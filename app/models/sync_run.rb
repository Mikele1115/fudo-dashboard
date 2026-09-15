# frozen_string_literal: true

# Registro de cada sincronización con Fudo (para mostrar el estado en el dashboard).
class SyncRun < ApplicationRecord
  STATUSES = %w[running ok error].freeze
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(id: :desc) }

  def running? = status == "running"
  def ok?      = status == "ok"
  def error?   = status == "error"
end
