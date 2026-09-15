# frozen_string_literal: true

class ReportsController < ApplicationController
  # Vista previa del correo tal como se enviará.
  def show
    @m    = Metrics.new(requested_date).build
    @name = AppSettings.restaurant_name
    render template: "report_mailer/daily", layout: false, formats: [:html]
  end

  # Envía el informe del día indicado ahora mismo.
  def create
    date     = requested_date
    delivery = ReportSender.call(date)
    redirect_to root_path(date: date), notice: "Informe del #{date} enviado a #{delivery.recipients}."
  rescue StandardError => e
    redirect_to root_path(date: date), alert: "No se pudo enviar el informe: #{e.message}"
  end
end
