# frozen_string_literal: true

# El costo que Fudo calcula sumando la receta del producto.
#
# Es distinto de `cost`, que es el que alguien teclea a mano en "Costo → Editar". La API
# los da en dos campos separados y hasta ahora solo leíamos el tecleado: por eso la
# Margherita 32 APLICACION salía "sin costo" en el panel mientras Fudo enseñaba $4.914,91.
#
# Cuatro decimales porque la API los da así (4914.914) y redondear aquí sería perder
# precisión antes de tiempo; el formato se decide al pintar.
class AddComponentsCostToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :components_cost, :decimal, precision: 14, scale: 4
  end
end
