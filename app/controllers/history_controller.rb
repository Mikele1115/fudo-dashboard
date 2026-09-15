# frozen_string_literal: true

class HistoryController < ApplicationController
  def index
    year, month = parse_month(params[:month])
    @report = MonthReport.new(year, month)
  end

  private

  # "2026-09" -> [2026, 9]; por defecto el mes del último día informado.
  def parse_month(value)
    if value.to_s =~ /\A(\d{4})-(\d{1,2})\z/ && (1..12).cover?(Regexp.last_match(2).to_i)
      [Regexp.last_match(1).to_i, Regexp.last_match(2).to_i]
    else
      d = AppSettings.report_day
      [d.year, d.month]
    end
  end
end
