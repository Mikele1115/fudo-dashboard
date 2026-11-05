# frozen_string_literal: true

# Correos de compras de insumos: el resumen semanal y los avisos de precio.
# Plantillas en app/views/purchases_mailer/.
class PurchasesMailer < ApplicationMailer
  include FormatHelper # para armar el asunto
  helper  FormatHelper # para usarlo en las plantillas
  helper  IngredientsHelper

  def weekly(on = AppSettings.today)
    @r     = WeeklyPurchasesReport.new(on)
    @name  = AppSettings.restaurant_name

    mail(
      to:      AppSettings.mail_to,
      from:    AppSettings.mail_from,
      subject: "[#{@name}] #{@r.subject}"
    )
  end

  # Aviso inmediato de uno o varios saltos de precio.
  def price_alerts(alert_ids)
    @alerts = PriceAlert.where(id: alert_ids).recent.to_a
    @name   = AppSettings.restaurant_name
    return if @alerts.empty?

    titulo = if @alerts.size == 1
               a = @alerts.first
               "#{a.ingredient_name} subió #{pct_text(a.new_price.to_f, a.baseline_price.to_f)}"
             else
               "#{@alerts.size} insumos subieron de precio"
             end

    mail(
      to:      AppSettings.mail_to,
      from:    AppSettings.mail_from,
      subject: "[#{@name}] Alerta de precios — #{titulo}"
    )
  end
end
