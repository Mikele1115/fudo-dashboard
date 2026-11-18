# frozen_string_literal: true

# Vista mensual del historial: cada día del mes con su comparable del año anterior,
# más el acumulado del mes contra el mismo período del año anterior.
class MonthReport
  attr_reader :year, :month, :from, :to, :rows, :period

  def initialize(year, month)
    @year  = year
    @month = month
    @from  = Date.new(year, month, 1)
    month_end = Date.new(year, month, -1)
    @to    = [month_end, AppSettings.report_day].min
    @complete = month_end <= AppSettings.report_day

    metrics = Metrics.new([@to, @from].max)
    @rows   = @to >= @from ? (@from..@to).map { |d| metrics.day_row(d) } : []
    @period = metrics.period("Mes", @from, @to, @from << 12, [@to, @from].max << 12)
  end

  def complete? = @complete
  def empty?    = @rows.empty?

  def prev_month = @from << 1
  def next_month = @from >> 1
  def future?    = @from > AppSettings.report_day

  # ---------- de dónde sale cada número (los cuadros que se abren) ----------
  #
  # Son descomposiciones del mes que ya está cargado: no van a la base de datos otra vez.
  # Los días cerrados (sin tickets) no cuentan en los promedios, igual que en Metrics.

  Weekday = Struct.new(:name, :days, :total, :tickets, :ly_total, keyword_init: true) do
    def avg_total  = days.positive? ? total / days : nil
    def avg_ticket = tickets.positive? ? total / tickets : nil
  end

  # El mes repartido por día de la semana, con lo que hizo cada uno el año anterior.
  # Es lo que contesta "¿de qué días vive el mes?", que el día a día no deja ver.
  def by_weekday
    @by_weekday ||= abiertos.group_by { |r| r.date.wday }.sort.map do |wday, filas|
      Weekday.new(
        name:     Metrics::WEEKDAYS[wday].capitalize,
        days:     filas.size,
        total:    filas.sum { |r| r.day.total },
        tickets:  filas.sum { |r| r.day.tickets },
        ly_total: filas.sum { |r| r.ly_day&.total.to_f }
      )
    end
  end

  # Los días con más y con menos venta. `by` permite ordenar por otra medida.
  def top_days(n = 5, by: :total)    = abiertos.sort_by { |r| -medida(r, by) }.first(n)
  def bottom_days(n = 5, by: :total) = abiertos.sort_by { |r| medida(r, by) }.first(n)

  # Días del mes sin una sola venta: local cerrado (o datos sin sincronizar).
  def closed_days = @rows.reject { |r| r.day&.open? }

  # Lo que no entra en el ticket por persona: ventas sin comensales registrados
  # (delivery y retiro). Ver Metrics: people_sales solo suma las de salón.
  def sales_without_people = period.current.total - period.current.people_sales

  private

  def abiertos = @abiertos ||= @rows.select { |r| r.day&.open? }

  def medida(row, by)
    case by
    when :avg_ticket then row.day.avg_ticket || 0.0
    when :tickets    then row.day.tickets.to_f
    else                  row.day.total
    end
  end
end
