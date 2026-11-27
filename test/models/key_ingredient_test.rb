# frozen_string_literal: true

require "test_helper"

class KeyIngredientTest < ActiveSupport::TestCase
  test "sin umbral propio usa el de los insumos clave" do
    assert_equal KeyIngredient::DEFAULT_PCT, KeyIngredient.new.threshold
    assert_equal 8.0, KeyIngredient.new(change_pct: 8).threshold
  end

  test "un insumo se marca una sola vez" do
    KeyIngredient.create!(fudo_ingredient_id: 1, ingredient_name: "Mozzarella")

    assert_not KeyIngredient.new(fudo_ingredient_id: 1, ingredient_name: "Mozzarella").valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      KeyIngredient.new(fudo_ingredient_id: 1, ingredient_name: "Mozzarella").save!(validate: false)
    end
  end

  test "el umbral debe ser positivo, en la validación y en la base" do
    assert_not KeyIngredient.new(fudo_ingredient_id: 1, ingredient_name: "M", change_pct: 0).valid?
    assert_raises(ActiveRecord::StatementInvalid) do
      KeyIngredient.new(fudo_ingredient_id: 1, ingredient_name: "M", change_pct: -1).save!(validate: false)
    end
  end
end
