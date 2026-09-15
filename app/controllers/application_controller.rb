class ApplicationController < ActionController::Base
  include Authentication # login obligatorio en toda la app (app/controllers/concerns/authentication.rb)
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :last_sync, :last_delivery

  private

  # Fecha pedida en ?date=YYYY-MM-DD, acotada al último día de negocio completo.
  def requested_date
    date = Date.parse(params[:date].to_s)
    [date, AppSettings.report_day].min
  rescue Date::Error
    AppSettings.report_day
  end

  def last_sync     = @last_sync ||= SyncRun.recent.first
  def last_delivery = @last_delivery ||= ReportDelivery.recent.first
end
