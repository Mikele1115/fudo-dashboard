# frozen_string_literal: true

require "test_helper"

class IngredientClassifierTest < ActiveSupport::TestCase
  def buy(name:, ingredient_id: nil, on: Date.new(2026, 10, 1), qty: 1, unit_total: 1_000)
    @seq = (@seq || 0) + 1
    IngredientPurchase.create!(
      fudo_item_id: @seq, fudo_expense_id: 900 + @seq, fudo_ingredient_id: ingredient_id || @seq,
      ingredient_name: name, unit_name: "kg", purchased_on: on,
      quantity: qty, line_total: unit_total, unit_price: unit_total / qty
    )
  end

  test "crea el catálogo de categorías con sus áreas" do
    IngredientClassifier.seed_categories!
    assert_equal "Cocina", IngredientCategory.find_by(name: "Quesos").area
    assert_equal "Bar",    IngredientCategory.find_by(name: "Cerveza y barriles").area
    assert_equal "Envases", IngredientCategory.find_by(name: "Envases y desechables").area
  end

  test "no duplica categorías al correrlo dos veces" do
    IngredientClassifier.seed_categories!
    antes = IngredientCategory.count
    IngredientClassifier.seed_categories!
    assert_equal antes, IngredientCategory.count
  end

  test "asigna por palabras clave del nombre" do
    buy(name: "Mozzarella", ingredient_id: 1)
    buy(name: "Barril Austral Calafate", ingredient_id: 2)
    buy(name: "Caja 33 cm", ingredient_id: 3)

    IngredientClassifier.run!
    categorias = IngredientAssignment.category_by_ingredient
    assert_equal "Quesos", categorias[1].name
    assert_equal "Bar",    categorias[2].area
    assert_equal "Envases", categorias[3].area
  end

  test "deja sin asignar lo que ninguna regla reconoce" do
    buy(name: "Voila", ingredient_id: 7)

    _, sin = IngredientClassifier.run!
    assert_includes sin, "Voila"
    assert_nil IngredientAssignment.find_by(fudo_ingredient_id: 7)
  end

  test "nunca pisa una asignación hecha a mano" do
    # El usuario decide que el Pecorino va a una categoría propia; la regla
    # automática lo mandaría a Quesos. Al reclasificar, su decisión manda.
    buy(name: "Pecorino romano", ingredient_id: 5)
    IngredientClassifier.run!
    assert_equal "Quesos", IngredientAssignment.find_by(fudo_ingredient_id: 5).ingredient_category.name

    propia = IngredientCategory.create!(name: "Quesos de autor", area: "Cocina")
    IngredientAssignment.find_by(fudo_ingredient_id: 5)
                        .update!(ingredient_category: propia, automatic: false)

    IngredientClassifier.run!
    a = IngredientAssignment.find_by(fudo_ingredient_id: 5)
    assert_equal "Quesos de autor", a.ingredient_category.name
    assert_not a.automatic
  end

  test "sí corrige una asignación automática anterior" do
    buy(name: "Mozzarella", ingredient_id: 6)
    IngredientClassifier.run!
    quesos = IngredientCategory.find_by(name: "Quesos")
    otra   = IngredientCategory.find_by(name: "Harinas y secos")
    IngredientAssignment.find_by(fudo_ingredient_id: 6).update!(ingredient_category: otra, automatic: true)

    IngredientClassifier.run!
    assert_equal quesos.id, IngredientAssignment.find_by(fudo_ingredient_id: 6).ingredient_category_id
  end

  test "las reglas más específicas ganan a las genéricas" do
    # "Salsa de tomate" debe ir a conservas, no a verduras por contener "tomate".
    buy(name: "Salsa de tomate (La Fiammante)", ingredient_id: 10)
    buy(name: "Tomate Cherry", ingredient_id: 11)

    IngredientClassifier.run!
    categorias = IngredientAssignment.category_by_ingredient
    assert_equal "Aceites y conservas", categorias[10].name
    assert_equal "Verduras y frutas",   categorias[11].name
  end
end

