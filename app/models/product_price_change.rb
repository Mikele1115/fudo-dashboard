# frozen_string_literal: true

# Cada vez que el precio de carta de un producto cambia respecto a la foto anterior.
#
# No hay una fila por día a propósito: la API no guarda historial, así que lo
# construimos nosotros, y guardar 356 productos x 365 días para decir casi siempre lo
# mismo serían 130.000 filas al año. Solo se escribe cuando el número cambia.
class ProductPriceChange < ApplicationRecord
  scope :chronological, -> { order(:changed_on, :id) }
  scope :recent,        -> { order(changed_on: :desc, id: :desc) }
  scope :between,       ->(from, to) { where(changed_on: from..to) }

  def change_pct
    return nil if was_price.nil? || was_price.to_f.zero?

    (price.to_f - was_price.to_f) / was_price.to_f * 100.0
  end

  def first_seen? = was_price.nil?
end
