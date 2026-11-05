class CreateIngredientPurchases < ActiveRecord::Migration[8.1]
  def change
    create_table :ingredient_purchases do |t|
      # Identidad en Fudo: cada fila es una linea de un egreso (ExpenseItem).
      t.integer :fudo_item_id,       null: false
      t.integer :fudo_expense_id,    null: false
      t.integer :fudo_ingredient_id, null: false

      # Se guarda el nombre y la unidad del momento de la compra: en Fudo pueden
      # renombrarse, y asi el historico no cambia de forma retroactiva.
      t.string  :ingredient_name, null: false
      t.string  :unit_name
      t.string  :detail
      t.string  :provider_name

      t.date    :purchased_on, null: false
      t.decimal :quantity,   precision: 14, scale: 4, null: false
      t.decimal :line_total, precision: 14, scale: 2, null: false # neto, sin IVA
      t.decimal :unit_price, precision: 14, scale: 4, null: false # line_total / quantity

      t.datetime :synced_at
      t.timestamps
    end

    # Clave natural: una linea de egreso se guarda una sola vez (permite upsert).
    add_index :ingredient_purchases, :fudo_item_id, unique: true
    # Consulta principal: historico de un insumo ordenado por fecha.
    add_index :ingredient_purchases, [:fudo_ingredient_id, :purchased_on]
    add_index :ingredient_purchases, :purchased_on
  end
end
