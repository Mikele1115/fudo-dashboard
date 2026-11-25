# frozen_string_literal: true

# Sincroniza con Fudo en segundo plano: ventas (botón "Sincronizar" del dashboard)
# y, en la corrida nocturna, también las compras de insumos y los precios de venta.
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

    # Precios de VENTA. Van al final a propósito: si algo de esto fallara, las ventas,
    # las compras y las alertas —que es lo que se mira cada mañana— ya están guardadas.
    #
    # El catálogo se baja entero cada noche porque es la única forma de saber que un
    # precio de carta cambió: la API no guarda historial ni trae updatedAt, así que
    # ProductsSync compara con la foto de ayer y anota solo lo que se movió.
    ProductsSync.run!
    SaleItemsSync.catch_up!
  end
end
