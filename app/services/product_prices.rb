# frozen_string_literal: true

# Los precios de venta, agrupando el mismo plato aunque en Fudo sean varios productos.
#
# "Margherita 32 cm" sale una sola vez, con sus canales al lado: PLATO, DELIVERY y
# APLICACION, cada uno con sus números.
#
# Tres precios por canal, y los tres dicen cosas distintas:
#   carta   -> el del catálogo de Fudo. Es lo que crees que cobras.
#   cobrado -> la mediana de lo realmente facturado. Es lo que cobras.
#   antes / ahora -> lo cobrado al principio y al final del período. Es cómo se movió.
#
# Mediana y no promedio, por lo mismo que en los insumos: el unitario de un producto se
# mueve dentro del día por los agregados —la Margherita 32 APLICACION salió a nueve
# precios distintos en un mes— y un promedio se iría detrás del que lleve más extras.
#
# El corte del período en dos bloques lo hace ComparisonWindow, compartido con el
# análisis de insumos.
class ProductPrices
  PERIODS = { "1" => "1 mes", "3" => "3 meses", "6" => "6 meses", "12" => "12 meses",
              "24" => "2 años", "all" => "Todo" }.freeze

  MIN_UNIDADES = 5 # por debajo de esto, la mediana de lo cobrado no dice nada

  # Ventas mínimas en cada extremo para fiarse de una variación. Mismo criterio que
  # MIN_CONFIDENCE en los insumos: con dos ventas a cada lado el porcentaje es ruido.
  MIN_CONFIDENCE = 3

  # Por debajo de esto es el mismo precio: redondeos y algún agregado suelto.
  STABLE_PCT = 1.0

  # "¿Está mi carta al día?" es una pregunta sobre HOY, no sobre el período elegido.
  # Por eso el desvío contra la carta mira siempre esta ventana fija, dé igual que
  # estés viendo 1 mes o 2 años. Con 12 meses entraban platos que no se venden desde
  # hace medio año: 72 en la lista en vez de los 22 que están vivos.
  VENTANA_CARTA = 30

  Canal = Struct.new(:channel, :product, :carta, :cobrado, :unidades, :precios_distintos,
                     :antes, :antes_n, :ahora, :ahora_n, :reciente, :reciente_n,
                     keyword_init: true) do
    def label = channel.presence || "único"

    # Cuánto se separa del precio de carta lo que se cobra en los últimos VENTANA_CARTA
    # días. Ni `cobrado` (la mediana del período entero: con 12 meses recoge lo que
    # valía antes de una subida y daba por descuadrada a la Coca Cola Zero por pasar de
    # $2.500 a $2.900 en mayo) ni `ahora` (que se mueve con el desplegable del período).
    # El catálogo dice el precio de hoy; se compara contra hoy.
    def desvio_pct
      return nil if carta.nil? || carta.zero? || reciente.nil?

      (reciente - carta) / carta * 100.0
    end

    # Cuánto se movió el precio cobrado DENTRO del período.
    def change_pct
      return nil if antes.nil? || ahora.nil? || antes.zero?

      (ahora - antes) / antes * 100.0
    end

    def fiable?     = unidades >= MIN_UNIDADES
    def comparable? = change_pct && [antes_n.to_i, ahora_n.to_i].min >= MIN_CONFIDENCE

    # Para la pregunta de la carta solo cuentan las ventas recientes: un plato que no se
    # vende desde hace medio año no dice nada sobre si su precio está bien hoy.
    def carta_fiable? = reciente_n.to_i >= MIN_UNIDADES

    def trend
      return "sin comparación" unless comparable?
      return "estable" if change_pct.abs < STABLE_PCT

      change_pct.positive? ? "alza" : "baja"
    end

    # Lo que ese movimiento vale en plata: las unidades vendidas por lo que cambió el
    # precio. Mismo criterio que spend_impact en insumos, y con las dos MISMAS medianas
    # que la variación, para que el signo no pueda contradecirla.
    def impacto
      return nil unless comparable?

      unidades * (ahora - antes)
    end
  end

  Grupo = Struct.new(:name, :canales, :unidades, :ingreso, keyword_init: true) do
    def multicanal? = canales.size > 1
    def vendidos    = canales.select { |c| c.unidades.positive? }

    # Un grupo "cuadra" cuando todos sus canales se cobran a su precio de carta.
    # Un grupo "cuadra" cuando todo lo que se vende HOY se cobra a su precio de carta.
    # Los canales sin ventas recientes no opinan: no se sabe y no se inventa.
    def cuadra?
      vivos = canales.select(&:carta_fiable?)
      return true if vivos.empty?

      vivos.all? { |c| c.desvio_pct && c.desvio_pct.abs < 1 }
    end

    # Variación del grupo: la de sus canales, ponderada por unidades vendidas, y solo
    # con los canales fiables. Un canal que vendió 3 unidades no puede mover el número.
    def change_pct
      comparables = canales.select(&:comparable?)
      peso = comparables.sum(&:unidades)
      return nil if peso.zero?

      comparables.sum { |c| c.change_pct * c.unidades } / peso
    end

    def impacto = canales.filter_map(&:impacto).sum
    def trend   = change_pct.nil? ? "sin comparación" : (change_pct.abs < STABLE_PCT ? "estable" : (change_pct.positive? ? "alza" : "baja"))
  end

  attr_reader :from, :to, :period_key

  def initialize(period: "3", from: nil, to: nil)
    @period_key = PERIODS.key?(period.to_s) ? period.to_s : "3"
    @to      = to   || SaleItem.last_sold_on || AppSettings.today
    @from    = from || default_from
    @ventana = ComparisonWindow.new(@from, @to)
  end

  delegate :split?, :window_days, :previous_from, to: :@ventana
  def compare_mode    = @ventana.mode
  def comparison_note = @ventana.note
  def period_label    = PERIODS[@period_key]

  def grupos
    @grupos ||= begin
      ventas = ventas_por_producto
      universo(ventas.keys).group_by(&:base_name).map { |base, productos|
        canales = productos.sort_by { |p| p.channel.to_s }
                           .map { |p| canal_de(p, ventas[p.fudo_product_id] || [],
                                               ventas_previas[p.fudo_product_id] || []) }
        Grupo.new(name: base, canales: canales,
                  unidades: canales.sum(&:unidades),
                  ingreso: canales.sum { |c| (c.cobrado || 0) * c.unidades })
      }.sort_by { |g| -g.ingreso }
    end
  end

  def con_ventas   = grupos.select { |g| g.unidades.positive? }
  def multicanal   = con_ventas.select(&:multicanal?)
  # Los que NO se cobran a su precio de carta: donde el catálogo y la realidad discrepan.
  def descuadrados = con_ventas.reject(&:cuadra?)

  def subieron = con_ventas.select { |g| g.trend == "alza" }
  def bajaron  = con_ventas.select { |g| g.trend == "baja" }

  # Variación media del menú, ponderada por lo que factura cada plato: que suba una
  # pizza de 777 unidades pesa más que una de 6.
  def menu_change_pct
    comparables = con_ventas.select { |g| g.change_pct }
    peso = comparables.sum(&:ingreso)
    return nil if peso.zero?

    comparables.sum { |g| g.change_pct * g.ingreso } / peso
  end

  private

  def default_from
    return SaleItem.first_sold_on || @to if @period_key == "all"

    @to.prev_month(@period_key.to_i) + 1
  end

  # Qué productos entran: los activos con precio MÁS cualquiera que haya vendido en el
  # período, esté activo o no.
  #
  # Lo segundo no es un extra: en el catálogo hay 24 productos marcados como inactivos
  # que siguen vendiendo, y entre ellos está el más vendido de todos —la Margherita 32
  # APLICACION, 419 unidades en tres meses—. Filtrando solo por `active` desaparecía del
  # informe el producto que más factura.
  def universo(ids_con_venta)
    Product.where(id: Product.activos.con_precio)
           .or(Product.where(fudo_product_id: ids_con_venta)).to_a
  end

  def canal_de(producto, ventas, previas)
    precios = ventas.map { |(_, p)| p.to_f }
    antes, ahora = extremos(ventas, previas)
    reciente = ventas_recientes[producto.fudo_product_id] || []
    Canal.new(
      channel: producto.channel, product: producto, carta: producto.price&.to_f,
      cobrado: ComparisonWindow.median(precios), unidades: precios.size,
      precios_distintos: precios.uniq.size,
      antes: ComparisonWindow.median(antes), antes_n: antes.size,
      ahora: ComparisonWindow.median(ahora), ahora_n: ahora.size,
      reciente: ComparisonWindow.median(reciente), reciente_n: reciente.size
    )
  end

  # Lo cobrado en los últimos VENTANA_CARTA días, al margen del período elegido.
  # Es la referencia para saber si el precio de carta está al día.
  def ventas_recientes
    @ventas_recientes ||= agrupar(@to - (VENTANA_CARTA - 1), @to)
                          .transform_values { |filas| filas.map(&:last) }
  end

  # Los dos extremos que se comparan, como en los insumos: las ventas de los primeros
  # window_days desde la primera venta del producto, contra las de los últimos
  # window_days hasta la última. En período corto, el período anterior contra este.
  def extremos(ventas, previas)
    ahora = ventas.map(&:last)
    return [previas.map(&:last), ahora] unless split?

    return [[], ahora] if ventas.empty?

    fechas  = ventas.map(&:first)
    primera = fechas.min
    ultima  = fechas.max
    # Sin recorrido suficiente no hay dos bloques: mejor sin comparación que inventada.
    return [[], ahora] if primera > ultima - window_days

    [ventas.select { |(d, _)| d <= primera + window_days }.map(&:last),
     ventas.select { |(d, _)| d >= ultima - window_days }.map(&:last)]
  end

  # [fecha, unitario] por producto dentro del período.
  def ventas_por_producto = @ventas_por_producto ||= agrupar(@from, @to)

  # Lo mismo para el período anterior: solo hace falta en modo :previous, y por eso no
  # se consulta si no se usa.
  def ventas_previas
    @ventas_previas ||= split? ? {} : agrupar(previous_from, @from - 1)
  end

  def agrupar(desde, hasta)
    SaleItem.cobradas.between(desde, hasta)
            .pluck(:fudo_product_id, :sold_on, :unit_price)
            .group_by(&:first)
            .transform_values { |filas| filas.map { |(_, d, p)| [d, p.to_f] } }
  end
end
