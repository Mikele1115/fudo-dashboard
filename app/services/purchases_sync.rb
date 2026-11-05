# frozen_string_literal: true

# Descarga de Fudo las compras de insumos (lineas de egresos) y las guarda en
# ingredient_purchases. Cada linea se identifica por su id en Fudo, asi que
# volver a sincronizar un periodo actualiza en vez de duplicar.
class PurchasesSync
  CHUNK_MONTHS   = 3 # tamano de cada consulta a la API al descargar el historico
  DEFAULT_YEARS  = 3 # cuanto historico traer la primera vez

  def self.run!(from: nil, to: nil)
    new.ensure(from: from, to: to)
  end

  # Sincronizacion incremental para la tarea nocturna: solo los ultimos dias.
  def self.catch_up!
    to   = AppSettings.today
    from = last_date ? last_date - AppSettings.refresh_days : default_from
    new.ensure(from: from, to: to)
  end

  def self.last_date = IngredientPurchase.last_purchase_date

  def self.default_from = AppSettings.today - (DEFAULT_YEARS * 365)

  def initialize(client: Fudo::Client.new, logger: Rails.logger)
    @client = client
    @logger = logger
  end

  # Devuelve el SyncRun con el resultado.
  def ensure(from: nil, to: nil)
    from ||= self.class.default_from
    to   ||= AppSettings.today
    run = SyncRun.create!(status: "running", started_at: Time.current, from_date: from, to_date: to, kind: "purchases")

    lines = 0
    each_chunk(from, to) do |a, b|
      lines += fetch_range(a, b)
    end

    run.update!(status: "ok", finished_at: Time.current, sales_count: lines,
                message: lines.zero? ? "Sin compras nuevas" : "#{lines} lineas de compra actualizadas")
    run
  rescue StandardError => e
    @logger.error "PurchasesSync: #{e.class}: #{e.message}"
    run&.update!(status: "error", finished_at: Time.current, message: "#{e.class}: #{e.message}")
    raise
  end

  private

  def each_chunk(from, to)
    cur = from
    while cur <= to
      chunk_end = [cur.next_month(CHUNK_MONTHS) - 1, to].min
      yield cur, chunk_end
      cur = chunk_end + 1
    end
  end

  def fetch_range(from, to)
    @logger.info "PurchasesSync: #{from} -> #{to}"
    rows = @client.ingredient_purchases(from, to)
    return 0 if rows.empty?

    now = Time.current
    records = rows.map do |r|
      {
        fudo_item_id:       r[:item_id],
        fudo_expense_id:    r[:expense_id],
        fudo_ingredient_id: r[:ingredient_id],
        ingredient_name:    r[:ingredient_name],
        unit_name:          r[:unit_name],
        detail:             r[:detail],
        provider_name:      r[:provider_name],
        purchased_on:       r[:date],
        quantity:           r[:quantity],
        line_total:         r[:line_total],
        unit_price:         r[:line_total] / r[:quantity],
        synced_at:          now,
        created_at:         now,
        updated_at:         now
      }
    end

    # upsert_all evita duplicados usando el indice unico de fudo_item_id.
    records.each_slice(500) do |slice|
      IngredientPurchase.upsert_all(slice, unique_by: :fudo_item_id)
    end
    records.size
  end
end
