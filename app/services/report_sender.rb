# frozen_string_literal: true

# Envía el informe de un día por correo y deja registro en report_deliveries.
class ReportSender
  def self.call(report_date)
    new(report_date).call
  end

  def initialize(report_date)
    @date = report_date
  end

  def call
    unless AppSettings.mail_configured?
      raise "Falta configurar el correo en .env: #{AppSettings.mail_missing.join(', ')}"
    end

    delivery = ReportDelivery.create!(report_date: @date, status: "sending", recipients: AppSettings.mail_to.join(", "))
    begin
      ReportMailer.daily(@date).deliver_now
      delivery.update!(status: "sent", sent_at: Time.current)
    rescue StandardError => e
      delivery.update!(status: "error", message: "#{e.class}: #{e.message}")
      raise
    end
    delivery
  end
end
