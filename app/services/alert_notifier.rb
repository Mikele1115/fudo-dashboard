# frozen_string_literal: true

# Avisa por correo de las alertas de precio que aún no se han notificado.
#
# Se agrupan en un solo correo por corrida: si una noche entran tres saltos de
# precio, llega un correo con los tres y no tres correos sueltos.
class AlertNotifier
  def self.call = new.call

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  def call
    pending = PriceAlert.unnotified.recent.to_a
    return [] if pending.empty?

    unless AppSettings.mail_configured?
      @logger.warn "AlertNotifier: #{pending.size} alertas sin enviar, falta configurar el correo (#{AppSettings.mail_missing.join(', ')})"
      return []
    end

    PurchasesMailer.price_alerts(pending.map(&:id)).deliver_now
    PriceAlert.where(id: pending.map(&:id)).update_all(notified_at: Time.current)
    @logger.info "AlertNotifier: avisadas #{pending.size} alertas a #{AppSettings.mail_to.join(', ')}"
    pending
  end
end
