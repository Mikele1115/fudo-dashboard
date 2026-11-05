# frozen_string_literal: true

require "test_helper"

class WeeklyPurchasesReportTest < ActiveSupport::TestCase
  VIERNES = Date.new(2026, 10, 23)

  def buy(on:, qty:, unit_total:, ingredient_id: 1, name: "Mozzarella", unit: "kg")
    @seq = (@seq || 0) + 1
    IngredientPurchase.create!(
      fudo_item_id: @seq, fudo_expense_id: 700 + @seq, fudo_ingredient_id: ingredient_id,
      ingredient_name: name, unit_name: unit, provider_name: "Lacteos SA",
      purchased_on: on, quantity: qty, line_total: unit_total, unit_price: unit_total / qty
    )
  end

  test "la semana va del lunes al día del informe" do
    r = WeeklyPurchasesReport.new(VIERNES)
    assert_equal Date.new(2026, 10, 19), r.from
    assert_equal VIERNES, r.to
    assert_equal 1, r.from.wday, "debe empezar en lunes"
  end

  test "resume gasto, compras e insumos de la semana" do
    buy(on: VIERNES - 2, qty: 10, unit_total: 70_000)
    buy(on: VIERNES,     qty: 5,  unit_total: 35_000)
    buy(on: VIERNES,     qty: 2,  unit_total: 40_000, ingredient_id: 2, name: "Jamón")
    buy(on: VIERNES - 8, qty: 10, unit_total: 60_000) # semana anterior: fuera

    r = WeeklyPurchasesReport.new(VIERNES)
    assert_equal 3, r.count
    assert_equal 2, r.ingredients_count
    assert_equal 145_000, r.spend
    assert_equal 60_000, r.previous.spend
  end

  test "compara el precio con el último pagado antes de la semana" do
    buy(on: VIERNES - 20, qty: 10, unit_total: 10 * 6_000)
    buy(on: VIERNES - 1,  qty: 10, unit_total: 10 * 7_500)

    linea = WeeklyPurchasesReport.new(VIERNES).lines.first
    assert_equal 6_000, linea.prev_price
    assert_equal 7_500, linea.last_price
    assert_in_delta 25.0, linea.change_pct, 0.01
    assert_equal 1, WeeklyPurchasesReport.new(VIERNES).rising.size
  end

  test "una línea con el total en cero no aparece como una bajada del 100%" do
    # Caso real: un barril cargado con total 0. Antes salia como "bajo -100%".
    5.times { |i| buy(on: VIERNES - 40 + (i * 5), qty: 30, unit_total: 30 * 1_400, name: "Barril", unit: "litre") }
    buy(on: VIERNES - 1, qty: 30, unit_total: 0, name: "Barril", unit: "litre")

    r = WeeklyPurchasesReport.new(VIERNES)
    assert_empty r.falling, "la línea mal cargada no es una bajada de precio"
    assert_equal 1, r.suspicious.size, "pero sí debe aparecer para corregirla en Fudo"
  end

  test "lista los insumos comprados por primera vez" do
    buy(on: VIERNES - 30, qty: 1, unit_total: 1_000)
    buy(on: VIERNES - 1,  qty: 1, unit_total: 1_000)
    buy(on: VIERNES - 1,  qty: 2, unit_total: 5_000, ingredient_id: 3, name: "Garbanzos")

    nuevos = WeeklyPurchasesReport.new(VIERNES).first_time
    assert_equal ["Garbanzos"], nuevos.map(&:name)
  end

  test "incluye las alertas de precio de la semana" do
    PriceAlert.create!(fudo_item_id: 1, fudo_ingredient_id: 1, ingredient_name: "Mozzarella",
                       unit_name: "kg", purchased_on: VIERNES - 1, baseline_price: 7_000,
                       new_price: 10_000, change_pct: 42.9, overcost: 60_000, quantity: 20)
    PriceAlert.create!(fudo_item_id: 2, fudo_ingredient_id: 1, ingredient_name: "Mozzarella",
                       unit_name: "kg", purchased_on: VIERNES - 20, baseline_price: 7_000,
                       new_price: 9_000, change_pct: 28.6, overcost: 40_000, quantity: 20)

    assert_equal 1, WeeklyPurchasesReport.new(VIERNES).alerts.size
  end

  test "una semana sin compras no rompe nada" do
    r = WeeklyPurchasesReport.new(VIERNES)
    assert_not r.any?
    assert_equal 0, r.spend
    assert_empty r.lines
    assert_nil r.spend_change_pct
  end
end
