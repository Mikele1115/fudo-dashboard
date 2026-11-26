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
#   costo   -> lo que Fudo dice que cuesta hacerlo. Es lo que te deja.
#
# Ojo con el IVA, que es el error fácil aquí: el costo de Fudo es NETO y el precio de
# venta lleva IVA. Comprobado contra la cuenta real, cruzando el costo que Fudo da a
# cada insumo con lo que pagamos por él: razón mediana 1,000 sobre 127 insumos, 91 de
# ellos dentro del ±3%. Restarlos tal cual inflaría el margen unos 19 puntos, así que
# al precio se le quita el IVA antes de restar el costo.
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

    # El costo que Fudo guarda para este producto, neto de IVA. nil cuando no hay nada
    # cargado, que hoy es lo normal: 253 de las 281 filas del panel no tienen costo.
    def costo      = product.cost.to_f.positive? ? product.cost.to_f : nil
    def sin_costo? = costo.nil?

    # Lo que se cobra hoy, sin IVA, para poder restarle el costo. Misma ventana que el
    # desvío contra la carta: la pregunta «¿cuánto me deja?» es sobre hoy.
    def precio_neto
      base = reciente || cobrado
      base&.positive? ? base / (1 + AppSettings.vat_rate) : nil
    end

    def margen_pesos = costo && precio_neto ? precio_neto - costo : nil
    def margen_pct   = margen_pesos && precio_neto.positive? ? margen_pesos / precio_neto * 100 : nil

    # Costo por encima del precio: se señala y no se toca. Puede ser un plato gancho,
    # pero en la cuenta real es un costo mal cargado —el Pisco Norterra está a $99.999—.
    #
    # Salta por dos vías: contra la carta —vale para todos, incluidos los parados— y
    # contra lo que se cobra de verdad, que coge al que tiene la carta bien y cobra menos.
    def margen_negativo? = product.cost_impossible? || margen_pesos&.negative? || false

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

    # Un plato queda "sin costo" cuando NINGUNO de sus canales vendidos tiene costo.
    # Si un canal lo tiene, el costo de hacer el plato se conoce: vale para los demás.
    def sin_costo?  = vendidos.any? ? vendidos.all?(&:sin_costo?) : canales.all?(&:sin_costo?)
    def con_costo   = vendidos.reject(&:sin_costo?)
    def costo       = con_costo.filter_map(&:costo).min
    def margen_negativo? = con_costo.any?(&:margen_negativo?)

    # Margen del plato: el de sus canales con costo, ponderado por unidades vendidas.
    def margen_pct
      utiles = con_costo.select(&:margen_pct)
      peso = utiles.sum(&:unidades)
      return nil if peso.zero?

      utiles.sum { |c| c.margen_pct * c.unidades } / peso
    end

    def impacto = canales.filter_map(&:impacto).sum
    def trend   = change_pct.nil? ? "sin comparación" : (change_pct.abs < STABLE_PCT ? "estable" : (change_pct.positive? ? "alza" : "baja"))
  end

  attr_reader :from, :to, :period_key

  def initialize(period: "3", from: nil, to: nil, descatalogados: false)
    @period_key = PERIODS.key?(period.to_s) ? period.to_s : "3"
    @to      = to   || SaleItem.last_sold_on || AppSettings.today
    @from    = from || default_from
    @ventana = ComparisonWindow.new(@from, @to)
    @descatalogados = descatalogados
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

  # Platos sin ningún costo cargado en Fudo, y su peso en la facturación. Es el techo de
  # lo que se puede decir sobre márgenes: sin costo no hay margen que calcular.
  def sin_costo = con_ventas.select(&:sin_costo?)
  def con_costo = con_ventas.reject(&:sin_costo?)

  def ingreso_total     = con_ventas.sum(&:ingreso)
  def ingreso_sin_costo = sin_costo.sum(&:ingreso)

  def cobertura_costos_pct
    return nil if ingreso_total.zero?

    (ingreso_total - ingreso_sin_costo) / ingreso_total * 100.0
  end

  # Margen medio de lo que SÍ tiene costo, ponderado por lo que factura cada plato.
  # Solo habla de esa parte del menú, y la pantalla dice de qué parte se trata.
  def margen_pct
    utiles = con_costo.select(&:margen_pct)
    peso = utiles.sum(&:ingreso)
    return nil if peso.zero?

    utiles.sum { |g| g.margen_pct * g.ingreso } / peso
  end

  # Costos que no pueden ser: por encima de la carta sin IVA. Se recorre el catálogo
  # ENTERO y no solo lo vendido en el período, porque un producto parado conserva su
  # costo torcido y nadie lo mira. Filtrando por ventas se marcaban 5 de 13.
  def costos_sospechosos
    @costos_sospechosos ||= Product.where("cost > 0").select(&:cost_impossible?)
                                   .sort_by { |p| -p.cost_ratio }
  end

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

  # Qué productos entran: los activos con precio MÁS los inactivos que SIGUEN VENDIENDO.
  #
  # El `active` de Fudo no dice lo que parece. De 356 canales con ventas en 12 meses, 92
  # son de productos marcados como inactivos, y 19 de ellos siguen vendiendo: entre esos
  # está el más vendido de todos, la Margherita 32 APLICACION, con 531 unidades en los
  # últimos 30 días y $17M al año. Filtrar por `active` a secas borraría del informe el
  # producto que más factura.
  #
  # Los otros 73 son catálogo muerto —"Margherita Pedidos Ya", "Coda APA 500cc"— que solo
  # estorba. Esos sí quedan fuera, y el panel dice cuántos son y deja verlos a un clic.
  def universo(ids_con_venta)
    vivos = Product.activos.con_precio
    return Product.where(id: vivos).or(Product.where(fudo_product_id: ids_con_venta)).to_a if @descatalogados

    Product.where(id: vivos)
           .or(Product.where(fudo_product_id: ventas_recientes.keys)).to_a
  end

  public

  # Inactivos en Fudo que vendieron en el período pero ya no venden: fuera del informe
  # salvo que se pidan expresamente. Se cuentan para poder decirlo en pantalla.
  def descatalogados
    @descatalogados_lista ||= begin
      vivos = Product.activos.con_precio.pluck(:fudo_product_id).to_set
      ids   = ventas_por_producto.keys - ventas_recientes.keys.to_a
      Product.where(fudo_product_id: ids).reject { |p| vivos.include?(p.fudo_product_id) }
    end
  end

  def descatalogados? = @descatalogados

  private

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
