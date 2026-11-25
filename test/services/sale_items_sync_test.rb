# frozen_string_literal: true

require "test_helper"

class SaleItemsSyncTest < ActiveSupport::TestCase
  HOY = Date.new(2026, 11, 4)

  class ClienteFalso
    attr_reader :pedidos

    def initialize(lineas)
      @lineas  = lineas
      @pedidos = []
    end

    def sale_items(desde, hasta)
      @pedidos << [desde, hasta]
      @lineas
    end
  end

  def linea(item_id:, precio:, cantidad:, closed_at:, product_id: 1, nombre: "Margherita")
    { item_id:, sale_id: 900 + item_id, product_id:, product_name: nombre,
      closed_at:, quantity: cantidad, line_total: precio }
  end

  def sincronizar(lineas, desde: HOY - 3, hasta: HOY)
    cliente = ClienteFalso.new(lineas)
    [SaleItemsSync.new(client: cliente).run!(desde, hasta), cliente]
  end

  test "el precio unitario es el total de la línea dividido por la cantidad" do
    # La trampa: `price` en Fudo es el total, no el unitario. Dos Coca Colas a 2.900
    # llegan como una línea de 5.800, y guardarla tal cual diría que valen el doble.
    sincronizar([linea(item_id: 1, precio: 5_800, cantidad: 2, closed_at: HOY.to_time.utc)])

    item = SaleItem.sole
    assert_equal 5_800, item.line_total
    assert_equal 2, item.quantity
    assert_equal 2_900, item.unit_price
  end

  test "una línea cae en el mismo día de negocio que su venta" do
    # Una venta cerrada a las 02:00 pertenece al día anterior si el corte está a esa hora.
    cerrada = Time.utc(2026, 11, 5, 4, 30) # 01:30 en Santiago
    sincronizar([linea(item_id: 1, precio: 11_400, cantidad: 1, closed_at: cerrada)])

    esperado = SalesSync.new.business_date(cerrada)
    assert_equal esperado, SaleItem.sole.sold_on
  end

  test "correr dos veces no duplica ni pierde líneas" do
    lineas = [linea(item_id: 1, precio: 11_400, cantidad: 1, closed_at: HOY.to_time.utc),
              linea(item_id: 2, precio: 5_800,  cantidad: 2, closed_at: HOY.to_time.utc)]
    sincronizar(lineas)
    r, = sincronizar(lineas)

    assert_equal 2, SaleItem.count
    assert_equal 0, r.nuevas
  end

  test "una línea corregida en Fudo se actualiza, no se duplica" do
    sincronizar([linea(item_id: 1, precio: 11_400, cantidad: 1, closed_at: HOY.to_time.utc)])
    sincronizar([linea(item_id: 1, precio: 12_900, cantidad: 1, closed_at: HOY.to_time.utc)])

    assert_equal 1, SaleItem.count
    assert_equal 12_900, SaleItem.sole.unit_price
  end

  test "una línea sin cantidad se descarta en vez de dividir por cero" do
    sincronizar([linea(item_id: 1, precio: 5_000, cantidad: 0, closed_at: HOY.to_time.utc)])

    assert_equal 0, SaleItem.count
  end

  test "la puesta al día arranca desde la última línea guardada, no desde cero" do
    SaleItem.create!(fudo_item_id: 7, fudo_sale_id: 7, fudo_product_id: 1,
                     product_name: "X", sold_on: HOY - 10, closed_at: (HOY - 10).to_time,
                     quantity: 1, line_total: 100, unit_price: 100)
    cliente = ClienteFalso.new([])
    SaleItemsSync.new(client: cliente).catch_up!(hasta: HOY)

    desde, = cliente.pedidos.first
    esperado = SalesSync.new.day_start_utc(HOY - 10 - AppSettings.refresh_days)
    assert_equal esperado, desde, "vuelve unos días atrás por las ventas que se cierran tarde"
  end

  test "la primera vez baja el histórico que se decidió, no todo" do
    cliente = ClienteFalso.new([])
    SaleItemsSync.new(client: cliente).catch_up!(hasta: HOY)

    desde, = cliente.pedidos.first
    esperado = SalesSync.new.day_start_utc(HOY - (SaleItemsSync::DEFAULT_YEARS * 365))
    assert_equal esperado, desde
  end
end
