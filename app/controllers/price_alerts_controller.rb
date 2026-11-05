# frozen_string_literal: true

# Marcar una alerta de precio como vista, para que deje de aparecer arriba.
class PriceAlertsController < ApplicationController
  def acknowledge
    alert = PriceAlert.find(params[:id])
    alert.acknowledge!
    redirect_back fallback_location: ingredients_path, notice: "Alerta de #{alert.ingredient_name} marcada como vista."
  end
end
