# frozen_string_literal: true

require "test_helper"

class PriceAlertDetectorTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 11, 4)

  # Una compra cara de un insumo que pesa en el gasto: lo normal es que avise.
  # `unit_total` es el total de la línea, como en Fudo.
  def buy(on:, qty:, unit_total:, ingredient_id: 1, name: "Mozzarella", unit: "kg")
    @seq = (@seq || 0) + 1
    IngredientPurchase.create!(
      fudo_item_id: @seq, fudo_expense_id: 500 + @seq, fudo_ingredient_id: ingredient_id,
      ingredient_name: name, unit_name: unit, provider_name: "Lacteos SA",
      purchased_on: on, quantity: qty, line_total: unit_total, unit_price: unit_total / qty
    )
  end

  # Histórico estable: 10 compras de 20 kg a $7.000/kg ($140.000 cada una).
  def historial_estable(hasta: TODAY - 10, precio: 7_000)
    10.times { |i| buy(on: hasta - (i * 20), qty: 20, unit_total: 20 * precio) }
  end

  test "avisa de una subida grande en un insumo que pesa en el gasto" do
    historial_estable
    buy(on: TODAY - 1, qty: 20, unit_total: 20 * 10_000) # +42,9%

    alertas = PriceAlertDetector.run!(since: TODAY - 5)
    assert_equal 1, alertas.size
    a = alertas.first
    assert_equal 7_000, a.baseline_price
    assert_equal 10_000, a.new_price
    assert_in_delta 42.9, a.change_pct, 0.1
    assert_in_delta 60_000, a.overcost, 1 # (10.000 - 7.000) x 20 kg
  end

  test "no avisa si la subida es pequeña aunque el insumo sea grande" do
    historial_estable
    buy(on: TODAY - 1, qty: 20, unit_total: 20 * 7_500) # +7,1%, por debajo del umbral

    assert_empty PriceAlertDetector.run!(since: TODAY - 5)
  end

  test "no avisa si el sobrecosto es irrelevante aunque el salto sea enorme" do
    # Insumo con mucho gasto anual, pero esta compra es de 100 gramos:
    # el precio se dispara y aun asi cuesta de mas una miseria.
    historial_estable
    buy(on: TODAY - 1, qty: 0.1, unit_total: 0.1 * 14_000) # +100% pero solo $700 de mas

    assert_empty PriceAlertDetector.run!(since: TODAY - 5)
  end

  test "no avisa de insumos que casi no se compran" do
    # Mismo salto porcentual, pero el insumo mueve poca plata al año.
    3.times { |i| buy(on: TODAY - 60 - (i * 20), qty: 1, unit_total: 1_000, ingredient_id: 9, name: "Perejil") }
    buy(on: TODAY - 1, qty: 10, unit_total: 10 * 3_000, ingredient_id: 9, name: "Perejil")

    assert_empty PriceAlertDetector.run!(since: TODAY - 5)
  end

  test "no avisa sin histórico suficiente para tener una referencia" do
    2.times { |i| buy(on: TODAY - 30 + i, qty: 20, unit_total: 20 * 7_000) }
    buy(on: TODAY - 1, qty: 20, unit_total: 20 * 15_000)

    assert_empty PriceAlertDetector.run!(since: TODAY - 5)
  end

  test "una línea mal cargada no dispara una alerta" do
    # El clásico: los gramos cargados como kilos. El precio unitario se desploma,
    # no sube, pero tampoco debe contaminar la referencia de las siguientes.
    historial_estable
    buy(on: TODAY - 3, qty: 20_000, unit_total: 140_000) # $7/kg: disparate
    buy(on: TODAY - 1, qty: 20, unit_total: 20 * 10_000)

    alertas = PriceAlertDetector.run!(since: TODAY - 5)
    assert_equal 1, alertas.size, "solo debe avisar de la subida real"
    assert_equal 7_000, alertas.first.baseline_price, "la referencia no se contamina con la línea mala"
  end

  test "no repite el aviso del mismo insumo si el precio se mantiene" do
    historial_estable
    buy(on: TODAY - 5, qty: 20, unit_total: 20 * 10_000)
    buy(on: TODAY - 1, qty: 20, unit_total: 20 * 10_000) # mismo precio alto, pocos días después

    assert_equal 1, PriceAlertDetector.run!(since: TODAY - 10).size
  end

  test "vuelve a avisar si el precio sigue subiendo tras el primer aviso" do
    historial_estable
    buy(on: TODAY - 5, qty: 20, unit_total: 20 * 10_000)
    buy(on: TODAY - 1, qty: 20, unit_total: 20 * 13_000) # +30% sobre el precio ya avisado

    assert_equal 2, PriceAlertDetector.run!(since: TODAY - 10).size
  end

  test "correr dos veces no duplica alertas" do
    historial_estable
    buy(on: TODAY - 1, qty: 20, unit_total: 20 * 10_000)

    PriceAlertDetector.run!(since: TODAY - 5)
    PriceAlertDetector.run!(since: TODAY - 5)
    assert_equal 1, PriceAlert.count
  end
end
