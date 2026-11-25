# frozen_string_literal: true

require "test_helper"

# La regla de cómo se parte un período la comparten los dos análisis, insumos y
# productos. Estas pruebas la fijan en un sitio para que no se separe de ninguno.
class ComparisonWindowTest < ActiveSupport::TestCase
  def ventana(dias) = ComparisonWindow.new(Date.new(2026, 1, 1), Date.new(2026, 1, 1) + dias - 1)

  test "un período largo se parte en dos bloques de un tercio" do
    v = ventana(365)

    assert_equal :split, v.mode
    assert v.split?
    assert_equal 90, v.window_days, "con techo de 90: un tercio de 365 serían 121"
  end

  test "la ventana es un tercio, no un valor fijo" do
    assert_equal 30, ventana(92).window_days
    assert_equal 61, ventana(184).window_days
    assert_equal 90, ventana(730).window_days
  end

  test "un período corto no se parte: se compara con el anterior del mismo largo" do
    v = ventana(31)

    assert_equal :previous, v.mode
    assert_not v.split?
    assert_equal Date.new(2025, 12, 1), v.previous_from
    assert_equal 31, (v.from - v.previous_from).to_i
  end

  test "el corte entre los dos modos está donde las ventanas dejarían de pisarse" do
    # Con menos de 63 días, un tercio cae por debajo del suelo de 21 y los dos bloques
    # se solaparían: la misma venta sería el antes y el después.
    assert_equal :previous, ventana(ComparisonWindow::SPLIT_MIN_DAYS - 1).mode
    assert_equal :split,    ventana(ComparisonWindow::SPLIT_MIN_DAYS).mode
  end

  test "en modo split los dos bloques caben sin pisarse" do
    [63, 92, 184, 365, 730].each do |dias|
      v = ventana(dias)
      assert_operator v.window_days * 2, :<=, v.days,
                      "con #{dias} días los bloques de #{v.window_days} se pisarían"
    end
  end

  test "la nota dice el criterio que de verdad se está usando" do
    assert_match "90 días al principio contra 90 al final", ventana(365).note
    assert_match "contra los 31 días anteriores", ventana(31).note
    assert_no_match(/primeros 90 días/, ventana(365).note,
                    "esa redacción sugería que se cuentan desde el inicio del período")
  end

  test "la mediana ignora el dato suelto que el promedio se llevaría detrás" do
    assert_equal 10, ComparisonWindow.median([10, 10, 10, 10, 1_000])
    assert_equal 15, ComparisonWindow.median([10, 20])
    assert_nil ComparisonWindow.median([])
  end
end
