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

  # Ancho de las dos ventanas que se comparan. NO es fijo: se adapta al período.
  #
  # Con una ventana fija de 90 días, el período de "3 meses" (91 días) no daba
  # ninguna variación: las dos ventanas se solapaban enteras, así que ningún
  # insumo tenía contra qué compararse y la pantalla salía vacía.
  #
  # Ahora la ventana es un tercio del período —así siempre caben las dos, con
  # un hueco en medio— con un techo de 90 días para que en períodos largos no
  # se comparen trozos enormes, y un suelo de 21 para que no se compare ruido.
  MAX_WINDOW_DAYS = 90
  MIN_WINDOW_DAYS = 21

  # Historial mínimo sobre el que se calcula el "precio normal" de un insumo, la
  # mediana que decide qué compras son dudosas.
  #
  # Es a propósito INDEPENDIENTE del período elegido: con 3 o 6 meses hay pocas
  # compras, la mediana se vuelve frágil y datos malos que en 12 meses se
  # descartaban pasaban el corte. Pasó de verdad: una compra de mozzarella a
  # $1.768/kg (gramos cargados como kilos) se colaba en el período de 6 meses y
  # empujaba la canasta de +1,8% a +13,8%.
  #
  # Un insumo no puede cambiar de "precio normal" porque el usuario mueva un
  # desplegable, así que el ancla mira siempre al menos un año.
  ANCHOR_DAYS = 365

  # Compras mínimas en CADA extremo para fiarse de una variación. Por debajo, la
  # fila se marca "pocos datos" en pantalla y no entra en los números agregados
  # (la canasta, el impacto en pesos, el ranking de los que más encarecieron).
  #
  # Si entra, un insumo con dos compras en un extremo puede mover el índice
  # entero: la mozzarella, que es el 22% del gasto, llevaba la canasta de
  # 6 meses a +13,8% apoyada en una sola compra dudosa.
  MIN_CONFIDENCE = 3

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

    # Lo que pesa el movimiento de precios: comprando el mismo volumen, cuánto
    # más (o menos) se paga al precio de ahora que al del arranque del período.
    #
    # Era `spend - quantity * baseline_price`: lo realmente gastado contra lo que
    # habría costado todo al precio inicial. Suena parecido y no lo es, porque
    # mezcla dos estadísticas: `spend` lleva dentro el PROMEDIO pagado, y
    # `baseline_price` es una MEDIANA. El promedio sí absorbe las líneas sueltas
    # que la mediana está puesta a ignorar, así que aparecían ahorros de miles de
    # pesos en insumos que no se habían movido ni un peso:
    #
    #   Agua (Bidón): once compras a $2.800 y una a $1.750 dentro de la ventana
    #   inicial. Variación 0,0%, "ahorro" $4.200, que son solo esa línea.
    #   Menta: "ahorro" $9.550, que es una cantidad mal cargada (ver QuantityTypos).
    #
    # Doce de los catorce insumos fiables de Ingredientes Barra aportaban ahorro
    # sin haber cambiado de precio, y el número contradecía a la variación que
    # tenía al lado.
    #
    # Ahora usa las MISMAS dos medianas que change_pct. Un insumo que terminó al
    # precio que empezó da exactamente $0, y el signo no puede contradecir a la
    # variación porque es el mismo resto.
    #
    # Ojo al leerlo: es un "si compraras lo mismo al precio de ahora", no la plata
    # que salió de la caja. En períodos largos el volumen es grande y el número
    # también; por eso las pantallas lo dicen al lado.
    def spend_impact
      return nil if baseline_price.nil? || recent_price.nil? || change_pct.nil?

      quantity * (recent_price - baseline_price)
    end

    # ¿Hay bastantes compras en los dos extremos como para fiarse?
    def reliable?
      change_pct && [baseline_n, recent_n].min >= MIN_CONFIDENCE
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
  # Pondera por gasto para que un insumo de $18M pese más que uno de $5.000, y
  # solo suma comparaciones fiables (ver MIN_CONFIDENCE).
  def basket_change_pct
    comparable = reliable_rows.select { |r| r.spend.positive? }
    return nil if comparable.empty?

    weight = comparable.sum(&:spend)
    weight.zero? ? nil : comparable.sum { |r| r.change_pct * r.spend } / weight
  end

  def reliable_rows = @reliable_rows ||= rows.select(&:reliable?)

  # Cuántas filas quedaron fuera de los agregados por falta de datos.
  def unreliable_count = rows.count { |r| r.change_pct && !r.reliable? }

  def spend_impact_total = reliable_rows.filter_map(&:spend_impact).sum

  def rising  = rows.select { |r| r.trend == "alza" }
  def falling = rows.select { |r| r.trend == "baja" }

  def top_rising(n = 5)  = rising.sort_by { |r| -r.change_pct }.first(n)
  def top_falling(n = 5) = falling.sort_by(&:change_pct).first(n)
  def top_spend(n = 5)   = rows.sort_by { |r| -r.spend }.first(n)

  # Los que más encarecieron la cuenta en pesos (alza x volumen comprado).
  # Solo los fiables: este ranking se usa para decidir con quién negociar.
  def costliest_rises(n = 5)
    reliable_rows.select { |r| (r.spend_impact || 0).positive? && r.trend == "alza" }
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

  Group = Struct.new(:key, :name, :rows, :spend, :share, :change_pct,
                     :spend_impact, :reliable_count, :unreliable_count, keyword_init: true) do
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
      #
      # Y, también igual que la canasta, solo entran las comparaciones FIABLES
      # (ver MIN_CONFIDENCE). Antes entraban todas, así que la misma categoría
      # daba un número distinto según la pantalla desde la que se mirara, y lo
      # peor: un insumo con una sola compra en cada extremo movía el total.
      # Pasó con Ingredientes Barra en 3 meses: salía +0,35% y un "ahorro" de
      # $40.166 del que $10.321 eran un licor comparado con 1 compra contra 1.
      # Con solo fiables: +0,98% y $26.444.
      fiables = grupo.select { |r| r.reliable? && r.spend.positive? }
      peso    = fiables.sum(&:spend)
      Group.new(
        key:              clave,
        name:             clave.is_a?(IngredientCategory) ? clave.name : (clave || "Sin subcategoría"),
        rows:             grupo,
        spend:            gasto,
        share:            total.positive? ? gasto / total * 100.0 : 0.0,
        change_pct:       peso.zero? ? nil : fiables.sum { |r| r.change_pct * r.spend } / peso,
        spend_impact:     fiables.filter_map(&:spend_impact).sum,
        reliable_count:   fiables.size,
        unreliable_count: grupo.count { |r| r.change_pct && !r.reliable? }
      )
    end
  end

  public

  def period_label = PERIODS[@period_key]

  # Un tercio del período, entre 21 y 90 días.
  def window_days
    @window_days ||= begin
      tercio = ((@to - @from).to_i / 3.0).floor
      tercio.clamp(MIN_WINDOW_DAYS, MAX_WINDOW_DAYS)
    end
  end

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

  # Precio "normal" de cada insumo: la mediana de un historial amplio, no la del
  # período elegido. Ver ANCHOR_DAYS.
  def anchor_medians
    @anchor_medians ||= begin
      desde = [@from, @to - ANCHOR_DAYS].min
      IngredientPurchase.between(desde, @to)
                        .pluck(:fudo_ingredient_id, :unit_price)
                        .group_by(&:first)
                        .transform_values { |pares| self.class.median(pares.map { |(_, precio)| precio.to_f }) }
    end
  end

  def build_row(ingredient_id, list)
    # El ancla viene del historial amplio; si el insumo no tuviera nada ahí, se
    # cae a la mediana del propio período.
    median = anchor_medians[ingredient_id] || self.class.median(list.map { |p| p.unit_price.to_f })
    return nil if median.nil? || median.zero?

    clean, suspicious = list.partition { |p| plausible?(p.unit_price.to_f, median) }
    return nil if clean.empty?

    prices = clean.map { |p| p.unit_price.to_f }
    qty    = clean.sum { |p| p.quantity.to_f }
    spend  = clean.sum { |p| p.line_total.to_f }
    last   = clean.last

    # Sin dos ventanas separadas no hay variación que medir (insumo nuevo o de compra única).
    single_window = clean.first.purchased_on > last.purchased_on - window_days
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

  # Precios de las compras dentro de los `window_days` siguientes (o anteriores) a una fecha.
  def window_prices(clean, anchor, direction)
    range = direction == :forward ? (anchor..anchor + window_days) : (anchor - window_days..anchor)
    clean.select { |p| range.cover?(p.purchased_on) }.map { |p| p.unit_price.to_f }
  end
end
