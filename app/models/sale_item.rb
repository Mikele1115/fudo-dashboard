# frozen_string_literal: true

# Una línea de venta: qué producto, cuántas unidades y cuánto se cobró.
#
# `line_total` es el total de la línea y `unit_price` el resultado de dividirlo por la
# cantidad, igual que en las compras de insumos. El unitario de un mismo producto varía
# dentro del mismo día por los agregados, así que el análisis usa medianas (ver
# ProductPrices) y no compras sueltas.
class SaleItem < ApplicationRecord
  scope :chronological, -> { order(:sold_on, :id) }
  scope :between,       ->(from, to) { where(sold_on: from..to) }
  scope :cobradas,      -> { where("unit_price > 0") } # fuera promociones y combos a 0

  def self.last_sold_on  = maximum(:sold_on)
  def self.first_sold_on = minimum(:sold_on)
end
