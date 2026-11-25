# frozen_string_literal: true

# Seguimiento de los precios de VENTA, que son dos cosas distintas:
#
#   products                -> el catálogo y su precio de carta de hoy
#   product_price_changes   -> cuándo cambió ese precio de carta (lo construimos nosotros:
#                              la API no guarda historial ni trae updatedAt)
#   sale_items              -> lo que de verdad se cobró, línea a línea. De aquí sale el
#                              histórico hacia atrás, que el catálogo no puede dar.
class CreateProductsAndSaleItems < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.integer :fudo_product_id, null: false
      t.string  :name,            null: false
      t.string  :code
      t.integer :fudo_category_id
      t.string  :category_name
      t.decimal :price, precision: 14, scale: 2            # precio de carta actual
      t.decimal :cost,  precision: 14, scale: 2            # vacío en Fudo hoy; si se llena, margen
      t.boolean :active, null: false, default: true
      t.datetime :synced_at
      t.timestamps
      t.index :fudo_product_id, unique: true
      t.index :name
    end

    # Una fila por cambio, no una por día: 356 productos activos x 365 días serían 130.000
    # filas al año para decir casi siempre lo mismo. Así son unas pocas al mes.
    create_table :product_price_changes do |t|
      t.integer :fudo_product_id, null: false
      t.date    :changed_on,      null: false
      t.decimal :price,     precision: 14, scale: 2, null: false
      t.decimal :was_price, precision: 14, scale: 2        # nil en la primera foto
      t.timestamps
      t.index %i[fudo_product_id changed_on], unique: true
      t.index :changed_on
    end

    create_table :sale_items do |t|
      t.integer  :fudo_item_id,    null: false
      t.integer  :fudo_sale_id,    null: false
      t.integer  :fudo_product_id, null: false
      t.string   :product_name,    null: false
      t.date     :sold_on,         null: false            # día de negocio, no el UTC crudo
      t.datetime :closed_at,       null: false
      t.decimal  :quantity,   precision: 14, scale: 4, null: false
      t.decimal  :line_total, precision: 14, scale: 2, null: false
      # Unitario = line_total / quantity. Se guarda calculado para no repetir la división
      # en cada consulta, igual que en ingredient_purchases.
      t.decimal  :unit_price, precision: 14, scale: 4, null: false
      t.timestamps
      t.index :fudo_item_id, unique: true
      t.index %i[fudo_product_id sold_on]
      t.index :sold_on
    end
  end
end
