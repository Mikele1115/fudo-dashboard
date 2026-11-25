# frozen_string_literal: true

# Precios de venta: qué cobras por cada plato, por canal, y cómo se ha movido.
class ProductsController < ApplicationController
  def index
    @prices = ProductPrices.new(period: params[:period])
    @query  = params[:q].to_s.strip
    @sort   = params[:sort].presence || "ingreso"
    @show_all = params[:all].present?
    @grupos = ordenar(@prices.con_ventas, @sort)
  end

  def show
    @prices  = ProductPrices.new(period: params[:period])
    @product = Product.find_by(fudo_product_id: params[:id].to_i)
    return redirect_to products_path, alert: "Ese producto no existe." if @product.nil?

    @grupo   = @prices.grupos.find { |g| g.name == @product.base_name }
    @history = SaleItem.where(fudo_product_id: @grupo ? ids_del_grupo : [@product.fudo_product_id])
                       .cobradas.chronological
    @changes = ProductPriceChange.where(fudo_product_id: ids_del_grupo).recent.limit(20)
  end

  # Botón "Actualizar productos": catálogo y líneas de venta.
  def sync
    catalogo = ProductsSync.run!
    lineas   = SaleItemsSync.catch_up!
    redirect_to products_path(period: params[:period]),
                notice: "#{catalogo.message}. #{lineas.message}."
  rescue StandardError => e
    redirect_to products_path(period: params[:period]),
                alert: "No se pudieron actualizar los productos: #{e.message}"
  end

  private

  def ids_del_grupo = @grupo ? @grupo.canales.map { |c| c.product.fudo_product_id } : [@product.fudo_product_id]

  def ordenar(grupos, key)
    case key
    when "alza"     then grupos.sort_by { |g| -(g.change_pct || -Float::INFINITY) }
    when "baja"     then grupos.sort_by { |g| g.change_pct || Float::INFINITY }
    when "impacto"  then grupos.sort_by { |g| -g.impacto.abs }
    when "unidades" then grupos.sort_by { |g| -g.unidades }
    when "nombre"   then grupos.sort_by { |g| g.name.to_s.downcase }
    else                 grupos.sort_by { |g| -g.ingreso } # "ingreso"
    end
  end
end
