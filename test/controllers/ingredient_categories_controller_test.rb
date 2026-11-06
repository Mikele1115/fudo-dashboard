require "test_helper"

class IngredientCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    IngredientClassifier.seed_categories!
    @quesos = IngredientCategory.find_by(name: "Quesos")
    comprar("Mozzarella", 1, 20, 140_000, Date.new(2026, 1, 10))
    comprar("Mozzarella", 1, 20, 180_000, Date.new(2026, 10, 10)) # subió
    comprar("Barril Coda", 2, 30, 42_000, Date.new(2026, 10, 11)) # otra categoría
    IngredientClassifier.run!
  end

  def comprar(nombre, id, qty, total, fecha)
    @seq = (@seq || 0) + 1
    IngredientPurchase.create!(
      fudo_item_id: @seq, fudo_expense_id: 800 + @seq, fudo_ingredient_id: id,
      ingredient_name: nombre, unit_name: "kg", purchased_on: fecha,
      quantity: qty, line_total: total, unit_price: total / qty
    )
  end

  test "el detalle muestra solo los insumos de esa categoría" do
    get ingredient_category_path(@quesos, period: "all")
    assert_response :success
    assert_select "h1", "Quesos"
    assert_match "Mozzarella", response.body
    assert_no_match(/Barril Coda/, response.body)
  end

  test "el detalle destaca las subidas de precio" do
    get ingredient_category_path(@quesos, period: "all")
    assert_match "Subidas de precio", response.body
    assert_match "+28,6%", response.body # 7.000 -> 9.000 por kg
  end

  test "una categoría sin compras en el período no rompe la página" do
    vacia = IngredientCategory.find_by(name: "Limpieza")
    get ingredient_category_path(vacia)
    assert_response :success
    assert_match "Sin compras en este período", response.body
  end

  test "la pantalla de categorías enlaza a cada detalle" do
    get ingredient_categories_path
    assert_response :success
    assert_select "a[href=?]", ingredient_category_path(@quesos)
  end

  test "el desglose de insumos enlaza a cada categoría" do
    get ingredients_path
    assert_response :success
    assert_select "a[href^=?]", "/insumos/categorias/#{@quesos.id}"
  end

  test "guardar una asignación la marca como manual" do
    otra = IngredientCategory.find_by(name: "Harinas y secos")
    patch ingredient_categories_path, params: { assignments: { "1" => otra.id.to_s } }
    assert_redirected_to ingredient_categories_path(filter: nil)

    a = IngredientAssignment.find_by(fudo_ingredient_id: 1)
    assert_equal otra.id, a.ingredient_category_id
    assert_not a.automatic, "lo que se guarda a mano no debe quedar como automático"
  end

  test "dejar un insumo en blanco borra su asignación" do
    assert IngredientAssignment.exists?(fudo_ingredient_id: 1)
    patch ingredient_categories_path, params: { assignments: { "1" => "" } }
    assert_not IngredientAssignment.exists?(fudo_ingredient_id: 1)
  end

  test "crear una categoría nueva" do
    assert_difference "IngredientCategory.count", 1 do
      post create_ingredient_category_path, params: { name: "Pastas frescas", area: "Cocina" }
    end
    assert_equal "Cocina", IngredientCategory.find_by(name: "Pastas frescas").area
  end

  test "no crea una categoría con nombre repetido" do
    assert_no_difference "IngredientCategory.count" do
      post create_ingredient_category_path, params: { name: "Quesos", area: "Cocina" }
    end
    follow_redirect!
    assert_match "No se pudo crear", response.body
  end

  test "volver a aplicar reglas respeta lo asignado a mano" do
    otra = IngredientCategory.find_by(name: "Harinas y secos")
    patch ingredient_categories_path, params: { assignments: { "1" => otra.id.to_s } }

    post reclassify_ingredient_categories_path
    assert_equal otra.id, IngredientAssignment.find_by(fudo_ingredient_id: 1).ingredient_category_id
  end

  test "una categoría inexistente devuelve 404" do
    # En integración Rails rescata RecordNotFound y responde 404 en vez de propagarla.
    get ingredient_category_path(999_999)
    assert_response :not_found
  end
end
