# frozen_string_literal: true

# Informe del comportamiento de los precios de compra de los insumos.
class IngredientsController < ApplicationController
  def index
    @alerts = PriceAlert.pending.recent.limit(10)
    # Un solo QuantityTypos.all por petición: lo necesitan el análisis de precios (para
    # dejar las líneas mal cargadas fuera de las medianas) y el contador del botón.
    typos   = QuantityTypos.all
    @prices = IngredientPrices.new(period: params[:period], typos: typos)
    @sort   = params[:sort].presence || "rise"
    @query  = params[:q].to_s.strip
    # La tabla no se dibuja entera por defecto: casi siempre se busca uno. Con ?all=1 se
    # pide el listado completo a propósito.
    #
    # Las filas se mandan TODAS y el filtrado lo hace filtro_controller.js mientras se
    # escribe. La vista marca cuáles coinciden con ?q= para que un enlace con búsqueda
    # funcione aunque el JS no cargue; el controlador recalcula lo mismo al arrancar.
    @show_all = params[:all].present?
    @rows     = @prices.sorted(@sort)
    @typos  = typos.size
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

  private

  # Las fechas se cuentan desde la ultima compra descargada, no desde hoy: si la
  # sincronizacion va con retraso, "3 meses" tiene que seguir mostrando algo.
  def inicio_del_periodo(key)
    return nil if key == "all"

    hasta = IngredientPurchase.last_purchase_date || AppSettings.today
    hasta.prev_month(key.to_i) + 1
  end
end
