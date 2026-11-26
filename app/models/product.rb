# frozen_string_literal: true

# Un producto del catálogo de Fudo, con su precio de carta actual.
#
# El mismo plato aparece varias veces, una por canal: "Margherita 32 cm PLATO",
# "... DELIVERY", "... APLICACION". `base_name` guarda el nombre sin ese sufijo y
# `channel` el canal, para poder agruparlos (ver Product.canal_de).
class Product < ApplicationRecord
  # Los canales que Fudo pone como sufijo del nombre. Medidos sobre el catálogo real:
  # DELIVERY 60, PLATO 60, APLICACION 26, EVENTO 7. Los 152 productos restantes —bebidas,
  # extras— no llevan sufijo y forman cada uno su propio grupo, que es lo correcto.
  CANALES = %w[PLATO DELIVERY APLICACION APLICACIÓN EVENTO RETIRO MOSTRADOR LOCAL].freeze
  SUFIJO  = /\s+(#{CANALES.join('|')})\s*\z/i

  scope :activos,    -> { where(active: true) }
  scope :alfabetico, -> { order(:base_name, :channel) }
  scope :con_precio, -> { where.not(price: nil).where.not(price: 0) }
  # Con costo por cualquiera de las dos vías: la receta o el tecleado a mano.
  scope :con_costo,  -> { where("cost > 0 OR components_cost > 0") }

  # "Margherita 32 cm APLICACION" -> ["Margherita 32 cm", "APLICACION"]
  # "Austral Calafate 500cc"      -> ["Austral Calafate 500cc", nil]
  def self.partir_nombre(nombre)
    canal = nombre.to_s[SUFIJO, 1]
    [nombre.to_s.sub(SUFIJO, "").strip, canal&.upcase&.tr("Á", "A")]
  end

  def changes_history = ProductPriceChange.where(fudo_product_id: fudo_product_id).chronological

  def margin = price && cost&.positive? ? price - cost : nil

  # Fudo guarda DOS costos y la API los da en campos separados:
  #   cost            -> el que alguien tecleó en "Costo → Editar"
  #   components_cost -> el que Fudo calcula sumando la receta
  #
  # Manda la receta cuando existe: se recalcula sola cuando cambia el precio de un insumo,
  # mientras que el tecleado se queda con el valor del día que se escribió. Son 46 los que
  # tienen los dos y no siempre coinciden —el Austral Calafate dice $2.123 a mano y $1.062
  # por receta, justo el doble—.
  #
  # Leer solo el tecleado era el motivo de que la Margherita 32 APLICACION saliera "sin
  # costo" mientras Fudo enseñaba $4.914,91. Con los dos se pasa del 12% al 90% de la
  # facturación con costo conocido.
  def recipe_cost = components_cost.to_f.positive? ? components_cost.to_f : nil
  def typed_cost  = cost.to_f.positive? ? cost.to_f : nil
  def cost_value  = recipe_cost || typed_cost

  # De dónde salió, para poder decirlo en pantalla: una receta y un número tecleado hace
  # meses no merecen la misma confianza.
  def cost_source
    return :receta   if recipe_cost
    return :tecleado if typed_cost

    nil
  end

  # La carta sin IVA. El costo de Fudo es neto y el precio lleva IVA; para compararlos
  # hay que ponerlos en la misma moneda.
  def price_net
    price.to_f.positive? ? price.to_f / (1 + AppSettings.vat_rate) : nil
  end

  # Un costo por encima del precio de venta no puede ser. Se juzga contra la carta y no
  # contra lo cobrado a propósito: la carta la tienen todos, también los productos
  # parados, que es justo donde nadie mira. Mirando solo lo cobrado se escapaban 8 de
  # los 13 costos rotos del catálogo, entre ellos cuatro agregados cuya receta se come
  # un kilo entero por porción: el Prosciutto crudo cuesta $19.561, que es el kilo.
  def cost_impossible?
    c = cost_value
    n = price_net
    c && n ? c > n : false
  end

  # Cuántas veces el costo es el precio: "19,2×" se lee mejor que "-1.819%".
  def cost_ratio = cost_impossible? ? cost_value / price_net : nil

  def channel_label = channel.presence || "único"
end
