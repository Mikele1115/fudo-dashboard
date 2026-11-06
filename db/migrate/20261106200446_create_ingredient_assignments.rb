class CreateIngredientAssignments < ActiveRecord::Migration[8.1]
  def change
    # A que categoria pertenece cada insumo de Fudo.
    # Se guarda por fudo_ingredient_id y no por nombre: en Fudo los insumos
    # se renombran, y la asignacion no debe perderse por eso.
    create_table :ingredient_assignments do |t|
      t.integer    :fudo_ingredient_id, null: false
      t.references :ingredient_category, null: false, foreign_key: true
      t.string     :ingredient_name # solo para poder leer la tabla a simple vista
      t.boolean    :automatic, null: false, default: false # la puso una regla, no el usuario
      t.timestamps
    end

    add_index :ingredient_assignments, :fudo_ingredient_id, unique: true
  end
end
