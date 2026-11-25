# frozen_string_literal: true

require "test_helper"

class ProductsSyncTest < ActiveSupport::TestCase
  HOY = Date.new(2026, 11, 25)

  # Cliente de mentira: devuelve el catálogo que le pongas.
  class ClienteFalso
    attr_accessor :catalogo

    def initialize(catalogo) = @catalogo = catalogo
    def products = @catalogo
  end

  def producto(id:, name:, price:, cost: nil, active: true)
    { id:, name:, price:, cost:, active:, code: nil, category_id: 1, category_name: "Pizzas" }
  end

  def sincronizar(catalogo, hoy: HOY)
    ProductsSync.new(client: ClienteFalso.new(catalogo)).run!(hoy: hoy)
  end

  test "guarda el catálogo partiendo el canal del nombre" do
    sincronizar([producto(id: 1, name: "Margherita 32 cm PLATO", price: 11_400),
                 producto(id: 2, name: "Margherita 32 cm APLICACION", price: 11_600),
                 producto(id: 3, name: "Coca cola Original", price: 2_900)])

    assert_equal 3, Product.count
    plato = Product.find_by(fudo_product_id: 1)
    assert_equal "Margherita 32 cm", plato.base_name
    assert_equal "PLATO", plato.channel

    app = Product.find_by(fudo_product_id: 2)
    assert_equal "Margherita 32 cm", app.base_name, "las dos tienen que agrupar igual"
    assert_equal "APLICACION", app.channel

    bebida = Product.find_by(fudo_product_id: 3)
    assert_equal "Coca cola Original", bebida.base_name
    assert_nil bebida.channel, "un producto sin sufijo no tiene canal"
  end

  test "la primera foto deja el precio de partida, no una subida" do
    sincronizar([producto(id: 1, name: "Margherita PLATO", price: 11_400)])

    cambio = ProductPriceChange.sole
    assert_equal 11_400, cambio.price
    assert_nil cambio.was_price
    assert cambio.first_seen?
    assert_nil cambio.change_pct, "sin precio anterior no hay variación que calcular"
  end

  test "solo escribe cuando el precio cambia de verdad" do
    catalogo = [producto(id: 1, name: "Margherita PLATO", price: 11_400)]
    sincronizar(catalogo, hoy: HOY)
    sincronizar(catalogo, hoy: HOY + 1)
    sincronizar(catalogo, hoy: HOY + 2)

    assert_equal 1, ProductPriceChange.count,
                 "tres días con el mismo precio son una sola fila, no tres"
  end

  test "anota la subida con el precio que había antes" do
    sincronizar([producto(id: 1, name: "Margherita PLATO", price: 11_400)], hoy: HOY)
    r = sincronizar([producto(id: 1, name: "Margherita PLATO", price: 12_900)], hoy: HOY + 1)

    assert_equal 1, r.cambios
    cambio = ProductPriceChange.recent.first
    assert_equal HOY + 1, cambio.changed_on
    assert_equal 12_900, cambio.price
    assert_equal 11_400, cambio.was_price
    assert_in_delta 13.2, cambio.change_pct, 0.1
  end

  test "un producto que desaparece del catálogo no se borra ni inventa cambios" do
    sincronizar([producto(id: 1, name: "Margherita PLATO", price: 11_400),
                 producto(id: 2, name: "Diavola PLATO", price: 12_000)])
    r = sincronizar([producto(id: 1, name: "Margherita PLATO", price: 11_400)])

    assert_equal 2, Product.count, "la Diavola sigue, con sus ventas históricas"
    assert_equal 0, r.cambios
  end

  test "lee el costo cuando está cargado, y el margen solo si tiene sentido" do
    sincronizar([producto(id: 1, name: "Margherita PLATO", price: 10_000, cost: 3_000),
                 producto(id: 2, name: "Diavola PLATO", price: 10_000, cost: nil)])

    assert_equal 7_000, Product.find_by(fudo_product_id: 1).margin
    assert_nil Product.find_by(fudo_product_id: 2).margin, "sin costo no hay margen"
  end
end
