# frozen_string_literal: true

# Detecta líneas de compra donde **la plata está bien y la cantidad no**.
#
# El filtro de IngredientPrices (OUTLIER_FACTOR) solo descarta precios más de 4
# veces fuera de la mediana, y hay errores que no llegan a tanto: media menta
# cargada como 0,5 kg cuando eran 0,2 por el mismo monto deja el precio unitario
# en la mitad, lo bastante raro para ensuciar las estadísticas y lo bastante
# normal para pasar el filtro. Apretar el filtro no es la salida: ya se midió, y
# bajarlo de 4x a 3x habría descartado seis compras reales de burrata.
#
# Por eso esto no mira el precio, mira el MONTO. Si una línea coincide al peso
# con otra compra del mismo insumo hecha al precio habitual, pero tiene cargada
# otra cantidad, lo que falla es la cantidad: el dinero que salió del local es
# el mismo. Eso además dice cuál era la cantidad correcta.
#
# No corrige nada. La corrección se hace en Fudo, que es donde está el dato; aquí
# solo se señala, igual que las compras dudosas.
class QuantityTypos
  # Qué cuenta como "comprado al precio habitual".
  NORMAL_BAND = 0.15
  # Cuánto tiene que desviarse el precio de la línea sospechosa. Alto a propósito:
  # con 10% se marcaban 180 líneas, casi todas fiambres y quesos que de verdad
  # varían de precio entre compras. Con 40% quedan 90, y el patrón es nítido.
  PRICE_TOL = 0.40
  # El monto tiene que coincidir al 0,5%: es la condición que sostiene todo.
  MONEY_TOL = 0.005
  # Mínimo para no confundir una cantidad distinta con la misma.
  QTY_TOL = 0.02
  # Compras al precio habitual necesarias para fiarse de ese precio.
  MIN_NORMAL = 4
  # Veces que la cantidad "correcta" tiene que haberse comprado de verdad. Con 1
  # cualquier cantidad suelta servía de coartada.
  MIN_REPEAT = 2

  Finding = Struct.new(:purchase, :normal_price, :twin, keyword_init: true) do
    def ingredient_id      = purchase.fudo_ingredient_id
    def name               = purchase.ingredient_name
    def unit               = purchase.unit_name.presence || "unidad"
    def on                 = purchase.purchased_on
    def provider           = purchase.provider_name
    def amount             = purchase.line_total.to_f
    def loaded_quantity    = purchase.quantity.to_f
    def loaded_price       = purchase.unit_price.to_f
    def suggested_quantity = twin.quantity.to_f
    def twin_on            = twin.purchased_on

    # Cuántas veces está inflada (o encogida) la cantidad cargada.
    def factor = suggested_quantity.zero? ? nil : loaded_quantity / suggested_quantity

    # Un factor limpio —x2, x10, x1000, x1,5, x30— es la huella de un error de
    # tipeo o de unidad: kilos por gramos, barril por litros, caja por unidades.
    # Un factor sucio (x1,67) puede ser perfectamente un precio que cambió, así
    # que se muestra igual pero sin afirmar tanto.
    def clean_factor?
      f = factor
      return false if f.nil? || f <= 0 || (f - 1).abs < 0.001

      [f, 1 / f].any? do |x|
        next false if x < 1.45

        medios = x * 2
        (medios - medios.round).abs / medios <= 0.01
      end
    end

    def confidence = clean_factor? ? :alta : :media
  end

  # Todas las líneas marcadas, de la más reciente a la más antigua.
  #
  # Mira SIEMPRE el historial completo, aunque la pantalla filtre por período:
  # el precio habitual de un insumo no puede depender de qué desplegable eligió
  # el usuario. Misma razón que ANCHOR_DAYS en IngredientPrices.
  def self.all
    nuevo.findings
  end

  def self.nuevo = new

  def findings = @findings ||= buscar.sort_by { |f| [-f.on.to_time.to_i, f.name.to_s] }

  def since(from) = findings.select { |f| f.on >= from }

  private

  def buscar
    IngredientPurchase.chronological.to_a.group_by(&:fudo_ingredient_id).flat_map do |_id, lineas|
      marcar(lineas)
    end
  end

  def marcar(lineas)
    normal = precio_habitual(lineas)
    return [] if normal.nil?

    normales = lineas.select { |l| cerca?(l.unit_price.to_f, normal, NORMAL_BAND) }
    return [] if normales.size < MIN_NORMAL

    frecuentes = cantidades_frecuentes(normales)
    return [] if frecuentes.empty?

    (lineas - normales).filter_map do |linea|
      next unless (linea.unit_price.to_f - normal).abs / normal >= PRICE_TOL

      gemela = gemela_de(linea, normales, frecuentes)
      Finding.new(purchase: linea, normal_price: normal, twin: gemela) if gemela
    end
  end

  # La mediana de todo el historial del insumo: no le afectan los extremos.
  def precio_habitual(lineas)
    precios = lineas.map { |l| l.unit_price.to_f }.sort
    return nil if precios.empty?

    mediana = precios[precios.size / 2]
    mediana.positive? ? mediana : nil
  end

  # Cantidades en las que el insumo se compra de verdad (vistas MIN_REPEAT veces
  # a precio normal): los formatos reales del proveedor.
  def cantidades_frecuentes(normales)
    normales.map { |l| l.quantity.to_f.round(4) }
            .tally.select { |cantidad, veces| cantidad.positive? && veces >= MIN_REPEAT }
            .keys.to_set
  end

  # La compra normal cuyo monto coincide con el de esta línea, con otra cantidad.
  def gemela_de(linea, normales, frecuentes)
    monto = linea.line_total.to_f
    return nil if monto.zero?

    normales.find do |n|
      cerca?(n.line_total.to_f, monto, MONEY_TOL) &&
        frecuentes.include?(n.quantity.to_f.round(4)) &&
        !cerca?(linea.quantity.to_f, n.quantity.to_f, QTY_TOL)
    end
  end

  def cerca?(valor, referencia, tolerancia)
    return false if referencia.zero?

    (valor - referencia).abs / referencia <= tolerancia
  end
end
