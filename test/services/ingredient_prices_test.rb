# frozen_string_literal: true

require "test_helper"

class IngredientPricesTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 11, 4)

  # Crea una compra. El precio unitario se calcula como en PurchasesSync.
  def buy(name:, on:, qty:, unit_total:, id: nil, ingredient_id: 1, unit: "kg", provider: "Proveedor")
    @seq = (@seq || 0) + 1
    IngredientPurchase.create!(
      fudo_item_id: id || @seq, fudo_expense_id: 100 + @seq, fudo_ingredient_id: ingredient_id,
      ingredient_name: name, unit_name: unit, provider_name: provider,
      purchased_on: on, quantity: qty, line_total: unit_total,
      unit_price: unit_total / qty
    )
  end

  test "la variación compara medianas de la primera y la última ventana, no compras sueltas" do
    # Tres compras a 1.000 hace un año; tres a 1.200 ahora: +20%.
    3.times { |i| buy(name: "Harina", on: TODAY - 360 + i, qty: 1, unit_total: 1000) }
    3.times { |i| buy(name: "Harina", on: TODAY - 10 + i, qty: 1, unit_total: 1200) }

    row = IngredientPrices.new(period: "12", to: TODAY).rows.first
    assert_equal 1000, row.baseline_price
    assert_equal 1200, row.recent_price
    assert_in_delta 20.0, row.change_pct, 0.01
    assert_equal "alza", row.trend
  end

  test "una compra con la cantidad mal cargada no contamina el análisis" do
    # El caso real: mozzarella a $6.700/kg y una línea con los gramos cargados
    # como kilos, que da $6,7/kg. Sin filtro, la variación se dispara.
    5.times { |i| buy(name: "Mozzarella", on: TODAY - 300 + (i * 10), qty: 2, unit_total: 13_400) }
    buy(name: "Mozzarella", on: TODAY - 200, qty: 2000, unit_total: 13_400) # 1.000 veces menos por kg
    3.times { |i| buy(name: "Mozzarella", on: TODAY - 20 + i, qty: 2, unit_total: 14_000) }

    a   = IngredientPrices.new(period: "12", to: TODAY)
    row = a.rows.first

    assert_equal 1, row.suspicious_count, "la línea mal cargada debe quedar marcada"
    assert_equal 8, row.purchases_count,  "y fuera de las compras limpias"
    assert_equal 6700, row.baseline_price
    assert_equal 7000, row.recent_price
    assert_in_delta 4.48, row.change_pct, 0.01
    assert_equal 1, a.to_review.size
  end

  test "un insumo con compras solo en una ventana corta no inventa una variación" do
    2.times { |i| buy(name: "Trufa", on: TODAY - 5 + i, qty: 1, unit_total: 50_000) }

    row = IngredientPrices.new(period: "12", to: TODAY).rows.first
    assert_nil row.baseline_price
    assert_nil row.change_pct
    assert_equal "nuevo", row.trend
  end

  test "la canasta pondera por gasto, no por número de insumos" do
    # Insumo caro (gasta 1.000.000) que sube 10%; insumo barato (gasta 1.000) que sube 100%.
    # El promedio simple daría +55%; ponderado por gasto debe quedar cerca de +10%.
    5.times { |i| buy(name: "Carne", ingredient_id: 1, on: TODAY - 360 + i, qty: 10, unit_total: 100_000) }
    5.times { |i| buy(name: "Carne", ingredient_id: 1, on: TODAY - 10 + i, qty: 10, unit_total: 110_000) }
    buy(name: "Perejil", ingredient_id: 2, on: TODAY - 360, qty: 1, unit_total: 100)
    buy(name: "Perejil", ingredient_id: 2, on: TODAY - 10,  qty: 1, unit_total: 200)

    a = IngredientPrices.new(period: "12", to: TODAY)
    assert_equal 2, a.ingredients_count
    assert_in_delta 10.0, a.basket_change_pct, 0.5
  end

  test "el impacto en pesos mide la subida sobre el volumen comprado" do
    # 10 kg a 1.000 al principio, 10 kg a 1.200 despues: se gastaron 2.000 de mas.
    buy(name: "Queso", on: TODAY - 360, qty: 10, unit_total: 10_000)
    buy(name: "Queso", on: TODAY - 10,  qty: 10, unit_total: 12_000)

    row = IngredientPrices.new(period: "12", to: TODAY).rows.first
    assert_equal 22_000, row.spend
    assert_in_delta 2_000, row.spend_impact, 0.01
  end

  test "las variaciones de menos de 2% se consideran precio estable" do
    buy(name: "Sal", on: TODAY - 360, qty: 1, unit_total: 1000)
    buy(name: "Sal", on: TODAY - 10,  qty: 1, unit_total: 1010)

    assert_equal "estable", IngredientPrices.new(period: "12", to: TODAY).rows.first.trend
  end

  test "la mediana funciona con un número par de valores" do
    assert_equal 15, IngredientPrices.median([10, 20])
    assert_equal 20, IngredientPrices.median([10, 20, 30])
    assert_nil IngredientPrices.median([])
  end

  test "los grupos usan el mismo criterio de fiabilidad que el panel principal" do
    # Un insumo fiable que no se movió (3 compras en cada extremo) y uno con una
    # sola compra en cada extremo que aparenta un desplome del 50%.
    3.times { |i| buy(name: "Harina", on: TODAY - 360 + i, qty: 1, unit_total: 1000) }
    3.times { |i| buy(name: "Harina", on: TODAY - 10 + i, qty: 1, unit_total: 1000) }
    buy(name: "Licor", on: TODAY - 360, qty: 1, unit_total: 10_000, ingredient_id: 2)
    buy(name: "Licor", on: TODAY - 10,  qty: 1, unit_total: 5_000,  ingredient_id: 2)

    a     = IngredientPrices.new(period: "12", to: TODAY)
    grupo = a.grouped_by_fudo_category.first

    assert_equal 2, grupo.rows.size
    assert_equal 1, grupo.reliable_count
    assert_equal 1, grupo.unreliable_count

    # Sin el filtro, el licor —1 compra contra 1— arrastraba el grupo a -35,7%
    # y le inventaba $5.000 de ahorro.
    assert_in_delta 0.0, grupo.change_pct, 0.01, "el licor no debe mover la variación del grupo"
    assert_equal 0, grupo.spend_impact, "ni inventar un ahorro"
  end

  test "la suma de los impactos por categoría cuadra con el total del panel" do
    3.times { |i| buy(name: "Harina", on: TODAY - 360 + i, qty: 1, unit_total: 1000) }
    3.times { |i| buy(name: "Harina", on: TODAY - 10 + i, qty: 1, unit_total: 1200) }
    3.times { |i| buy(name: "Menta", on: TODAY - 360 + i, qty: 1, unit_total: 20_000, ingredient_id: 2) }
    3.times { |i| buy(name: "Menta", on: TODAY - 10 + i, qty: 1, unit_total: 18_000, ingredient_id: 2) }

    a = IngredientPrices.new(period: "12", to: TODAY)
    assert_equal a.spend_impact_total, a.grouped_by_fudo_category.sum(&:spend_impact)
  end
end
