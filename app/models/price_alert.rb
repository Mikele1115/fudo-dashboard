# frozen_string_literal: true

# Aviso de que un insumo se compró bastante más caro de lo habitual.
# Lo crea PriceAlertDetector después de cada sincronización de compras.
class PriceAlert < ApplicationRecord
  scope :recent,       -> { order(purchased_on: :desc, id: :desc) }
  scope :pending,      -> { where(acknowledged_at: nil) }
  scope :unnotified,   -> { where(notified_at: nil) }
  scope :between,      ->(from, to) { where(purchased_on: from..to) }

  def acknowledged? = acknowledged_at.present?

  def acknowledge! = update!(acknowledged_at: Time.current)

  def unit_label = unit_name.presence || "unidad"
end
