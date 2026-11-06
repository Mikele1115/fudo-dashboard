# frozen_string_literal: true

# Análisis del comportamiento de los precios de compra de los insumos.
#
# Trabaja sobre ingredient_purchases (precios NETOS, sin IVA: ver Fudo::Client).
#
# Por qué no se compara simplemente el primer precio con el último:
# en los datos reales hay líneas mal cargadas (cantidad en gramos donde iba en
# kilos, o al revés). Eso produce precios unitarios absurdos —mozzarella a
# $1.768/kg cuando el promedio real es $6.708— y un solo dato así arruina
# cualquier comparación. Por eso aquí:
#
#   1. se toma la MEDIANA de cada insumo como ancla (no le afectan los extremos),
#   2. se marcan como sospechosas las compras que se alejan más de OUTLIER_FACTOR
#      veces de esa mediana, y se excluyen de las estadísticas,
#   3. las variaciones se calculan entre MEDIANAS de dos ventanas de tiempo,
#      no entre dos compras sueltas.
#
# Las compras sospechosas no se borran: se listan aparte para poder corregirlas
# en Fudo.
class IngredientPrices
  PERIODS = { "3" => "3 meses", "6" => "6 meses", "12" => "12 meses", "24" => "2 años", "all" => "Todo" }.freeze
  STABLE_PCT     = 2.0 # variaciones de menos de ±2% se consideran precio estable
  OUTLIER_FACTOR = 4.0 # veces por encima o por debajo de la mediana para marcar sospechosa
  WINDOW_DAYS    = 90  # ancho de las ventanas inicial y reciente que se comparan

  def self.median(values)
    return nil if values.empty?

    s = values.sort
    mid = s.size / 2
    s.size.odd? ? s[mid] : (s[mid - 1] + s[mid]) / 2.0
  end

  # Resumen de un insumo en el período.
  Row = Struct.new(
    :ingredient_id, :name, :unit, :providers,
    :clean, :suspicious, # compras limpias y sospechosas
    :median_price, :baseline_price, :baseline_n, :recent_price, :recent_n,
    :min_price, :min_date, :max_price, :max_date,
    :avg_price, :quantity, :spend, :last_date, :series,
    keyword_init: true
  ) do
    def purchases_count  = clean.size
    def suspicious_count = suspicious.size

    # Variación del precio: mediana de la ventana reciente vs. mediana de la inicial.
    def change_pct
      return nil if baseline_price.nil? || recent_price.nil? || baseline_price.zero?

      (recent_price - baseline_price) / baseline_price * 100.0
    end

    # Cuánto costó de más (o de menos) el movimiento de precios, sobre lo comprado.
    def spend_impact
      return nil if baseline_price.nil? || change_pct.nil?

      spend - (quantity * baseline_price)
    end

    def trend
      c = change_pct
      return "nuevo" if c.nil?
      return "estable" if c.abs < STABLE_PCT

      c.positive? ? "alza" : "baja"
    end

    # Recorrido del precio ya limpio: si sigue siendo alto, el precio es volátil de verdad.
    def volatility_pct
      return nil if min_price.nil? || min_price.zero? || purchases_count < 2

      (max_price - min_price) / min_price * 100.0
    end

    def unit_label = unit.presence || "unidad"
  end

  attr_reader :from, :to, :period_key

  def initialize(period: "12", from: nil, to: nil)
    @period_key = PERIODS.key?(period.to_s) ? period.to_s : "12"
    @to   = to || IngredientPurchase.last_purchase_date || AppSettings.today
    @from = from || default_from
  end

  def rows = @rows ||= build_rows

  def any? = IngredientPurchase.exists?

  # ---------- totales del período ----------

  def total_spend       = rows.sum(&:spend)
  def ingredients_count = rows.size
  def purchases_count   = rows.sum(&:purchases_count)
  def suspicious_count  = rows.sum(&:suspicious_count)

  # Insumos con líneas sospechosas, para revisar la carga en Fudo.
  def to_review = rows.select { |r| r.suspicious_count.positive? }.sort_by { |r| -r.suspicious_count }

  # Variación media ponderada por gasto: cuánto se movió "la canasta" del local.
  # Pondera por gasto para que un insumo de $18M pese más que uno de $5.000.
  def basket_change_pct
    comparable = rows.select { |r| r.change_pct && r.spend.positive? }
    return nil if comparable.empty?

    weight = comparable.sum(&:spend)
    weight.zero? ? nil : comparable.sum { |r| r.change_pct * r.spend } / weight
  end

  def spend_impact_total = rows.filter_map(&:spend_impact).sum

  def rising  = rows.select { |r| r.trend == "alza" }
  def falling = rows.select { |r| r.trend == "baja" }

  def top_rising(n = 5)  = rising.sort_by { |r| -r.change_pct }.first(n)
  def top_falling(n = 5) = falling.sort_by(&:change_pct).first(n)
  def top_spend(n = 5)   = rows.sort_by { |r| -r.spend }.first(n)

  # Los que más encarecieron la cuenta en pesos (alza x volumen comprado).
  def costliest_rises(n = 5)
    rows.select { |r| (r.spend_impact || 0).positive? && r.trend == "alza" }
        .sort_by { |r| -r.spend_impact }.first(n)
  end

  def sorted(key)
    case key
    when "spend"  then rows.sort_by { |r| -r.spend }
    when "name"   then rows.sort_by { |r| r.name.to_s.downcase }
    when "recent" then rows.sort_by { |r| [-(r.last_date&.to_time&.to_i || 0), r.name.to_s] }
    when "drop"   then rows.sort_by { |r| r.change_pct || Float::INFINITY }
    when "impact" then rows.sort_by { |r| -(r.spend_impact || -Float::INFINITY) }
    else               rows.sort_by { |r| -(r.change_pct || -Float::INFINITY) } # "rise" (por defecto)
    end
  end


  # ---------- desglose en dos niveles ----------
  #
  # Nivel 1: la categoría de Fudo (Ingredientes Pizza, Barra, Barriles…). Es la
  #   que el usuario mantiene en el POS, así que manda y no se edita aquí.
  # Nivel 2: la subcategoría fina (Quesos, Embutidos, Verduras…), que Fudo no
  #   tiene. "Ingredientes Pizza" es el 75% del gasto: sin este detalle no se
  #   distingue si subió el queso o la harina.
  #
  # El nivel 2 NO es una jerarquía fija: una subcategoría puede aparecer dentro
  # de dos categorías de Fudo si sus insumos están repartidos. Se agrupa por
  # insumo, no por un árbol predefinido.

  Group = Struct.new(:key, :name, :rows, :spend, :share, :change_pct, keyword_init: true) do
    def ingredients_count = rows.size
    def sin_categoria?    = key.nil?
  end

  # { fudo_ingredient_id => IngredientCategory } (la subcategoría fina)
  def assignments = @assignments ||= IngredientAssignment.category_by_ingredient

  # { fudo_ingredient_id => nombre de su categoría en Fudo }
  def fudo_categories = @fudo_categories ||= Ingredient.fudo_category_by_id

  def fudo_category_for(row)
    fudo_categories[row.ingredient_id].presence || Ingredient::SIN_CATEGORIA
  end

  # Nivel 1: las categorías de Fudo, de mayor a menor gasto.
  def grouped_by_fudo_category
    @grouped_by_fudo_category ||= build_groups { |r| fudo_category_for(r) }.sort_by { |g| -g.spend }
  end

  # Nivel 2: las subcategorías dentro de una categoría de Fudo.
  def subcategories_of(fudo_category_name)
    @subcategories ||= {}
    @subcategories[fudo_category_name] ||= begin
      dentro = rows.select { |r| fudo_category_for(r) == fudo_category_name }
      build_groups(dentro) { |r| assignments[r.ingredient_id] }.sort_by { |g| -g.spend }
    end
  end

  def uncategorized = rows.reject { |r| assignments[r.ingredient_id] }

  # Agrupa por subcategoría fina sobre todo el período (para su página propia).
  def grouped_by_subcategory
    @grouped_by_subcategory ||= build_groups { |r| assignments[r.ingredient_id] }.sort_by { |g| -g.spend }
  end

  private

  def build_groups(subconjunto = nil)
    total = total_spend
    (subconjunto || rows).group_by { |r| yield(r) }.map do |clave, grupo|
      gasto = grupo.sum(&:spend)
      # La variación del grupo se pondera por gasto, igual que la canasta:
      # un insumo de $18M debe pesar más que uno de $5.000.
      comparables = grupo.select { |r| r.change_pct && r.spend.positive? }
      peso = comparables.sum(&:spend)
      Group.new(
        key:        clave,
        name:       clave.is_a?(IngredientCategory) ? clave.name : (clave || "Sin subcategoría"),
        rows:       grupo,
        spend:      gasto,
        share:      total.positive? ? gasto / total * 100.0 : 0.0,
        change_pct: peso.zero? ? nil : comparables.sum { |r| r.change_pct * r.spend } / peso
      )
    end
  end

  public

  def period_label = PERIODS[@period_key]
  def window_days  = WINDOW_DAYS

  private

  def default_from
    case @period_key
    when "all" then IngredientPurchase.first_purchase_date || @to
    else @to.prev_month(@period_key.to_i) + 1
    end
  end

  def build_rows
    IngredientPurchase.between(@from, @to).chronological
                      .group_by(&:fudo_ingredient_id)
                      .filter_map { |id, list| build_row(id, list) }
  end

  def build_row(ingredient_id, list)
    median = self.class.median(list.map { |p| p.unit_price.to_f })
    return nil if median.nil? || median.zero?

    clean, suspicious = list.partition { |p| plausible?(p.unit_price.to_f, median) }
    return nil if clean.empty?

    prices = clean.map { |p| p.unit_price.to_f }
    qty    = clean.sum { |p| p.quantity.to_f }
    spend  = clean.sum { |p| p.line_total.to_f }
    last   = clean.last

    # Sin dos ventanas separadas no hay variación que medir (insumo nuevo o de compra única).
    single_window = clean.first.purchased_on > last.purchased_on - WINDOW_DAYS
    baseline = single_window ? [] : window_prices(clean, clean.first.purchased_on, :forward)
    recent   = window_prices(clean, last.purchased_on, :backward)

    Row.new(
      ingredient_id:  ingredient_id,
      name:           last.ingredient_name,
      unit:           last.unit_name,
      providers:      clean.filter_map(&:provider_name).uniq,
      clean:          clean,
      suspicious:     suspicious,
      median_price:   self.class.median(prices),
      baseline_price: self.class.median(baseline),
      baseline_n:     baseline.size,
      recent_price:   self.class.median(recent),
      recent_n:       recent.size,
      min_price:      prices.min,
      min_date:       clean[prices.index(prices.min)].purchased_on,
      max_price:      prices.max,
      max_date:       clean[prices.index(prices.max)].purchased_on,
      # Promedio ponderado por cantidad: el precio que de verdad se pagó.
      avg_price:      qty.positive? ? spend / qty : nil,
      quantity:       qty,
      spend:          spend,
      last_date:      last.purchased_on,
      series:         clean.map { |p| [p.purchased_on, p.unit_price.to_f] }
    )
  end

  # Una compra es plausible si su precio no se aleja más de OUTLIER_FACTOR veces de la mediana.
  def plausible?(price, median)
    return false unless price.positive?

    price <= median * OUTLIER_FACTOR && price >= median / OUTLIER_FACTOR
  end

  # Precios de las compras dentro de los WINDOW_DAYS siguientes (o anteriores) a una fecha.
  def window_prices(clean, anchor, direction)
    range = direction == :forward ? (anchor..anchor + WINDOW_DAYS) : (anchor - WINDOW_DAYS..anchor)
    clean.select { |p| range.cover?(p.purchased_on) }.map { |p| p.unit_price.to_f }
  end
end
