# frozen_string_literal: true

# Configuración de la app leída del archivo .env (ver .env.example).
module AppSettings
  module_function

  def restaurant_name = env("RESTAURANT_NAME", "Restaurante")

  # Raíz de la aplicación web de Fudo, para enlazar a la pantalla de edición de un
  # producto o un insumo. No sale de la API: es la URL que se ve en el navegador al
  # editar uno. Configurable por si Fudo cambia de dominio y hay que arreglarlo sin
  # tocar código.
  def fudo_app_url = env("FUDO_APP_URL", "https://app-v2.fu.do/app/#!")
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
  def mail_to         = lista("MAIL_TO")

  # Destinatarios SOLO de las alertas de precio, además de MAIL_TO.
  #
  # Va aparte a propósito: MAIL_TO recibe también el informe diario de ventas, con la
  # facturación del local. Que alguien tenga que enterarse de que subió la mozzarella no
  # significa que deba ver cuánto se vendió ayer. Se suma a MAIL_TO en vez de sustituirlo
  # para que nadie pueda quedarse fuera de sus propias alertas por editar mal una variable.
  def price_alerts_extra_to = lista("PRICE_ALERTS_EXTRA_TO")
  def price_alerts_to       = (mail_to + price_alerts_extra_to).uniq

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

  # Una variable con varias direcciones separadas por comas.
  def lista(key) = env(key, "").split(",").map(&:strip).reject(&:empty?)
end
