# frozen_string_literal: true

# Trae de Fudo el catálogo de productos y anota los cambios de precio de carta.
#
# La API no guarda historial de precios ni trae `updatedAt`, así que el historial lo
# construimos nosotros: cada corrida compara el precio de hoy con el que teníamos
# guardado y, solo si cambió, escribe una fila en product_price_changes.
#
# Consecuencia que conviene tener clara: este historial empieza el día que esto corre
# por primera vez. Hacia atrás no hay nada que recuperar, y por eso el otro seguimiento
# —el del precio realmente cobrado, en SaleItemsSync— es el que da el pasado.
class ProductsSync
  def self.run!(client: Fudo::Client.new, logger: Rails.logger) = new(client:, logger:).run!

  def initialize(client: Fudo::Client.new, logger: Rails.logger)
    @client = client
    @logger = logger
  end

  Resultado = Struct.new(:total, :nuevos, :cambios, keyword_init: true) do
    def message
      "#{total} productos · #{nuevos} nuevos · #{cambios} cambio(s) de precio"
    end
  end

  def run!(hoy: AppSettings.today)
    catalogo = @client.products
    previos  = Product.pluck(:fudo_product_id, :price).to_h
    nuevos   = 0
    cambios  = 0

    catalogo.each do |p|
      antes = previos[p[:id]]
      nuevos += 1 unless previos.key?(p[:id])

      base, canal = Product.partir_nombre(p[:name])
      producto = Product.find_or_initialize_by(fudo_product_id: p[:id])
      producto.assign_attributes(
        name: p[:name], base_name: base, channel: canal,
        code: p[:code], fudo_category_id: p[:category_id],
        category_name: p[:category_name], price: p[:price],
        cost: p[:cost], components_cost: p[:components_cost],
        active: p[:active], synced_at: Time.current
      )
      producto.save!

      cambios += 1 if anotar_cambio(p, antes, previos.key?(p[:id]), hoy)
    end

    r = Resultado.new(total: catalogo.size, nuevos: nuevos, cambios: cambios)
    @logger.info "ProductsSync: #{r.message}"
    r
  end

  private

  # Escribe una fila solo cuando el precio es distinto del que ya teníamos. La primera
  # foto de un producto se guarda con was_price nil: es el punto de partida, no una subida.
  def anotar_cambio(p, antes, ya_estaba, hoy)
    nuevo = p[:price]
    return false if nuevo.nil?
    return false if ya_estaba && antes && antes.to_f == nuevo.to_f

    ProductPriceChange.find_or_initialize_by(fudo_product_id: p[:id], changed_on: hoy)
                      .update!(price: nuevo, was_price: ya_estaba ? antes : nil)
    true
  end
end
