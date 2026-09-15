# frozen_string_literal: true

# Correo con el informe diario de ventas. Plantillas en app/views/report_mailer/.
class ReportMailer < ApplicationMailer
  include FormatHelper # para armar el asunto
  helper  FormatHelper # para usarlo en las plantillas

  def daily(report_date)
    @m    = Metrics.new(report_date).build
    @name = AppSettings.restaurant_name

    mail(
      to:      AppSettings.mail_to,
      from:    AppSettings.mail_from,
      subject: "[#{@name}] #{report_subject(@m)}"
    )
  end
end
