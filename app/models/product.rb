# frozen_string_literal: true

# Un producto del catálogo de Fudo, con su precio de carta actual.
#
# El mismo plato aparece varias veces, una por canal: "Margherita 32 cm PLATO",
# "... DELIVERY", "... APLICACION". `base_name` guarda el nombre sin ese sufijo y
# `channel` el canal, para poder agruparlos (ver Product.canal_de).
class Product < ApplicationRecord
  # Los canales que Fudo pone como sufijo del nombre. Medidos sobre el catálogo real:
  # DELIVERY 60, PLATO 60, APLICACION 26, EVENTO 7. Los 152 productos restantes —bebidas,
  # extras— no llevan sufijo y forman cada uno su propio grupo, que es lo correcto.
  CANALES = %w[PLATO DELIVERY APLICACION APLICACIÓN EVENTO RETIRO MOSTRADOR LOCAL].freeze
  SUFIJO  = /\s+(#{CANALES.join('|')})\s*\z/i

  scope :activos,    -> { where(active: true) }
  scope :alfabetico, -> { order(:base_name, :channel) }
  scope :con_precio, -> { where.not(price: nil).where.not(price: 0) }

  # "Margherita 32 cm APLICACION" -> ["Margherita 32 cm", "APLICACION"]
  # "Austral Calafate 500cc"      -> ["Austral Calafate 500cc", nil]
  def self.partir_nombre(nombre)
    canal = nombre.to_s[SUFIJO, 1]
    [nombre.to_s.sub(SUFIJO, "").strip, canal&.upcase&.tr("Á", "A")]
  end

  def changes_history = ProductPriceChange.where(fudo_product_id: fudo_product_id).chronological

  def margin = price && cost&.positive? ? price - cost : nil

  def channel_label = channel.presence || "único"
end
