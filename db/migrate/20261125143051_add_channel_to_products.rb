# frozen_string_literal: true

# El mismo plato está en Fudo como varios productos, uno por canal: "Margherita 32 cm
# PLATO", "... DELIVERY", "... APLICACION". Se guarda el nombre sin el sufijo y el canal
# aparte para poder verlos juntos, con un precio al lado del otro.
#
# Se calcula al sincronizar y no al consultar: así la regla vive en un sitio, se puede
# mirar en la base cuando algo no cuadra, y no hay que repetir el parseo en cada consulta.
class AddChannelToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :base_name, :string
    add_column :products, :channel,   :string
    add_index  :products, :base_name
  end
end
