# frozen_string_literal: true

# Categoría de insumos, dentro de un área del restaurante.
# Dos niveles a propósito: el área responde "cuánto gasta el bar" y la
# categoría "cuánto gasto en quesos", sin tener que elegir entre las dos.
class IngredientCategory < ApplicationRecord
  AREAS = ["Cocina", "Bar", "Envases", "Limpieza", "Otros"].freeze

  has_many :ingredient_assignments, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :area, inclusion: { in: AREAS }

  scope :ordered, -> { order(:area, :position, :name) }

  # Agrupadas por área, en el orden de AREAS.
  def self.by_area
    ordered.group_by(&:area).sort_by { |area, _| AREAS.index(area) || 99 }
  end

  def label = "#{area} · #{name}"
end
