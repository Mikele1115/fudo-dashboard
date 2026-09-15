# frozen_string_literal: true

class SyncsController < ApplicationController
  def create
    if SyncRun.recent.first&.running?
      redirect_back_or_to root_path, alert: "Ya hay una sincronización en curso."
    elsif !AppSettings.fudo_configured?
      redirect_back_or_to root_path, alert: "Falta configurar #{AppSettings.fudo_missing.join(' y ')} en el archivo .env."
    else
      SyncSalesJob.perform_later(requested_date.to_s)
      redirect_back_or_to root_path, notice: "Sincronización iniciada. La primera vez puede tardar unos minutos."
    end
  end
end
