# frozen_string_literal: true

# Insumos clave de la pizzería: avisan con un umbral propio, más sensible que el general.
# Se guardan por fudo_ingredient_id (no dentro de `ingredients`) para que la sincronización
# con Fudo, que pisa esa tabla, nunca los pierda.
class CreateKeyIngredients < ActiveRecord::Migration[8.1]
  def change
    create_table :key_ingredients do |t|
      t.integer :fudo_ingredient_id, null: false
      t.string  :ingredient_name, null: false
      t.decimal :change_pct, precision: 5, scale: 2   # null = el umbral por defecto de los claves
      t.timestamps
    end
    add_index :key_ingredients, :fudo_ingredient_id, unique: true
    add_check_constraint :key_ingredients, "change_pct IS NULL OR change_pct > 0", name: "key_ingredients_pct_positivo"

    add_column :price_alerts, :key_ingredient, :boolean, default: false, null: false
  end
end