class IngredientPricesCategoriesTest < ActiveSupport::TestCase
  def buy(name:, ingredient_id:, unit_total:, on: Date.new(2026, 10, 1), qty: 1)
    @seq = (@seq || 0) + 1
    IngredientPurchase.create!(
      fudo_item_id: @seq, fudo_expense_id: 950 + @seq, fudo_ingredient_id: ingredient_id,
      ingredient_name: name, unit_name: "kg", purchased_on: on,
      quantity: qty, line_total: unit_total, unit_price: unit_total / qty
    )
  end

  test "agrupa el gasto por la categoría de Fudo y, dentro, por tipo de insumo" do
    buy(name: "Mozzarella", ingredient_id: 1, unit_total: 80_000)
    buy(name: "Barril Coda", ingredient_id: 2, unit_total: 20_000)
    Ingredient.create!(fudo_id: 1, name: "Mozzarella", fudo_category_name: "Ingredientes Pizza")
    Ingredient.create!(fudo_id: 2, name: "Barril Coda", fudo_category_name: "Barriles")
    IngredientClassifier.run!

    a = IngredientPrices.new(period: "12", to: Date.new(2026, 10, 15))
    cats = a.grouped_by_fudo_category.to_h { |g| [g.name, g] }
    assert_in_delta 80.0, cats["Ingredientes Pizza"].share, 0.1
    assert_in_delta 20.0, cats["Barriles"].share, 0.1
    assert_equal ["Quesos"], a.subcategories_of("Ingredientes Pizza").map(&:name)
  end

  test "un mismo tipo puede aparecer en varias categorías de Fudo" do
    # El caso real: hay queso en Pizza, en Postre y en Colación. Por eso la
    # jerarquía no es fija: se agrupa por insumo, no por un árbol predefinido.
    buy(name: "Mozzarella", ingredient_id: 1, unit_total: 60_000)
    buy(name: "Queso mascarpone", ingredient_id: 2, unit_total: 40_000)
    Ingredient.create!(fudo_id: 1, name: "Mozzarella", fudo_category_name: "Ingredientes Pizza")
    Ingredient.create!(fudo_id: 2, name: "Queso mascarpone", fudo_category_name: "Ingredientes Postre")
    IngredientClassifier.run!

    a = IngredientPrices.new(period: "12", to: Date.new(2026, 10, 15))
    assert_equal ["Quesos"], a.subcategories_of("Ingredientes Pizza").map(&:name)
    assert_equal ["Quesos"], a.subcategories_of("Ingredientes Postre").map(&:name)
  end

  test "un insumo sin tipo asignado no se pierde del total" do
    buy(name: "Mozzarella", ingredient_id: 1, unit_total: 90_000)
    buy(name: "Voila", ingredient_id: 2, unit_total: 10_000)
    Ingredient.create!(fudo_id: 1, name: "Mozzarella", fudo_category_name: "Ingredientes Pizza")
    Ingredient.create!(fudo_id: 2, name: "Voila", fudo_category_name: "Ingredientes Barra")
    IngredientClassifier.run!

    a = IngredientPrices.new(period: "12", to: Date.new(2026, 10, 15))
    assert_equal 1, a.uncategorized.size, "Voila no coincide con ninguna regla"
    assert_equal "Voila", a.uncategorized.first.name
    # Aun sin tipo, sigue contando en su categoría de Fudo.
    barra = a.grouped_by_fudo_category.find { |g| g.name == "Ingredientes Barra" }
    assert_equal 10_000, barra.spend
    assert_equal ["Sin subcategoría"], a.subcategories_of("Ingredientes Barra").map(&:name)
  end

  test "un insumo que no está en el catálogo de Fudo queda como Sin categoría" do
    buy(name: "Tomate Cherry", ingredient_id: 7, unit_total: 5_000)
    IngredientClassifier.run!

    a = IngredientPrices.new(period: "12", to: Date.new(2026, 10, 15))
    assert_equal Ingredient::SIN_CATEGORIA, a.grouped_by_fudo_category.first.name
  end
end
