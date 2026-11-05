# frozen_string_literal: true

# Informe del comportamiento de los precios de compra de los insumos.
class IngredientsController < ApplicationController
  def index
    @prices = IngredientPrices.new(period: params[:period])
    @sort   = params[:sort].presence || "rise"
    @query  = params[:q].to_s.strip
    @rows   = @prices.sorted(@sort)
    @rows   = @rows.select { |r| r.name.to_s.downcase.include?(@query.downcase) } if @query.present?
  end

  def show
    @prices = IngredientPrices.new(period: params[:period])
    @row    = @prices.rows.find { |r| r.ingredient_id == params[:id].to_i }
    return redirect_to ingredients_path, alert: "Ese insumo no tiene compras en el período elegido." if @row.nil?

    # Historial completo del insumo, al margen del período elegido arriba.
    @history = IngredientPurchase.where(fudo_ingredient_id: @row.ingredient_id).chronological
  end

  # Descarga de Fudo las compras (botón "Actualizar compras").
  def sync
    run = PurchasesSync.catch_up!
    redirect_to ingredients_path(period: params[:period]), notice: run.message
  rescue StandardError => e
    redirect_to ingredients_path(period: params[:period]), alert: "No se pudieron actualizar las compras: #{e.message}"
  end
end
