# frozen_string_literal: true

# Una alerta de precio puede no ser una subida sino una cantidad mal cargada: si el monto
# de la compra coincide al peso con otra compra al precio habitual, la plata que salió del
# local es la misma y lo que está mal es la cantidad. Se guarda marcado, junto con la compra
# que sirve de prueba, para que el correo y las pantallas lo digan en vez de anunciar una
# subida que no existió. El dato de Fudo no se toca: solo se señala.
class AddSuspectQuantityToPriceAlerts < ActiveRecord::Migration[8.1]
  def change
    add_column :price_alerts, :suspect_quantity,  :boolean, null: false, default: false
    add_column :price_alerts, :twin_quantity,     :decimal, precision: 14, scale: 4
    add_column :price_alerts, :twin_purchased_on, :date
  end
end
