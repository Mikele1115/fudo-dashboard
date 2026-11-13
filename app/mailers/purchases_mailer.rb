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

    # El asunto no puede decir "subió un 164%" de una compra cuya cantidad está mal
    # cargada: el precio no subió. Para esas, el asunto manda a revisar la carga.
    titulo = if @alerts.size == 1
               a = @alerts.first
               if a.suspect?
                 "#{a.ingredient_name}: revisar la cantidad cargada"
               else
                 "#{a.ingredient_name} subió #{pct_text(a.new_price.to_f, a.baseline_price.to_f)}"
               end
             else
               PriceAlert.headline(@alerts)
             end

    mail(
      to:      AppSettings.mail_to,
      from:    AppSettings.mail_from,
      subject: "[#{@name}] #{@alerts.all?(&:suspect?) ? 'Revisar cargas' : 'Alerta de precios'} — #{titulo}"
    )
  end
end
