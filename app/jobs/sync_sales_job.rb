# frozen_string_literal: true

# Sincroniza con Fudo en segundo plano. Dos usos, con alcance distinto:
#
#   nocturno (recurring.yml, 00:00)  -> todo, y además avisa por correo
#   botón "Sincronizar" del panel    -> ventas y precios de venta, SIN correos
#
# El botón no manda correos a propósito. Las alertas de precios van a varias personas
# y no pueden salir cada vez que alguien pulsa un botón: los saltos de precio se
# detectan igual y el aviso sale en la corrida de la noche.
class SyncSalesJob < ApplicationJob
  queue_as :default

  # with_products y notify siguen a with_purchases salvo que se diga lo contrario, para
  # que la corrida nocturna no tenga que enumerarlo todo.
  def perform(report_date = nil, with_purchases: false, with_products: with_purchases,
              notify: with_purchases)
    date = report_date ? Date.parse(report_date.to_s) : AppSettings.report_day
    SalesSync.run!(date)

    if with_purchases
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
      AlertNotifier.call if notify
    end

    return unless with_products

    # Precios de VENTA. Van al final a propósito: si algo de esto fallara, las ventas,
    # las compras y las alertas —que es lo que se mira cada mañana— ya están guardadas.
    #
    # El catálogo se baja entero porque es la única forma de saber que un precio de
    # carta cambió: la API no guarda historial ni trae updatedAt, así que ProductsSync
    # compara con la foto anterior y anota solo lo que se movió.
    ProductsSync.run!
    SaleItemsSync.catch_up!
  end
end
