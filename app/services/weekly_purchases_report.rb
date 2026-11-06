# frozen_string_literal: true

# Resumen semanal de las compras de insumos: qué se compró, cuánto se gastó,
# qué se movió de precio y qué quedó mal cargado.
#
# La semana va de lunes a viernes (el informe sale el viernes por la noche).
class WeeklyPurchasesReport
  Line = Struct.new(:ingredient_id, :name, :unit, :quantity, :spend, :purchases,
                    :last_price, :prev_price, :providers, keyword_init: true) do
    # Variación respecto a lo que se pagaba antes de esta semana.
    # nil cuando falta alguno de los dos precios limpios: sin referencia no se compara.
    def change_pct
      return nil if last_price.nil? || prev_price.nil? || prev_price.zero?

      (last_price - prev_price) / prev_price * 100.0
    end

    def unit_label = unit.presence || "unidad"
  end

  attr_reader :from, :to

  # `on` es el día del envío y el informe cubre la SEMANA ANTERIOR COMPLETA,
  # de lunes a domingo. El correo sale el lunes a mediodía: si cubriera "desde
  # el lunes hasta hoy" llegaría con solo la mañana de ese mismo día.
  #
  # Enviado el lunes 9, cubre del lunes 2 al domingo 8.
  def initialize(on = AppSettings.today)
    lunes_de_esta_semana = on - ((on.wday - 1) % 7)
    @from = lunes_de_esta_semana - 7
    @to   = lunes_de_esta_semana - 1
  end

  def purchases = @purchases ||= IngredientPurchase.between(@from, @to).chronological.to_a

  def any? = purchases.any?

  def spend      = purchases.sum { |p| p.line_total.to_f }
  def count      = purchases.size
  def ingredients_count = purchases.map(&:fudo_ingredient_id).uniq.size
  def providers  = purchases.filter_map(&:provider_name).tally.sort_by { |_, n| -n }

  # La semana de antes, para comparar.
  def previous
    @previous ||= self.class.new(@from) # su "semana anterior" es la de antes de esta
  end

  def spend_change_pct
    base = previous.spend
    return nil if base.zero?

    (spend - base) / base * 100.0
  end

  # Detalle por insumo, ordenado por gasto.
  #
  # El gasto suma TODAS las lineas (es la plata que de verdad salio), pero los
  # precios que se comparan salen solo de las limpias. Sin esto, una linea con el
  # total en cero aparecia como "bajo -100%", que no es una bajada sino un error
  # de carga; y los gramos cargados como kilos daban subidas imaginarias.
  def lines
    @lines ||= purchases.group_by(&:fudo_ingredient_id).map do |id, list|
      last  = list.last
      clean = list.reject { |p| suspicious_ids.include?(p.fudo_item_id) }
      Line.new(
        ingredient_id: id,
        name:          last.ingredient_name,
        unit:          last.unit_name,
        quantity:      list.sum { |p| p.quantity.to_f },
        spend:         list.sum { |p| p.line_total.to_f },
        purchases:     list.size,
        last_price:    clean.last&.unit_price&.to_f,
        prev_price:    previous_price_for(id),
        providers:     list.filter_map(&:provider_name).uniq
      )
    end.sort_by { |l| -l.spend }
  end

  def top_spend(n = 10) = lines.first(n)

  # Insumos que subieron de precio respecto a antes de esta semana.
  def rising(n = 10)
    lines.select { |l| l.change_pct && l.change_pct >= 2 }.sort_by { |l| -l.change_pct }.first(n)
  end

  def falling(n = 5)
    lines.select { |l| l.change_pct && l.change_pct <= -2 }.sort_by(&:change_pct).first(n)
  end

  # Insumos comprados por primera vez esta semana.
  def first_time
    ids = purchases.map(&:fudo_ingredient_id).uniq
    previos = IngredientPurchase.where(fudo_ingredient_id: ids)
                                .where(purchased_on: ...@from)
                                .distinct.pluck(:fudo_ingredient_id).to_set
    lines.reject { |l| previos.include?(l.ingredient_id) }
  end

  def alerts = @alerts ||= PriceAlert.between(@from, @to).recent.to_a

  # Líneas cargadas esta semana con un precio fuera de rango: para corregirlas en Fudo.
  def suspicious
    @suspicious ||= begin
      semana = purchases.map(&:fudo_item_id).to_set
      price_analysis.rows.flat_map(&:suspicious).select { |p| semana.include?(p.fudo_item_id) }
    end
  end


  # Gasto de la semana por categoría de Fudo (Ingredientes Pizza, Barra…), con la
  # semana anterior al lado. Devuelve [{ area:, spend:, previous:, share: }, ...].
  def by_area
    @by_area ||= begin
      cats   = Ingredient.fudo_category_by_id
      actual = agrupar_por_area(purchases, cats)
      pasada = agrupar_por_area(previous.purchases, cats)
      total  = spend

      actual.map { |area, gasto|
        { area: area, spend: gasto, previous: pasada[area] || 0.0,
          share: total.positive? ? gasto / total * 100.0 : 0.0 }
      }.sort_by { |h| -h[:spend] }
    end
  end

  def subject
    "Compras de la semana — #{money_label(spend)} en #{count} compras"
  end

  private

  def agrupar_por_area(lineas, cats)
    lineas.each_with_object(Hash.new(0.0)) do |p, h|
      area = cats[p.fudo_ingredient_id].presence || Ingredient::SIN_CATEGORIA
      h[area] += p.line_total.to_f
    end
  end

  # Último precio limpio pagado por ese insumo ANTES de esta semana.
  def previous_price_for(ingredient_id)
    IngredientPurchase.where(fudo_ingredient_id: ingredient_id)
                      .where(purchased_on: ...@from)
                      .chronological.to_a
                      .reject { |p| suspicious_ids.include?(p.fudo_item_id) }
                      .last&.unit_price&.to_f
  end

  # Ids de las lineas que IngredientPrices considera fuera de rango.
  def suspicious_ids
    @suspicious_ids ||= price_analysis.rows.flat_map(&:suspicious).map(&:fudo_item_id).to_set
  end

  def price_analysis = @price_analysis ||= IngredientPrices.new(period: "12", to: @to)

  # El asunto del correo no pasa por los helpers de la vista.
  def money_label(n)
    sym = AppSettings.currency_symbol
    "#{sym}#{n.round.to_s.reverse.scan(/\d{1,3}/).join('.').reverse}"
  end
end
