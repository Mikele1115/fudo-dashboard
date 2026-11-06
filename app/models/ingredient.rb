# frozen_string_literal: true

# Un insumo tal como está en Fudo, con la categoría que le pusiste en el POS.
#
# Fudo manda: la categoría se sincroniza desde ahí en cada actualización y no se
# edita en este dashboard. Si mueves un insumo de categoría en el POS, aquí se
# refleja solo. La subcategoría fina (Quesos, Embutidos…) sí vive aquí, en
# [[IngredientAssignment]], porque Fudo no la tiene.
class Ingredient < ApplicationRecord
  SIN_CATEGORIA = "Sin categoría"

  scope :ordered, -> { order(:fudo_category_name, :name) }

  # { fudo_id => nombre de su categoría en Fudo }
  def self.fudo_category_by_id
    pluck(:fudo_id, :fudo_category_name).to_h
  end

  # Nombres de las categorías de Fudo, de mayor a menor número de insumos.
  def self.fudo_category_names
    where.not(fudo_category_name: nil).group(:fudo_category_name).count
         .sort_by { |_, n| -n }.map(&:first)
  end

  def category_label = fudo_category_name.presence || SIN_CATEGORIA
end
