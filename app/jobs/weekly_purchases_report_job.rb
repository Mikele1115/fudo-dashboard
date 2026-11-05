# frozen_string_literal: true

# Tarea programada (config/recurring.yml): resumen semanal de compras de insumos.
class WeeklyPurchasesReportJob < ApplicationJob
  queue_as :default

  def perform(on = nil)
    date = on ? Date.parse(on.to_s) : AppSettings.today
    PurchasesSync.catch_up! # por si la sincronización nocturna falló
    report = WeeklyPurchasesReport.new(date)
    return Rails.logger.info("WeeklyPurchasesReportJob: semana sin compras, no se envía") unless report.any?

    unless AppSettings.mail_configured?
      return Rails.logger.warn("WeeklyPurchasesReportJob: correo sin configurar, no se envía (faltan #{AppSettings.mail_missing.join(', ')})")
    end

    PurchasesMailer.weekly(date).deliver_now
    Rails.logger.info "WeeklyPurchasesReportJob: enviado a #{AppSettings.mail_to.join(', ')}"
  end
end
