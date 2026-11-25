# frozen_string_literal: true

require "test_helper"

# Los enlaces a Fudo usan SIEMPRE el id de Fudo, no el nuestro. Si alguien se confunde
# el enlace sigue funcionando pero lleva a otro producto, que es peor que no llevar a
# ninguno: corregirías el precio del plato equivocado.
class FudoLinksTest < ActionView::TestCase
  include FormatHelper

  test "arma la URL con el patrón de la aplicación de Fudo" do
    assert_equal "https://app-v2.fu.do/app/#!/products/558/edit", fudo_edit_url(:product, 558)
    assert_equal "https://app-v2.fu.do/app/#!/ingredients/82/edit", fudo_edit_url(:ingredient, 82)
  end

  test "la raíz se puede cambiar sin tocar código" do
    ENV["FUDO_APP_URL"] = "https://otro.fu.do/app/#!"
    assert_equal "https://otro.fu.do/app/#!/products/7/edit", fudo_edit_url(:product, 7)
  ensure
    ENV.delete("FUDO_APP_URL")
  end

  test "un tipo que no existe falla en vez de armar una URL rota" do
    assert_raises(KeyError) { fudo_edit_url(:proveedor, 1) }
  end

  test "sin id no se pinta nada" do
    assert_equal "", fudo_edit_link(:product, nil)
    assert_equal "", fudo_edit_link(:product, "")
  end

  test "el enlace abre en otra pestaña y no deja la pestaña a merced del destino" do
    html = fudo_edit_link(:ingredient, 82)

    assert_includes html, 'target="_blank"'
    assert_includes html, 'rel="noopener"'
    assert_includes html, "/ingredients/82/edit"
  end
end

class FudoLinksEnPantallaTest < ActionDispatch::IntegrationTest
  include FormatHelper

  setup { sign_in_as(User.take) }

  test "la tabla de insumos enlaza al insumo correcto de Fudo" do
    6.times do |j|
      IngredientPurchase.create!(fudo_item_id: j + 1, fudo_expense_id: j + 1, fudo_ingredient_id: 4321,
                                 ingredient_name: "Mozzarella", unit_name: "kg", provider_name: "P",
                                 purchased_on: Date.new(2026, 11, 4) - (j * 10),
                                 quantity: 10, line_total: 60_000, unit_price: 6_000)
    end

    get ingredients_path(all: 1)

    assert_select "a[href=?]", fudo_edit_url(:ingredient, 4321),
                  { minimum: 1 }, "tiene que llevar el id de Fudo (4321), no el de nuestra tabla"
  end

  test "la tabla de productos enlaza al producto correcto de Fudo" do
    base, canal = Product.partir_nombre("Margherita 32 cm PLATO")
    Product.create!(fudo_product_id: 558, name: "Margherita 32 cm PLATO", base_name: base,
                    channel: canal, price: 11_400, active: true)
    6.times do |j|
      SaleItem.create!(fudo_item_id: j + 1, fudo_sale_id: j + 1, fudo_product_id: 558,
                       product_name: "Margherita 32 cm PLATO", sold_on: Date.new(2026, 11, 4) - j,
                       closed_at: Time.current, quantity: 1, line_total: 11_400, unit_price: 11_400)
    end

    get products_path(all: 1)

    assert_response :success
    assert_select "a[href=?]", fudo_edit_url(:product, 558), { minimum: 1 }
  end
end
