# frozen_string_literal: true

# Descarga las líneas de venta: qué producto se vendió, cuántas unidades y a cuánto.
#
# De aquí sale el historial de precios de venta hacia atrás, que el catálogo de Fudo no
# puede dar porque solo guarda el precio de hoy.
#
# Las líneas vienen colgando de las ventas, no de /items, porque /items no acepta filtro
# por fecha. Reutiliza el reloj de SalesSync para que una línea caiga en el mismo día de
# negocio que su venta: si no, las ventas de después de medianoche quedarían en otro día
# que el ticket al que pertenecen.
class SaleItemsSync
  DEFAULT_YEARS = 2 # con dos años sobra para comparar, y evita medio millón de filas

  def self.catch_up!(**) = new(**).catch_up!

  def initialize(client: Fudo::Client.new, logger: Rails.logger)
    @client = client
    @logger = logger
    @reloj  = SalesSync.new
  end

  # Desde la última línea guardada (menos un margen, por ventas que se cierran tarde)
  # hasta hoy. La primera vez baja DEFAULT_YEARS años.
  def catch_up!(hasta: AppSettings.today)
    desde = SaleItem.last_sold_on&.-(AppSettings.refresh_days) || (hasta - (DEFAULT_YEARS * 365))
    run!(desde, hasta)
  end

  Resultado = Struct.new(:desde, :hasta, :lineas, :nuevas, :productos, keyword_init: true) do
    def message
      "#{lineas} líneas (#{nuevas} nuevas) de #{productos} productos, del #{desde} al #{hasta}"
    end
  end

  def run!(desde, hasta)
    crudas = @client.sale_items(@reloj.day_start_utc(desde), @reloj.day_start_utc(hasta + 1))
    antes  = SaleItem.count

    crudas.each_slice(500) do |lote|
      filas = lote.filter_map { |i| fila(i) }
      SaleItem.upsert_all(filas, unique_by: :fudo_item_id) if filas.any?
    end

    r = Resultado.new(desde: desde, hasta: hasta, lineas: crudas.size,
                      nuevas: SaleItem.count - antes, productos: crudas.map { |i| i[:product_id] }.uniq.size)
    @logger.info "SaleItemsSync: #{r.message}"
    r
  end

  private

  def fila(i)
    cantidad = i[:quantity].to_f
    return nil unless cantidad.positive?

    ahora = Time.current
    {
      fudo_item_id: i[:item_id], fudo_sale_id: i[:sale_id], fudo_product_id: i[:product_id],
      product_name: i[:product_name], closed_at: i[:closed_at],
      sold_on: @reloj.business_date(i[:closed_at]),
      quantity: cantidad, line_total: i[:line_total],
      unit_price: i[:line_total] / cantidad,
      created_at: ahora, updated_at: ahora
    }
  end
end
