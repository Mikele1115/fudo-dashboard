# frozen_string_literal: true

class SyncsController < ApplicationController
  def create
    if SyncRun.recent.first&.running?
      redirect_back_or_to root_path, alert: "Ya hay una sincronización en curso."
    elsif !AppSettings.fudo_configured?
      redirect_back_or_to root_path, alert: "Falta configurar #{AppSettings.fudo_missing.join(' y ')} en el archivo .env."
    else
      # Es el único botón del panel: hace lo mismo que la corrida nocturna salvo el
      # correo. Sin notify a propósito, ver SyncSalesJob.
      SyncSalesJob.perform_later(requested_date.to_s, with_purchases: true, notify: false)
      redirect_back_or_to root_path,
                          notice: "Sincronización iniciada: ventas, compras y productos. Puede tardar unos minutos."
    end
  end
end
