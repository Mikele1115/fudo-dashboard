# frozen_string_literal: true

# A qué categoría pertenece un insumo de Fudo.
#
# Se guarda por `fudo_ingredient_id`, no por nombre: en Fudo los insumos se
# renombran y la asignación no debe perderse por eso. `ingredient_name` es solo
# una copia para poder leer la tabla a simple vista.
#
# `automatic` distingue lo que puso una regla de lo que decidió el usuario:
# al volver a aplicar las reglas, lo que tocó una persona nunca se pisa.
class IngredientAssignment < ApplicationRecord
  belongs_to :ingredient_category

  validates :fudo_ingredient_id, presence: true, uniqueness: true

  scope :manual,    -> { where(automatic: false) }
  scope :automatic, -> { where(automatic: true) }

  # { fudo_ingredient_id => IngredientCategory }
  def self.category_by_ingredient
    includes(:ingredient_category).to_h { |a| [a.fudo_ingredient_id, a.ingredient_category] }
  end
end
