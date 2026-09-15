# frozen_string_literal: true

# Configuración de la app leída del archivo .env (ver .env.example).
module AppSettings
  module_function

  def restaurant_name = env("RESTAURANT_NAME", "Restaurante")
  def timezone_name   = env("TZ_NAME", "America/Santiago")
  def timezone        = TZInfo::Timezone.get(timezone_name)
  def cutoff_hour     = env("BUSINESS_DAY_CUTOFF_HOUR", "0").to_i
  def compare_mode    = env("COMPARE_MODE", "weekday") == "date" ? "date" : "weekday"
  def currency_symbol = env("CURRENCY_SYMBOL", "$")
  def decimals        = env("DECIMALS", "0").to_i
  def refresh_days    = env("REFRESH_DAYS", "3").to_i
  def vat_rate        = env("VAT_RATE", "0.19").to_f
  # Primer día del histórico a descargar (todos los años que quieres comparar).
  def history_from    = Date.parse(env("HISTORY_FROM", "#{today.year - 1}-01-01"))
  def mail_from       = env("MAIL_FROM", "")
  def mail_to         = env("MAIL_TO", "").split(",").map(&:strip).reject(&:empty?)

  def fudo_missing = %w[FUDO_API_KEY FUDO_API_SECRET].select { |k| env(k).nil? }
  def mail_missing = %w[SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASSWORD MAIL_FROM MAIL_TO].select { |k| env(k).nil? }
  def fudo_configured? = fudo_missing.empty?
  def mail_configured? = mail_missing.empty?

  # Día de negocio actual en la zona horaria del local (antes de la hora de corte sigue siendo "ayer").
  def today
    now = timezone.now
    now.hour < cutoff_hour ? now.to_date - 1 : now.to_date
  end

  # Día que informa el reporte diario: el último día de negocio completo.
  def report_day = today - 1

  def env(key, default = nil)
    v = ENV[key].to_s.strip
    v.empty? ? default : v
  end
end
