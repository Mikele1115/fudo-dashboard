class CreateIngredients < ActiveRecord::Migration[8.1]
  def change
    # Catalogo de insumos tal como esta en Fudo, con SU categoria.
    # Fudo es la fuente de verdad de la categoria: si el usuario mueve un insumo
    # de "Ingredientes Barra" a "Ingredientes Postre" en el POS, aqui se refleja
    # en la siguiente sincronizacion.
    create_table :ingredients do |t|
      t.integer :fudo_id, null: false
      t.string  :name,    null: false
      t.string  :unit_name
      t.integer :fudo_category_id
      t.string  :fudo_category_name
      t.datetime :synced_at
      t.timestamps
    end

    add_index :ingredients, :fudo_id, unique: true
    add_index :ingredients, :fudo_category_name
  end
end
