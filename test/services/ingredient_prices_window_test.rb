# frozen_string_literal: true

require "test_helper"

# Tres fallos encontrados mirando el período de 3 meses. Estas pruebas existen
# para que no vuelvan.
class IngredientPricesWindowTest < ActiveSupport::TestCase
  HOY = Date.new(2026, 11, 4)

  def buy(on:, unit_total:, qty: 1, ingredient_id: 1, name: "Mozzarella")
    @seq = (@seq || 0) + 1
    IngredientPurchase.create!(
      fudo_item_id: @seq, fudo_expense_id: 300 + @seq, fudo_ingredient_id: ingredient_id,
      ingredient_name: name, unit_name: "kg", purchased_on: on,
      quantity: qty, line_total: unit_total, unit_price: unit_total / qty
    )
  end

  test "la ventana se adapta al período y nunca se come el período entero" do
    # El fallo original: con una ventana fija de 90 días, el período de 3 meses
    # (91 días) no daba NINGUNA variación porque las dos ventanas se solapaban.
    assert_equal 30, IngredientPrices.new(period: "3",  to: HOY).window_days
    assert_equal 61, IngredientPrices.new(period: "6",  to: HOY).window_days
    assert_equal 90, IngredientPrices.new(period: "12", to: HOY).window_days
    assert_equal 90, IngredientPrices.new(period: "24", to: HOY).window_days
  end

  test "el período de 3 meses sí calcula variaciones" do
    # Compras repartidas por los tres meses, subiendo de precio.
    4.times { |i| buy(on: HOY - 88 + (i * 5), unit_total: 6_000) }
    4.times { |i| buy(on: HOY - 20 + (i * 5), unit_total: 7_500) }

    a = IngredientPrices.new(period: "3", to: HOY)
    row = a.rows.first
    assert_not_nil row.change_pct, "con 3 meses debe poder compararse"
    assert_in_delta 25.0, row.change_pct, 0.01
    assert_equal 1, a.rising.size
  end

  test "el precio normal de un insumo no cambia según el período elegido" do
    # El fallo: el filtro de dudosas usaba la mediana del período. En 12 meses
    # una compra mala se descartaba; en 6 meses se colaba y torcía la canasta.
    12.times { |i| buy(on: HOY - 330 + (i * 25), unit_total: 7_000) }
    buy(on: HOY - 100, unit_total: 100) # gramos cargados como kilos
    3.times { |i| buy(on: HOY - 20 + (i * 5), unit_total: 7_500) }

    %w[3 6 12].each do |periodo|
      a = IngredientPrices.new(period: periodo, to: HOY)
      row = a.rows.first
      next if row.nil?

      assert_equal 0, row.clean.count { |p| p.unit_price.to_f < 1_000 },
                   "la compra mala debe quedar fuera también con período #{periodo}"
    end
  end

  test "una variación con pocos datos no entra en la canasta" do
    # Insumo grande con un solo dato en un extremo: no debe mover el índice.
    buy(on: HOY - 300, unit_total: 1_000, qty: 1000, ingredient_id: 1, name: "Grande")
    buy(on: HOY - 10,  unit_total: 3_000, qty: 1000, ingredient_id: 1, name: "Grande")
    # Insumo pequeño pero bien medido.
    4.times { |i| buy(on: HOY - 330 + (i * 5), unit_total: 1_000, ingredient_id: 2, name: "Pequeno") }
    4.times { |i| buy(on: HOY - 20 + (i * 5), unit_total: 1_020, ingredient_id: 2, name: "Pequeno") }

    a = IngredientPrices.new(period: "12", to: HOY)
    grande = a.rows.find { |r| r.name == "Grande" }
    assert_not grande.reliable?, "con 1 compra por extremo no es fiable"
    assert_equal 1, a.unreliable_count
    # La canasta refleja solo al pequeño (+2%), no el +200% del grande.
    assert_in_delta 2.0, a.basket_change_pct, 0.1
  end

  test "los que más encarecieron la cuenta solo incluye filas fiables" do
    buy(on: HOY - 300, unit_total: 1_000, qty: 1000, ingredient_id: 1, name: "Dudoso")
    buy(on: HOY - 10,  unit_total: 9_000, qty: 1000, ingredient_id: 1, name: "Dudoso")

    a = IngredientPrices.new(period: "12", to: HOY)
    assert_empty a.costliest_rises, "no se recomienda negociar con una sola compra de respaldo"
  end
end
