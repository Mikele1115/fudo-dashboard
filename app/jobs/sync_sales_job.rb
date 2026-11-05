# frozen_string_literal: true

# Sincroniza con Fudo en segundo plano: ventas (botón "Sincronizar" del dashboard)
# y, en la corrida nocturna, también las compras de insumos.
class SyncSalesJob < ApplicationJob
  queue_as :default

  def perform(report_date = nil, with_purchases: false)
    date = report_date ? Date.parse(report_date.to_s) : AppSettings.report_day
    SalesSync.run!(date)
    # Las compras se actualizan solo en la tarea nocturna: el botón del dashboard
    # es para las ventas del día y debe responder rápido.
    PurchasesSync.catch_up! if with_purchases
  end
end
