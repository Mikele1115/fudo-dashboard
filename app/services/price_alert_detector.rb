# frozen_string_literal: true

# Detecta compras en las que un insumo salió bastante más caro de lo habitual.
#
# Los umbrales no son inventados: se midieron contra 12 meses de compras reales
# del local (1.546 comparaciones). Avisar por porcentaje a secas daba 137 avisos
# al año con +15% —más de uno cada tres días, imposible de leer—. Al exigir
# además que el insumo pese en el gasto anual y que el salto haya costado dinero
# de verdad, bajan a unos 34 al año (~3 al mes), todos con un motivo económico.
#
# Dato revelador de esa medición: con los filtros de dinero puestos, mover el
# umbral de +10% a +30% solo quita 4 avisos al año. El que hace el trabajo es el
# filtro de plata, no el porcentaje.
#
# Tres decisiones de diseño que evitan falsos positivos:
#
#   - Se compara contra la MEDIANA de las compras recientes del insumo, no contra
#     la compra anterior. Hay insumos cuyo precio oscila entre dos valores (dos
#     formatos, dos proveedores): comparando con la anterior, la Salsiccia saltaba
#     "+150%" una y otra vez sin estar subiendo.
#   - Se ignoran las compras marcadas como dudosas por IngredientPrices (gramos
#     cargados como kilos y similares). Si no, cada error de carga sería una alerta.
#   - Ese filtro solo descarta lo que está más de 4x fuera de la mediana, y hay errores
#     más chicos que pasan: cargar 0,72 kg de lo que fueron 1,8 deja el precio 2,6 veces
#     alto, no 4. Por eso, antes de avisar, se le pregunta a QuantityTypos si el MONTO de
#     la línea coincide al peso con otra compra al precio habitual. Si coincide, la plata
#     que salió es la misma y la alerta se guarda marcada como cantidad mal cargada: el
#     correo manda a revisar la carga en vez de anunciar una subida que no hubo.
class PriceAlertDetector
  CHANGE_PCT    = 15.0    # subida mínima respecto a la mediana reciente
  MIN_OVERCOST  = 20_000  # lo que esa compra costó de más, en pesos
  MIN_SPEND     = 500_000 # gasto anual del insumo: por debajo, no mueve la aguja
  HISTORY_DAYS  = 365     # ventana para la mediana y el gasto anual
  BASELINE_MIN  = 3       # compras previas mínimas para tener una referencia fiable
  COOLDOWN_DAYS = 14      # no repetir aviso del mismo insumo dentro de este plazo

  def self.run!(since: nil) = new.run!(since: since)

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  # Revisa las compras desde `since` (por defecto, la última semana) y crea las
  # alertas que falten. Es idempotente: una compra ya avisada no se duplica.
  def run!(since: nil)
    since ||= AppSettings.today - 7
    nuevas = []

    IngredientPurchase.where(purchased_on: since..).chronological.each do |purchase|
      next if PriceAlert.exists?(fudo_item_id: purchase.fudo_item_id)

      alert = evaluate(purchase)
      nuevas << alert if alert
    end

    @logger.info "PriceAlertDetector: #{nuevas.size} alertas nuevas desde #{since}"
    nuevas
  end

  private

  # Devuelve la PriceAlert creada, o nil si esta compra no merece aviso.
  def evaluate(purchase)
    history = IngredientPurchase
              .where(fudo_ingredient_id: purchase.fudo_ingredient_id)
              .where(purchased_on: (purchase.purchased_on - HISTORY_DAYS)...purchase.purchased_on)
              .chronological.to_a
    return nil if history.size < BASELINE_MIN

    prices = history.map { |p| p.unit_price.to_f }
    median = IngredientPrices.median(prices)
    return nil if median.nil? || median.zero?

    # Fuera las compras dudosas: ni la que evaluamos ni las que forman la referencia.
    new_price = purchase.unit_price.to_f
    return nil unless plausible?(new_price, median)

    clean = prices.select { |p| plausible?(p, median) }
    return nil if clean.size < BASELINE_MIN

    baseline = IngredientPrices.median(clean)
    return nil if baseline.nil? || baseline.zero?

    change = (new_price - baseline) / baseline * 100.0
    return nil if change < CHANGE_PCT

    overcost = (new_price - baseline) * purchase.quantity.to_f
    return nil if overcost < MIN_OVERCOST
    return nil if annual_spend(purchase) < MIN_SPEND
    return nil if recently_alerted?(purchase)

    # Un precio unitario disparado también sale de cargar menos cantidad de la que se
    # compró. Si el monto de la línea coincide al peso con otra compra al precio habitual,
    # la plata que salió es la misma y lo que está mal es la cantidad: se avisa igual,
    # porque hay algo que revisar, pero marcado como carga y no como subida de precio.
    twin = QuantityTypos.twin_for(purchase)

    PriceAlert.create!(
      fudo_item_id:       purchase.fudo_item_id,
      fudo_ingredient_id: purchase.fudo_ingredient_id,
      ingredient_name:    purchase.ingredient_name,
      unit_name:          purchase.unit_name,
      provider_name:      purchase.provider_name,
      purchased_on:       purchase.purchased_on,
      baseline_price:     baseline,
      new_price:          new_price,
      change_pct:         change,
      overcost:           overcost,
      quantity:           purchase.quantity,
      suspect_quantity:   twin.present?,
      twin_quantity:      twin&.quantity,
      twin_purchased_on:  twin&.purchased_on
    )
  end

  def plausible?(price, median)
    price.positive? &&
      price <= median * IngredientPrices::OUTLIER_FACTOR &&
      price >= median / IngredientPrices::OUTLIER_FACTOR
  end

  def annual_spend(purchase)
    IngredientPurchase
      .where(fudo_ingredient_id: purchase.fudo_ingredient_id)
      .where(purchased_on: (purchase.purchased_on - HISTORY_DAYS)..purchase.purchased_on)
      .sum(:line_total).to_f
  end

  # Evita avisar dos veces de lo mismo: si ya se avisó hace poco de este insumo,
  # se calla salvo que el precio haya seguido subiendo de forma clara.
  def recently_alerted?(purchase)
    last = PriceAlert.where(fudo_ingredient_id: purchase.fudo_ingredient_id)
                     .where(purchased_on: (purchase.purchased_on - COOLDOWN_DAYS)..purchase.purchased_on)
                     .recent.first
    return false if last.nil?

    purchase.unit_price.to_f <= last.new_price.to_f * 1.10
  end
end
