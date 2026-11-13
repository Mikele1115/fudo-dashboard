# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  # Sábado 12 de septiembre de 2026. Del 1 al 12 de septiembre hay dos sábados y un lunes;
  # en 2025 esas mismas fechas traen un sábado y dos lunes, así que el mes se compara desparejo.
  HOY = Date.new(2026, 9, 12)

  setup do
    ENV["HISTORY_FROM"] = "2025-01-01"
    sign_in_as(User.take)
  end

  teardown { ENV.delete("HISTORY_FROM") }

  test "el panel avisa cuando el mes se compara contra días de la semana distintos" do
    DailySale.create!(date: HOY, total: 1_200_000, tickets: 60, people: 50, people_sales: 1_000_000)
    DailySale.create!(date: HOY - 7, total: 1_000_000, tickets: 50)                  # el otro sábado
    DailySale.create!(date: Date.new(2025, 9, 5), total: 2_000_000, tickets: 100)    # el mes del año anterior

    get root_path(date: HOY.to_s)

    assert_response :success
    assert_match "un lunes menos y un sábado más", response.body
    assert_match "el calendario le suma", response.body
  end

  test "no avisa nada cuando los dos períodos traen los mismos días de la semana" do
    # El 7 de octubre: el mes lleva 7 días y el año 280, los dos múltiplos de 7. Ventanas así
    # tienen la misma cantidad de cada día de la semana aunque empiecen en días distintos.
    septimo = Date.new(2026, 10, 7)
    DailySale.create!(date: septimo, total: 1_200_000, tickets: 60)
    DailySale.create!(date: Date.new(2025, 10, 7), total: 1_000_000, tickets: 50)

    get root_path(date: septimo.to_s)

    assert_response :success
    assert_no_match(/el calendario le/, response.body)
  end
end
