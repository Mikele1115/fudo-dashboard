# frozen_string_literal: true

# Una linea de compra de insumo (una linea de un egreso de Fudo).
# El precio unitario es neto, sin IVA: ver Fudo::Client#ingredient_purchases.
class IngredientPurchase < ApplicationRecord
  scope :between,    ->(from, to) { where(purchased_on: from..to) }
  scope :newest,     -> { order(purchased_on: :desc, id: :desc) }
  scope :chronological, -> { order(purchased_on: :asc, id: :asc) }

  # Nombre actual de cada insumo: el de su compra mas reciente.
  # (En Fudo se pueden renombrar; el historico guarda el nombre del momento.)
  def self.current_names
    newest.pluck(:fudo_ingredient_id, :ingredient_name, :unit_name)
          .each_with_object({}) { |(id, name, unit), h| h[id] ||= { name: name, unit: unit } }
  end

  def self.first_purchase_date = minimum(:purchased_on)
  def self.last_purchase_date  = maximum(:purchased_on)
end
