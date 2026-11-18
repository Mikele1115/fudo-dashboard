require "test_helper"

# Un cambio en el layout afecta a TODAS las pantallas a la vez, y los tests de cada
# controlador miran su contenido, no su marco. Esto comprueba el marco: que cada pantalla
# responde, que trae la barra lateral y que no quedó nada de la cabecera vieja.
class LayoutTest < ActionDispatch::IntegrationTest
  test "todas las pantallas responden con el layout nuevo" do
    IngredientPurchase.create!(fudo_item_id: 1, fudo_expense_id: 1, fudo_ingredient_id: 1,
      ingredient_name: "Mozzarella", unit_name: "kg", provider_name: "P",
      purchased_on: Date.new(2026, 11, 4), quantity: 10, line_total: 60_000, unit_price: 6_000)
    DailySale.create!(date: Date.new(2026, 11, 4), total: 1_000_000, tickets: 50, people: 40, people_sales: 800_000)

    # Sin sesión: la pantalla de entrada no lleva barra lateral.
    get root_path
    assert_redirected_to new_session_path
    get new_session_path
    assert_response :success
    assert_select ".sidebar", 0, "sin sesión no debe haber barra lateral"
    assert_select ".login__card"

    sign_in_as(User.take)
    rutas = {
      "dashboard"  => root_path,
      "historial"  => history_path,
      "insumos"    => ingredients_path,
      "insumo"     => ingredient_path(1),
      "revisar"    => review_ingredients_path,
      "categorías" => ingredient_categories_path,
      "fudo cat."  => fudo_category_path("Sin categoría")
    }
    rutas.each do |nombre, ruta|
      get ruta
      assert_response :success, "#{nombre} (#{ruta}) devolvió #{response.status}"
      assert_select ".shell .sidebar .nav__link", { minimum: 3 }, "#{nombre}: falta la barra lateral"
      assert_select ".main", { minimum: 1 }, "#{nombre}: falta el contenido"
      assert_select ".topbar", 0, "#{nombre}: quedó la cabecera vieja"
    end
  end
end
