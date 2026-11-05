class CreatePriceAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :price_alerts do |t|
      # La compra que disparo la alerta (clave natural: una alerta por linea de compra).
      t.integer :fudo_item_id,       null: false
      t.integer :fudo_ingredient_id, null: false
      t.string  :ingredient_name, null: false
      t.string  :unit_name
      t.string  :provider_name

      t.date    :purchased_on, null: false
      t.decimal :baseline_price, precision: 14, scale: 4, null: false # mediana reciente antes de la compra
      t.decimal :new_price,      precision: 14, scale: 4, null: false
      t.decimal :change_pct,     precision: 8,  scale: 2, null: false
      t.decimal :overcost,       precision: 14, scale: 2, null: false # (new - baseline) * cantidad
      t.decimal :quantity,       precision: 14, scale: 4, null: false

      t.datetime :notified_at     # cuando se envio por correo
      t.datetime :acknowledged_at # cuando el usuario la marco como vista
      t.timestamps
    end

    add_index :price_alerts, :fudo_item_id, unique: true
    add_index :price_alerts, [:fudo_ingredient_id, :purchased_on]
    add_index :price_alerts, :purchased_on
  end
end
