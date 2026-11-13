# frozen_string_literal: true

# Aviso de que un insumo se compró bastante más caro de lo habitual.
# Lo crea PriceAlertDetector después de cada sincronización de compras.
#
# Hay alertas que no son una subida de precio sino una cantidad mal cargada (suspect?):
# el monto de la compra coincide al peso con otra al precio habitual, así que la plata
# que salió del local es la misma. En esas, el "costó de más" no es plata perdida y no
# debe sumarse ni presentarse como tal.
class PriceAlert < ApplicationRecord
  scope :recent,       -> { order(purchased_on: :desc, id: :desc) }
  scope :pending,      -> { where(acknowledged_at: nil) }
  scope :unnotified,   -> { where(notified_at: nil) }
  scope :between,      ->(from, to) { where(purchased_on: from..to) }
  scope :suspect,      -> { where(suspect_quantity: true) }
  scope :real_rise,    -> { where(suspect_quantity: false) }

  # Titular común al panel, al asunto del correo y al cuerpo: cuántas son subidas de precio
  # de verdad y cuántas son cargas por revisar. Meter las dos cosas bajo "subieron de precio"
  # es exactamente lo que hacía que el correo anunciara una subida que no había ocurrido.
  def self.headline(alerts)
    subidas = alerts.count { |a| !a.suspect? }
    cargas  = alerts.count(&:suspect?)
    partes  = []
    partes << (subidas == 1 ? "un insumo subió de precio" : "#{subidas} insumos subieron de precio") if subidas.positive?
    partes << (cargas == 1 ? "una carga para revisar" : "#{cargas} cargas para revisar") if cargas.positive?
    partes.join(" y ").upcase_first
  end

  def acknowledged? = acknowledged_at.present?

  def acknowledge! = update!(acknowledged_at: Time.current)

  def unit_label = unit_name.presence || "unidad"

  # La cantidad cargada no cuadra con la plata: lo que hay que revisar es la carga.
  def suspect? = suspect_quantity?

  # Sobrecosto real: cero cuando la alerta es una carga mal hecha.
  def real_overcost = suspect? ? 0.0 : overcost.to_f
end
