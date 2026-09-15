# frozen_string_literal: true

# Configuración SMTP leída del archivo .env (ver .env.example). En test se usa el
# adaptador :test de Rails y no se envía nada.
ActiveSupport.on_load(:action_mailer) do
  next if Rails.env.test? || !AppSettings.mail_configured?

  self.delivery_method       = :smtp
  self.perform_deliveries    = true
  self.raise_delivery_errors = true
  self.smtp_settings = {
    address:              ENV.fetch("SMTP_HOST"),
    port:                 ENV.fetch("SMTP_PORT").to_i,
    user_name:            ENV.fetch("SMTP_USER"),
    password:             ENV.fetch("SMTP_PASSWORD"),
    authentication:       :plain,
    enable_starttls_auto: true,
    open_timeout:         20,
    read_timeout:         60
  }
end
