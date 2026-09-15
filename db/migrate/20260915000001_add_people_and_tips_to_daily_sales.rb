class AddPeopleAndTipsToDailySales < ActiveRecord::Migration[8.1]
  def change
    change_table :daily_sales, bulk: true do |t|
      t.integer :people,       null: false, default: 0 # comensales (solo ventas de salón con personas registradas)
      t.decimal :people_sales, null: false, default: 0, precision: 14, scale: 2 # venta de esas mismas ventas
      t.decimal :tips,         null: false, default: 0, precision: 14, scale: 2 # propinas (no están incluidas en total)
    end
  end
end
