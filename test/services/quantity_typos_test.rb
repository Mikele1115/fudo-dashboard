# frozen_string_literal: true

require "test_helper"

class QuantityTyposTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 11, 4)

  def buy(name:, qty:, total:, on: TODAY, ingredient_id: 1, unit: "kg")
    @seq = (@seq || 0) + 1
    IngredientPurchase.create!(
      fudo_item_id: @seq, fudo_expense_id: 500 + @seq, fudo_ingredient_id: ingredient_id,
      ingredient_name: name, unit_name: unit, provider_name: "Proveedor",
      purchased_on: on - @seq, quantity: qty, line_total: total, unit_price: total / qty.to_f
    )
  end

  # El caso real de la menta: $4.336 es exactamente lo que cuestan 0,2 kg al
  # precio de siempre, pero la línea dice 0,5 kg.
  test "marca la línea cuyo monto cuadra pero cuya cantidad no" do
    6.times { buy(name: "Menta", qty: 0.3, total: 6504) }
    2.times { buy(name: "Menta", qty: 0.2, total: 4336) }
    mala = buy(name: "Menta", qty: 0.5, total: 4336)

    hallazgos = QuantityTypos.all

    assert_equal 1, hallazgos.size
    f = hallazgos.first
    assert_equal mala.id, f.purchase.id
    assert_in_delta 21_680, f.normal_price, 1
    assert_in_delta 0.2, f.suggested_quantity, 0.001, "la cantidad correcta sale de la compra gemela"
    assert_in_delta 2.5, f.factor, 0.001
    assert_equal :alta, f.confidence
  end

  test "no marca una compra que simplemente salió a otro precio" do
    5.times { buy(name: "Prosciutto", qty: 4, total: 78_244) }
    buy(name: "Prosciutto", qty: 4.11, total: 71_502) # -11%: variación normal de un fiambre

    assert_empty QuantityTypos.all
  end

  test "no marca una línea barata cuyo monto no coincide con ninguna compra normal" do
    5.times { buy(name: "Prosciutto", qty: 4, total: 78_244) }
    buy(name: "Prosciutto", qty: 4, total: 39_122) # mitad de precio, monto inédito

    assert_empty QuantityTypos.all, "sin monto gemelo no se puede afirmar cuál era la cantidad"
  end

  test "no marca nada si el insumo no tiene bastante historial al precio habitual" do
    2.times { buy(name: "Trufa", qty: 1, total: 50_000) }
    buy(name: "Trufa", qty: 4, total: 50_000)

    assert_empty QuantityTypos.all
  end

  test "una proporción sucia entre cantidades se marca para confirmar, no como segura" do
    3.times { buy(name: "Queso Azul", qty: 2, total: 2000) }
    2.times { buy(name: "Queso Azul", qty: 3.4, total: 3400) }
    buy(name: "Queso Azul", qty: 2, total: 3400) # x1,7: podría ser un precio real

    hallazgos = QuantityTypos.all

    assert_equal 1, hallazgos.size
    assert_equal :media, hallazgos.first.confidence
    assert_in_delta 3.4, hallazgos.first.suggested_quantity, 0.001
  end

  test "la cantidad sugerida tiene que ser una que el insumo compre de verdad" do
    # 0,2 kg aparece una sola vez: no sirve de referencia (MIN_REPEAT).
    6.times { buy(name: "Menta", qty: 0.3, total: 6504) }
    buy(name: "Menta", qty: 0.2, total: 4336)
    buy(name: "Menta", qty: 0.5, total: 4336)

    assert_empty QuantityTypos.all
  end
end
