# frozen_string_literal: true

# Informe del comportamiento de los precios de compra de los insumos.
class IngredientsController < ApplicationController
  def index
    @alerts = PriceAlert.pending.recent.limit(10)
    @prices = IngredientPrices.new(period: params[:period])
    @sort   = params[:sort].presence || "rise"
    @query  = params[:q].to_s.strip
    @rows   = @prices.sorted(@sort)
    @rows   = @rows.select { |r| r.name.to_s.downcase.include?(@query.downcase) } if @query.present?
    @typos  = QuantityTypos.all.size
  end

  # Lineas donde el monto cuadra y la cantidad no: errores de carga a corregir
  # en Fudo. Ver QuantityTypos.
  def review
    @period_key = IngredientPrices::PERIODS.key?(params[:period].to_s) ? params[:period].to_s : "12"
    @all        = QuantityTypos.all
    @from       = inicio_del_periodo(@period_key)
    @findings   = @from ? @all.select { |f| f.on >= @from } : @all
  end

  def show
    @prices = IngredientPrices.new(period: params[:period])
    @alerts = PriceAlert.where(fudo_ingredient_id: params[:id].to_i).recent.limit(5)
    @row    = @prices.rows.find { |r| r.ingredient_id == params[:id].to_i }
    return redirect_to ingredients_path, alert: "Ese insumo no tiene compras en el período elegido." if @row.nil?

    # Historial completo del insumo, al margen del período elegido arriba.
    @history = IngredientPurchase.where(fudo_ingredient_id: @row.ingredient_id).chronological
  end

  # Descarga de Fudo las compras (botón "Actualizar compras").
  def sync
    run = PurchasesSync.catch_up!
    IngredientsSync.run!   # trae la categoría que tengan en Fudo ahora mismo
    IngredientClassifier.run!
    redirect_to ingredients_path(period: params[:period]), notice: run.message
  rescue StandardError => e
    redirect_to ingredients_path(period: params[:period]), alert: "No se pudieron actualizar las compras: #{e.message}"
  end

  private

  # Las fechas se cuentan desde la ultima compra descargada, no desde hoy: si la
  # sincronizacion va con retraso, "3 meses" tiene que seguir mostrando algo.
  def inicio_del_periodo(key)
    return nil if key == "all"

    hasta = IngredientPurchase.last_purchase_date || AppSettings.today
    hasta.prev_month(key.to_i) + 1
  end
end
