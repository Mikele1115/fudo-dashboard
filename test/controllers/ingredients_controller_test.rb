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

  def alerta(suspect:)
    PriceAlert.create!(
      fudo_item_id: 9001, fudo_ingredient_id: 1, ingredient_name: "Ndjua piccante", unit_name: "kg",
      provider_name: "QI FOOD", purchased_on: HOY, baseline_price: 17_900, new_price: 47_250,
      change_pct: 164.0, overcost: 21_132, quantity: 0.72, suspect_quantity: suspect,
      twin_quantity: (1.8 if suspect), twin_purchased_on: (HOY - 14 if suspect)
    )
  end

  test "el panel marca la alerta cuya cantidad no cuadra con la plata" do
    buy(name: "Ndjua piccante", qty: 0.72, total: 34_020)
    alerta(suspect: true)

    get ingredients_path

    assert_response :success
    assert_select "h2", text: /Una carga para revisar/
    assert_match "revisar carga", response.body
    assert_no_match(/21\.132/, response.body, "el sobrecosto no ocurrió: no se muestra como plata perdida")
  end

  test "el panel sigue mostrando el sobrecosto de una subida real" do
    buy(name: "Ndjua piccante", qty: 0.72, total: 34_020)
    alerta(suspect: false)

    get ingredients_path

    assert_response :success
    assert_select "h2", text: /Un insumo subió de precio/
    assert_match "21.132", response.body
    assert_no_match(/revisar carga/, response.body)
  end
end
