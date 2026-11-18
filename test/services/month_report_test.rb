# frozen_string_literal: true

require "test_helper"

class MonthReportTest < ActiveSupport::TestCase
  # Septiembre de 2026: empieza en martes y tiene 30 días.
  AÑO = 2026
  MES = 9

  setup { ENV["HISTORY_FROM"] = "2025-01-01" }
  teardown { ENV.delete("HISTORY_FROM") }

  def vende(dia, total:, tickets: 10, people: 0, people_sales: 0, tips: 0, año: AÑO)
    fecha = Date.new(año, MES, dia)
    DailySale.create!(date: fecha, total: total, tickets: tickets,
                      people: people, people_sales: people_sales, tips: tips)
    fecha
  end

  # El comparable de un día es D − 364, que cae en el mismo día de la semana.
  def vendio_el_año_pasado(dia, total:)
    fecha = Date.new(AÑO, MES, dia) - 364
    DailySale.create!(date: fecha, total: total, tickets: 10)
  end

  test "reparte el mes por día de la semana, de mayor a menor" do
    vende(5,  total: 3_000_000) # sábado
    vende(12, total: 2_000_000) # sábado
    vende(8,  total: 1_000_000) # martes

    dias = MonthReport.new(AÑO, MES).by_weekday

    sabado = dias.find { |d| d.name == "Sábado" }
    martes = dias.find { |d| d.name == "Martes" }
    assert_equal 2, sabado.days
    assert_equal 5_000_000, sabado.total
    assert_equal 2_500_000, sabado.avg_total, "el promedio es por día abierto, no por día del mes"
    assert_equal 1, martes.days
    assert_equal 1_000_000, martes.total
  end

  test "compara cada día de la semana con el mismo del año anterior" do
    vende(5, total: 3_000_000)
    vendio_el_año_pasado(5, total: 2_000_000)

    sabado = MonthReport.new(AÑO, MES).by_weekday.find { |d| d.name == "Sábado" }

    assert_equal 2_000_000, sabado.ly_total
  end

  test "los días cerrados no entran en ningún promedio" do
    vende(1, total: 1_000_000)
    vende(2, total: 0, tickets: 0) # abierto en la base, pero sin una sola venta

    r = MonthReport.new(AÑO, MES)

    assert_equal 1, r.by_weekday.sum(&:days), "solo cuenta el día con venta"
    assert_includes r.closed_days.map(&:date), Date.new(AÑO, MES, 2)
    assert_not_includes r.top_days.map(&:date), Date.new(AÑO, MES, 2)
  end

  test "los mejores y peores días se pueden pedir por venta o por ticket promedio" do
    vende(1, total: 1_000_000, tickets: 100) # mucha venta, ticket bajo: $10.000
    vende(2, total: 600_000,   tickets: 10)  # poca venta, ticket alto:  $60.000

    r = MonthReport.new(AÑO, MES)

    assert_equal Date.new(AÑO, MES, 1), r.top_days(1).first.date
    assert_equal Date.new(AÑO, MES, 2), r.top_days(1, by: :avg_ticket).first.date
    assert_equal Date.new(AÑO, MES, 2), r.bottom_days(1).first.date
    assert_equal Date.new(AÑO, MES, 1), r.bottom_days(1, by: :avg_ticket).first.date
  end

  test "la venta sin comensales es la que no entra en el ticket por persona" do
    vende(1, total: 1_000_000, people: 50, people_sales: 800_000)

    r = MonthReport.new(AÑO, MES)

    assert_equal 200_000, r.sales_without_people, "delivery y retiro, que no tienen comensales"
    assert_equal 16_000, r.period.current.avg_per_person, "800.000 / 50, no 1.000.000 / 50"
  end

  test "un mes sin ventas no revienta" do
    r = MonthReport.new(AÑO, MES)

    assert_empty r.by_weekday
    assert_empty r.top_days
    assert_equal 0.0, r.sales_without_people
  end
end
