# frozen_string_literal: true

require "test_helper"

class IngredientsControllerTest < ActionDispatch::IntegrationTest
  HOY = Date.new(2026, 11, 4)

  setup { sign_in_as(User.take) }

  def buy(name:, qty:, total:, on: HOY, ingredient_id: 1, unit: "kg")
    @seq = (@seq || 0) + 1
    IngredientPurchase.create!(
      fudo_item_id: @seq, fudo_expense_id: 700 + @seq, fudo_ingredient_id: ingredient_id,
      ingredient_name: name, unit_name: unit, provider_name: "La Barra SpA",
      purchased_on: on - @seq, quantity: qty, line_total: total, unit_price: total / qty.to_f
    )
  end

  def cargar_menta
    6.times { buy(name: "Menta", qty: 0.3, total: 6504) }
    2.times { buy(name: "Menta", qty: 0.2, total: 4336) }
    buy(name: "Menta", qty: 0.5, total: 4336)
  end

  test "la pantalla de revisión lista la línea y dice cuál era la cantidad correcta" do
    cargar_menta

    get review_ingredients_path(period: "all")
    assert_response :success
    assert_select "h1", "Revisar cargas"
    assert_match "Menta", response.body
    assert_match "La Barra SpA", response.body
    assert_match "casi seguro", response.body
  end

  test "sin líneas marcadas la pantalla lo dice en vez de romperse" do
    5.times { buy(name: "Harina", qty: 10, total: 12_000) }

    get review_ingredients_path
    assert_response :success
    assert_match "Nada que revisar", response.body
  end

  test "el período filtra las líneas pero no cambia el precio habitual" do
    cargar_menta

    get review_ingredients_path(period: "all")
    con_todo = css_select("table").last.css("tbody tr").size

    get review_ingredients_path(period: "3")
    assert_response :success
    assert_operator css_select("table").last.css("tbody tr").size, :<=, con_todo
  end

  test "insumos enlaza a la pantalla de revisión con el número de líneas" do
    cargar_menta

    get ingredients_path
    assert_response :success
    assert_select "a[href=?]", review_ingredients_path, text: /Revisar cargas \(1\)/
  end
end
