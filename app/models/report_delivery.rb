# frozen_string_literal: true

# Registro de cada envío del informe diario por correo.
class ReportDelivery < ApplicationRecord
  STATUSES = %w[sending sent error].freeze
  validates :status, inclusion: { in: STATUSES }
  validates :report_date, presence: true

  scope :recent, -> { order(id: :desc) }

  def sent?  = status == "sent"
  def error? = status == "error"
end
