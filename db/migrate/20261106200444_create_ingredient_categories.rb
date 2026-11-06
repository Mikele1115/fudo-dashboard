class CreateIngredientCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :ingredient_categories do |t|
      t.string  :name,     null: false
      t.string  :area,     null: false # Cocina, Bar, Envases, Limpieza, Otros
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :ingredient_categories, :name, unique: true
    add_index :ingredient_categories, [:area, :position]
  end
end
