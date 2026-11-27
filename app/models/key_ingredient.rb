# frozen_string_literal: true

# Un insumo clave de la pizzería (la mozzarella, la harina…): una subida pequeña ya duele.
#
# Para estos, PriceAlertDetector usa un umbral propio y se salta los filtros de dinero
# (sobrecosto mínimo y gasto anual): que sea clave lo decide una persona, no el gasto.
# Se guarda por `fudo_ingredient_id`, como IngredientAssignment, para sobrevivir a la
# sincronización del catálogo y a los renombres en Fudo.
class KeyIngredient < ApplicationRecord
  DEFAULT_PCT = 5.0 # subida mínima sobre la mediana reciente; el general es PriceAlertDetector::CHANGE_PCT

  validates :fudo_ingredient_id, presence: true, uniqueness: true
  validates :ingredient_name, presence: true
  validates :change_pct, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true

  scope :ordered, -> { order(:ingredient_name) }

  # { fudo_ingredient_id => KeyIngredient }
  def self.by_ingredient = all.index_by(&:fudo_ingredient_id)

  def threshold = (change_pct || DEFAULT_PCT).to_f
end
