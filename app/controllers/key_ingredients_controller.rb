# frozen_string_literal: true

# Marca y desmarca insumos clave, y ajusta su umbral de aviso. Ver KeyIngredient.
class KeyIngredientsController < ApplicationController
  before_action :set_ingredient

  def create
    clave = KeyIngredient.find_or_initialize_by(fudo_ingredient_id: @id)
    clave.ingredient_name = @nombre
    clave.change_pct = umbral if params.key?(:change_pct)
    guardar(clave, "#{@nombre} es ahora un insumo clave.")
  end

  def update
    clave = KeyIngredient.find_by!(fudo_ingredient_id: @id)
    clave.change_pct = umbral
    guardar(clave, "Umbral de #{@nombre} actualizado.")
  end

  def destroy
    KeyIngredient.where(fudo_ingredient_id: @id).destroy_all
    redirect_back_or_to ingredient_path(@id), notice: "#{@nombre} ya no es un insumo clave."
  end

  private

  def set_ingredient
    @id = params[:id].to_i
    @nombre = IngredientPurchase.where(fudo_ingredient_id: @id).order(:purchased_on).pick(:ingredient_name)
    redirect_to ingredients_path, alert: "Ese insumo no existe." if @nombre.nil?
  end

  # Vacío = el umbral por defecto de los claves.
  def umbral = params[:change_pct].to_s.tr(",", ".").presence

  def guardar(clave, aviso)
    if clave.save
      redirect_back_or_to ingredient_path(@id), notice: aviso
    else
      redirect_back_or_to ingredient_path(@id), alert: clave.errors.full_messages.to_sentence
    end
  end
end
