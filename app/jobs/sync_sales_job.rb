# frozen_string_literal: true

# Sincroniza con Fudo en segundo plano: ventas (botón "Sincronizar" del dashboard)
# y, en la corrida nocturna, también las compras de insumos.
class SyncSalesJob < ApplicationJob
  queue_as :default

  def perform(report_date = nil, with_purchases: false)
    date = report_date ? Date.parse(report_date.to_s) : AppSettings.report_day
    SalesSync.run!(date)
    return unless with_purchases

    # Las compras se actualizan solo en la tarea nocturna: el botón del dashboard
    # es para las ventas del día y debe responder rápido.
    PurchasesSync.catch_up!
    # El catálogo trae la categoría que el usuario mantiene en Fudo: si allí
    # recategoriza un insumo, aquí se refleja en esta corrida.
    IngredientsSync.run!
    # Un insumo nuevo se queda sin tipo hasta que pasan las reglas. Pasarlas
    # aquí es seguro: nunca tocan lo asignado a mano.
    IngredientClassifier.run!
    # Fudo no tiene webhooks, así que los saltos de precio se detectan aquí,
    # sobre lo que acaba de descargarse.
    PriceAlertDetector.run!
    AlertNotifier.call
  end
end
