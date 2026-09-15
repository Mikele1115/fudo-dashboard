# frozen_string_literal: true

# Tarea programada (config/recurring.yml): sincroniza y envía el informe del día que acaba de terminar.
class DailyReportJob < ApplicationJob
  queue_as :default

  def perform(report_date = nil)
    date = report_date ? Date.parse(report_date.to_s) : AppSettings.report_day
    SalesSync.run!(date)
    ReportSender.call(date)
  end
end
