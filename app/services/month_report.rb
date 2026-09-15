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
end
