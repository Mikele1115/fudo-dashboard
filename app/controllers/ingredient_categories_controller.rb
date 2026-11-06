# frozen_string_literal: true

# Pantalla para asignar cada insumo a una categoría y crear categorías nuevas.
class IngredientCategoriesController < ApplicationController
  def index
    @prices     = IngredientPrices.new(period: "12")
    @categories = IngredientCategory.ordered
    @filter     = params[:filter].presence || "todos"
    @rows       = filtered_rows
  end

  # Guarda de una vez todas las asignaciones cambiadas en la pantalla.
  def update
    cambios = 0
    (params[:assignments] || {}).each do |ingredient_id, category_id|
      cambios += 1 if assign(ingredient_id.to_i, category_id)
    end

    redirect_to ingredient_categories_path(filter: params[:filter]),
                notice: cambios.zero? ? "No hubo cambios que guardar." : "#{cambios} insumo#{'s' if cambios > 1} actualizado#{'s' if cambios > 1}."
  end

  def create
    categoria = IngredientCategory.new(name: params[:name].to_s.strip, area: params[:area])
    if categoria.save
      redirect_to ingredient_categories_path, notice: "Categoría «#{categoria.name}» creada en #{categoria.area}."
    else
      redirect_to ingredient_categories_path, alert: "No se pudo crear: #{categoria.errors.full_messages.join(', ')}"
    end
  end

  # Vuelve a pasar las reglas automáticas. Nunca pisa lo asignado a mano.
  def reclassify
    asignados, sin = IngredientClassifier.run!
    redirect_to ingredient_categories_path,
                notice: "#{asignados} insumos asignados por regla; #{sin.size} siguen sin categoría."
  end

  private

  def filtered_rows
    todas = @prices.rows.sort_by { |r| -r.spend }
    case @filter
    when "sin"    then todas.reject { |r| @prices.assignments[r.ingredient_id] }
    when "manual" then todas.select { |r| manual_ids.include?(r.ingredient_id) }
    when "auto"   then todas.select { |r| auto_ids.include?(r.ingredient_id) }
    else               todas
    end
  end

  def manual_ids = @manual_ids ||= IngredientAssignment.manual.pluck(:fudo_ingredient_id).to_set
  def auto_ids   = @auto_ids   ||= IngredientAssignment.automatic.pluck(:fudo_ingredient_id).to_set

  # Devuelve true si cambió algo. Guardar a mano marca la asignación como no automática,
  # para que una futura pasada de las reglas la respete.
  def assign(ingredient_id, category_id)
    actual = IngredientAssignment.find_by(fudo_ingredient_id: ingredient_id)

    if category_id.blank?
      return false if actual.nil?

      actual.destroy
      return true
    end

    return false if actual&.ingredient_category_id == category_id.to_i && !actual.automatic

    asignacion = actual || IngredientAssignment.new(fudo_ingredient_id: ingredient_id)
    asignacion.ingredient_category_id = category_id
    asignacion.ingredient_name = nombre_de(ingredient_id)
    asignacion.automatic = false
    asignacion.save!
    true
  end

  def nombre_de(ingredient_id)
    IngredientPurchase.where(fudo_ingredient_id: ingredient_id).newest.first&.ingredient_name
  end
end
