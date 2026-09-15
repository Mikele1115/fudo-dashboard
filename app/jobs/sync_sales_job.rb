# frozen_string_literal: true

# Sincroniza las ventas con Fudo en segundo plano (botón "Sincronizar" del dashboard).
class SyncSalesJob < ApplicationJob
  queue_as :default

  def perform(report_date = nil)
    date = report_date ? Date.parse(report_date.to_s) : AppSettings.report_day
    SalesSync.run!(date)
  end
end
