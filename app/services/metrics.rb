# frozen_string_literal: true

# Calcula todos los indicadores del dashboard y del informe para un día de negocio,
# a partir de los totales diarios guardados en daily_sales.
#
#   result = Metrics.new(Date.new(2026, 9, 13)).build
#   result.day.total            # venta bruta del día
#   result.day.net              # venta neta (sin IVA)
#   result.day.avg_per_person   # ticket por persona
#   result.years                # comparativa de todos los años
#
# Vocabulario:
#   total        = venta bruta (lo cobrado, IVA incluido, sin propinas)
#   net          = venta neta  (total sin IVA)
#   people       = comensales (solo ventas de salón con personas registradas)
#   people_sales = venta de esas ventas con comensales -> ticket por persona = people_sales / people
class Metrics
  # Totales de un conjunto de días. Es la pieza básica: un Day es un Totals de un solo día.
  Totals = Struct.new(:total, :tickets, :people, :people_sales, :tips, :days, keyword_init: true) do
    def net            = Metrics.net(total)
    def avg_ticket     = tickets.positive? ? total / tickets : nil
    def avg_per_person = people.positive? ? people_sales / people : nil
    def open?          = tickets.positive?
  end

  Day = Struct.new(:date, :total, :tickets, :people, :people_sales, :tips) do
    def net            = Metrics.net(total)
    def avg_ticket     = tickets.positive? ? total / tickets : nil
    def avg_per_person = people.positive? ? people_sales / people : nil
    def open?          = tickets.positive?
  end

  # Promedio diario de un conjunto de días (solo cuenta días con ventas).
  Average = Struct.new(:days, :avg_total, :avg_tickets, :avg_ticket, :avg_per_person, keyword_init: true) do
    def avg_net = Metrics.net(avg_total)
  end

  # Acumulado de un período (semana, mes, año) y su equivalente del año anterior.
  Period = Struct.new(:label, :from, :to, :current, :ly_from, :ly_to, :ly, keyword_init: true)

  # Un año completo de la comparativa, con su "mismo período" (1 ene -> misma fecha del día informado).
  YearRow = Struct.new(:year, :full, :ytd, :ytd_to, :complete, keyword_init: true)

  # Un día de la tabla de "últimos días" con su comparable del año anterior.
  DayRow = Struct.new(:date, :day, :ly_date, :ly_day, keyword_init: true)

  Result = Struct.new(
    :report_date,    # Date del día informado
    :day,            # Day del día informado (nil si no hay datos sincronizados)
    :ly_date,        # Date comparable del año anterior
    :ly_day,         # Day del año anterior (puede ser nil)
    :ytd,            # Average: promedio diario del año en curso (1 ene -> día informado)
    :ly_same_period, # Average: promedio diario del año anterior en el mismo período
    :ly_full,        # Average: promedio diario del año anterior completo
    :weekday_ytd,    # Average: mismos días de la semana del año en curso (sin el día informado)
    :weekday_ly,     # Average: mismos días de la semana del año anterior completo
    :periods,        # [Period] semana, mes y año en curso vs. año anterior
    :years,          # [YearRow] todos los años del histórico, del más reciente al más antiguo
    :recent,         # [DayRow] últimos días, del más reciente al más antiguo
    :charts,         # Hash con los datos de los gráficos
    keyword_init: true
  )

  RECENT_DAYS    = 14
  CHART_DAYS     = 30
  WEEKDAYS_SHORT = %w[Dom Lun Mar Mié Jue Vie Sáb].freeze
  MONTHS_SHORT   = %w[Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic].freeze
  MONTHS         = %w[enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre].freeze

  # Venta neta: quita el IVA incluido en el total.
  def self.net(amount)
    amount && amount / (1 + AppSettings.vat_rate)
  end

  # Primer día que hace falta tener sincronizado para calcular todo.
  def self.required_from(report_date)
    [AppSettings.history_from, Date.new(report_date.year - 1, 1, 1)].min
  end

  # Día comparable del año anterior según COMPARE_MODE.
  #   weekday: D - 364 días (mismo día de la semana). date: misma fecha, un año antes.
  def self.comparable_last_year(date, mode = AppSettings.compare_mode)
    mode == "date" ? (date << 12) : (date - 364)
  end

  def initialize(report_date, compare_mode: AppSettings.compare_mode)
    @report_date = report_date
    @mode        = compare_mode
    @from        = self.class.required_from(report_date)
    # Una sola consulta a la BD; después todo se calcula en memoria.
    @days = DailySale.where(date: @from..report_date).each_with_object({}) do |r, h|
      h[r.date] = Day.new(r.date, r.total.to_f, r.tickets, r.people, r.people_sales.to_f, r.tips.to_f)
    end
  end

  def day(date) = @days[date]
  def ly(date)  = self.class.comparable_last_year(date, @mode)

  def build
    d             = @report_date
    year_start    = Date.new(d.year, 1, 1)
    ly_year_start = Date.new(d.year - 1, 1, 1)
    ly_year_end   = Date.new(d.year - 1, 12, 31)

    Result.new(
      report_date:    d,
      day:            day(d),
      ly_date:        ly(d),
      ly_day:         day(ly(d)),
      ytd:            average(year_start..d),
      ly_same_period: average(ly_year_start..(d << 12)),
      ly_full:        average(ly_year_start..ly_year_end),
      weekday_ytd:    average((year_start..d).select { |x| x.wday == d.wday && x != d }),
      weekday_ly:     average((ly_year_start..ly_year_end).select { |x| x.wday == d.wday }),
      periods:        [week_period(d), month_period(d), year_period(d)],
      years:          years(d),
      recent:         ((d - RECENT_DAYS + 1)..d).map { |x| day_row(x) }.reverse,
      charts:         {
        last_days: last_days_chart(d),
        monthly:   monthly_chart(d),
        weekday:   weekday_chart(d),
        years:     years_chart(d)
      }
    )
  end

  def day_row(date)
    DayRow.new(date: date, day: day(date), ly_date: ly(date), ly_day: day(ly(date)))
  end

  # Suma de un rango de fechas y del rango equivalente del año anterior.
  def period(label, from, to, ly_from, ly_to)
    Period.new(label: label, from: from, to: to, current: sum(from..to),
               ly_from: ly_from, ly_to: ly_to, ly: sum(ly_from..ly_to))
  end

  # Totales de un conjunto de fechas (los días sin datos cuentan como 0).
  def sum(dates)
    days = dates.map { |x| day(x) }.compact
    Totals.new(
      total:        days.sum(&:total),
      tickets:      days.sum(&:tickets),
      people:       days.sum(&:people),
      people_sales: days.sum(&:people_sales),
      tips:         days.sum(&:tips),
      days:         days.count(&:open?)
    )
  end

  # Promedio sobre los días con ventas (los días sin tickets se consideran local cerrado y se excluyen).
  def average(dates)
    days = dates.map { |x| day(x) }.compact.select(&:open?)
    return Average.new(days: 0, avg_total: nil, avg_tickets: nil, avg_ticket: nil, avg_per_person: nil) if days.empty?

    t = sum(days.map(&:date))
    Average.new(days: days.size, avg_total: t.total / days.size, avg_tickets: t.tickets.to_f / days.size,
                avg_ticket: t.avg_ticket, avg_per_person: t.avg_per_person)
  end

  private

  # Semana en curso: de lunes al día informado. Se compara con los mismos días de la semana del año pasado.
  def week_period(d)
    from = d - ((d.wday - 1) % 7)
    period("Semana en curso (desde el lunes)", from, d, from - 364, d - 364)
  end

  # Mes y año en curso se comparan por calendario (mismas fechas del año anterior).
  def month_period(d)
    from = Date.new(d.year, d.month, 1)
    period("Mes en curso (#{MONTHS[d.month - 1]})", from, d, from << 12, d << 12)
  end

  def year_period(d)
    from = Date.new(d.year, 1, 1)
    period("Año en curso (desde el 1 de enero)", from, d, from << 12, d << 12)
  end

  # Comparativa de todos los años del histórico. Para cada año: el año completo y el
  # "mismo período" (1 ene -> misma fecha que el día informado), para comparar años incompletos de forma justa.
  def years(d)
    (@from.year..d.year).map do |y|
      from   = Date.new(y, 1, 1)
      to     = [Date.new(y, 12, 31), d].min
      ytd_to = d << (12 * (d.year - y)) # misma fecha en ese año (29 feb -> 28 feb)
      YearRow.new(year: y, full: sum(from..to), ytd: sum(from..ytd_to), ytd_to: ytd_to, complete: y < d.year)
    end.reverse
  end

  # ---------- gráficos ----------

  def last_days_chart(d)
    dates = ((d - CHART_DAYS + 1)..d).to_a
    {
      type:     "bar",
      labels:   dates.map { |x| x.strftime("%d/%m") },
      datasets: [
        { label: "#{d.year}", data: dates.map { |x| day(x)&.total&.round(2) } },
        { label: "#{d.year - 1} (día comparable)", data: dates.map { |x| day(ly(x))&.total&.round(2) }, type: "line" }
      ]
    }
  end

  def monthly_chart(d)
    {
      type:     "bar",
      labels:   MONTHS_SHORT,
      datasets: [
        { label: "#{d.year}", data: (1..12).map { |m| m <= d.month ? month_total(d.year, m, d) : nil } },
        { label: "#{d.year - 1}", data: (1..12).map { |m| month_total(d.year - 1, m, nil) } }
      ]
    }
  end

  # Una línea por año: permite ver estacionalidad y crecimiento de todos los años a la vez.
  def years_chart(d)
    {
      type:     "line",
      labels:   MONTHS_SHORT,
      datasets: (@from.year..d.year).map do |y|
        { label: y.to_s,
          data: (1..12).map { |m| y == d.year && m > d.month ? nil : month_total(y, m, d) } }
      end.reverse
    }
  end

  def month_total(year, month, upto)
    from = Date.new(year, month, 1)
    to   = Date.new(year, month, -1)
    to   = [to, upto].min if upto
    sum(from..to).total.round(2)
  end

  def weekday_chart(d)
    order = [1, 2, 3, 4, 5, 6, 0] # lunes a domingo
    ys    = Date.new(d.year, 1, 1)..d
    lys   = Date.new(d.year - 1, 1, 1)..Date.new(d.year - 1, 12, 31)
    {
      type:     "bar",
      labels:   order.map { |w| WEEKDAYS_SHORT[w] },
      datasets: [
        { label: "Promedio #{d.year}",     data: order.map { |w| average(ys.select { |x| x.wday == w }).avg_total&.round(2) } },
        { label: "Promedio #{d.year - 1}", data: order.map { |w| average(lys.select { |x| x.wday == w }).avg_total&.round(2) } }
      ]
    }
  end
end
