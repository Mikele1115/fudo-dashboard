# frozen_string_literal: true

require "test_helper"

class HistoryControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["HISTORY_FROM"] = "2025-01-01"
    sign_in_as(User.take)
  end

  teardown { ENV.delete("HISTORY_FROM") }

  def mes_con_ventas
    (1..20).each do |d|
      fecha = Date.new(2026, 9, d)
      DailySale.create!(date: fecha, total: 1_200_000 + (d * 1000), tickets: 40,
                        people: 30, people_sales: 900_000, tips: 90_000)
      DailySale.create!(date: fecha - 364, total: 1_000_000, tickets: 38)
    end
  end

  test "los seis cuadros se abren y enseñan de dónde sale su número" do
    mes_con_ventas

    get history_path(month: "2026-09")

    assert_response :success
    etiquetas = css_select("section.kpis details.kpi > summary .kpi__label").map { |e| e.text.strip }
    assert_equal ["Ventas del mes", "Venta neta (sin IVA)", "Tickets", "Ticket promedio",
                  "Ticket por persona", "Venta promedio por día"], etiquetas
    assert_equal 6, css_select("section.kpis details.kpi .kpi__detail").size
  end

  test "el cuadro de ventas reparte el mes por día de la semana" do
    mes_con_ventas

    get history_path(month: "2026-09")

    detalle = css_select("section.kpis details.kpi").first.css(".kpi__detail").text
    assert_match "Sábado", detalle
    assert_match "Martes", detalle
    assert_match "Año anterior", detalle
  end

  test "el cuadro del ticket por persona explica qué venta queda fuera" do
    mes_con_ventas

    get history_path(month: "2026-09")

    detalle = css_select("section.kpis details.kpi")[4].css(".kpi__detail").text.gsub(/\s+/, " ")
    assert_match "Venta con comensales registrados", detalle
    assert_match "delivery y retiro", detalle
    assert_match "que no es lo que gasta nadie", detalle
  end

  test "un mes sin datos se abre igual, sin romperse" do
    get history_path(month: "2026-09")

    assert_response :success
    assert_equal 6, css_select("section.kpis details.kpi").size
    assert_match "Todavía no hay días con venta", response.body
  end
end
