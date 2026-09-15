# frozen_string_literal: true

# Total de ventas cerradas y cantidad de tickets de un día de negocio, descargado de Fudo.
class DailySale < ApplicationRecord
  validates :date, presence: true, uniqueness: true
  validates :total, :tickets, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :between, ->(from, to) { where(date: from..to).order(:date) }

  def avg_ticket
    tickets.positive? ? total / tickets : nil
  end
end
