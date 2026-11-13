# frozen_string_literal: true

require "test_helper"

class MetricsTest < ActiveSupport::TestCase
  # Sábado 12 de septiembre de 2026. Su comparable "weekday" es el sábado 13 de septiembre de 2025.
  REPORT = Date.new(2026, 9, 12)

  setup do
    ENV["VAT_RATE"]     = "0.19"
    ENV["HISTORY_FROM"] = "2024-01-01"
    DailySale.create!(date: REPORT, total: 1190, tickets: 10, people: 4, people_sales: 800, tips: 100)
    DailySale.create!(date: REPORT - 364, total: 800, tickets: 8, people: 2, people_sales: 300) # mismo sábado del año pasado
    DailySale.create!(date: REPORT - 7, total: 600, tickets: 6)                                 # sábado anterior
    DailySale.create!(date: REPORT - 1, total: 400, tickets: 4, people: 2, people_sales: 400)   # viernes
    DailySale.create!(date: REPORT - 2, total: 0, tickets: 0)                                   # jueves cerrado
    DailySale.create!(date: Date.new(2025, 3, 3), total: 200, tickets: 2) # lunes del año pasado, fuera del período
    DailySale.create!(date: Date.new(2024, 6, 1), total: 500, tickets: 5) # hace dos años
  end

  teardown do
    ENV.delete("VAT_RATE")
    ENV.delete("HISTORY_FROM")
  end

  test "día informado y comparable del año anterior" do
    r = Metrics.new(REPORT, compare_mode: "weekday").build
    assert_equal 1190, r.day.total
    assert_equal 119,  r.day.avg_ticket
    assert_equal Date.new(2025, 9, 13), r.ly_date
    assert_equal 800, r.ly_day.total
  end

  test "venta neta, comensales, ticket por persona y propinas" do
    r = Metrics.new(REPORT).build
    assert_in_delta 1000.0, r.day.net, 0.01          # 1190 / 1.19
    assert_equal 4,   r.day.people
    assert_equal 200, r.day.avg_per_person           # 800 / 4
    assert_equal 150, r.ly_day.avg_per_person        # 300 / 2
    assert_equal 100, r.day.tips
    assert_nil Metrics.new(REPORT - 7).build.day.avg_per_person # sin comensales registrados
  end

  test "modo date compara con la misma fecha del año anterior" do
    r = Metrics.new(REPORT, compare_mode: "date").build
    assert_equal Date.new(2025, 9, 12), r.ly_date
    assert_nil r.ly_day
  end

  test "los promedios excluyen los días cerrados" do
    r = Metrics.new(REPORT, compare_mode: "weekday").build
    # Año en curso: 1190 + 600 + 400 en 3 días con venta (el jueves cerrado no cuenta)
    assert_equal 3, r.ytd.days
    assert_in_delta 730.0, r.ytd.avg_total, 0.01
    assert_in_delta 109.5, r.ytd.avg_ticket, 0.01     # 2190 / 20
    assert_in_delta 200.0, r.ytd.avg_per_person, 0.01 # (800 + 400) / (4 + 2)
  end

  test "promedio de los mismos días de la semana sin contar el día informado" do
    r = Metrics.new(REPORT, compare_mode: "weekday").build
    assert_equal 1,   r.weekday_ytd.days # solo el sábado 5/9
    assert_equal 600, r.weekday_ytd.avg_total
    assert_equal 1,   r.weekday_ly.days
    assert_equal 800, r.weekday_ly.avg_total
  end

  test "acumulados de semana, mes y año" do
    r = Metrics.new(REPORT, compare_mode: "weekday").build
    week, month, year = r.periods
    assert_equal Date.new(2026, 9, 7), week.from
    assert_equal 1590, week.current.total   # viernes + sábado (el sábado 5/9 queda fuera de la semana)
    assert_equal 2190, month.current.total
    assert_equal 2190, year.current.total
    assert_equal 200,  year.ly.total        # solo el 3/3; el sábado 13/9/2025 queda fuera (el período termina el 12/9)
    assert_equal 200,  year.current.avg_per_person
  end

  test "comparativa de todos los años desde HISTORY_FROM" do
    r = Metrics.new(REPORT).build
    assert_equal [2026, 2025, 2024], r.years.map(&:year)
    y2026, y2025, y2024 = r.years
    refute y2026.complete
    assert y2025.complete
    assert_equal 2190, y2026.full.total
    assert_equal 2190, y2026.ytd.total
    assert_equal 1000, y2025.full.total                 # 200 + 800 (13/9 sí entra en el año completo)
    assert_equal 200,  y2025.ytd.total                  # hasta el 12/9/2025
    assert_equal Date.new(2025, 9, 12), y2025.ytd_to
    assert_equal 500,  y2024.full.total
    assert_equal 3, r.charts[:years][:datasets].size
    assert_equal "2026", r.charts[:years][:datasets].first[:label]
  end

  test "sin datos devuelve nils en vez de fallar" do
    DailySale.delete_all
    r = Metrics.new(REPORT).build
    assert_nil r.day
    assert_nil r.ytd.avg_total
    assert_equal 0, r.periods.first.current.total
    assert_nil r.periods.first.current.avg_per_person
    assert_equal 30, r.charts[:last_days][:labels].size
  end

  # ---------- desajuste de días de la semana ----------

  test "el mes avisa cuando las dos ventanas no tienen los mismos días de la semana" do
    # Del 1 al 12 de septiembre de 2026 hay dos sábados y un lunes; en 2025, un sábado y dos lunes.
    DailySale.create!(date: Date.new(2025, 9, 5), total: 5000, tickets: 50) # para que el año anterior no sea cero
    gap = Metrics.new(REPORT).build.periods[1].weekday_gap

    assert_equal [["lunes", -1], ["sábado", 1]], gap.days
    assert_equal "un lunes menos y un sábado más", gap.text
    assert_in_delta 895.0, gap.effect, 0.01 # el sábado promedio de 2026: (1190 + 600) / 2
    assert gap.favourable?, "el sábado de más le juega a favor a la ventana de 2026"
    assert gap.material?
  end

  test "la semana no avisa nunca porque se compara con los mismos días de la semana" do
    assert_nil Metrics.new(REPORT).build.periods[0].weekday_gap
  end

  test "un desajuste que no mueve el total no se avisa" do
    chico  = Metrics::WeekdayGap.new(days: [["lunes", 1]], effect: 1000.0, share: 1.9)
    grande = Metrics::WeekdayGap.new(days: [["lunes", 1]], effect: 1000.0, share: -2.1)

    assert_not chico.material?, "en una ventana larga un día de más se diluye"
    assert grande.material?
  end

  test "el texto del desajuste pluraliza y enumera los días" do
    texto = ->(days) { Metrics::WeekdayGap.new(days: days, effect: 0.0, share: 0.0).text }

    assert_equal "un martes más",   texto.([["martes", 1]])
    assert_equal "2 sábados menos", texto.([["sábado", -2]])
    assert_equal "un lunes menos, un martes más y 2 domingos más",
                 texto.([["lunes", -1], ["martes", 1], ["domingo", 2]])
  end
end
