# frozen_string_literal: true

# Descarga de Fudo las ventas cerradas y guarda el total y los tickets de cada día
# de negocio en la tabla daily_sales. Solo pide a la API lo que falta (más los
# últimos REFRESH_DAYS días, por si hubo ventas cerradas tarde o correcciones).
class SalesSync
  CHUNK_DAYS = 31 # tamaño de cada consulta a la API al descargar el histórico

  # Sincroniza todo lo necesario para poder calcular el informe de `report_date`.
  def self.run!(report_date = AppSettings.report_day)
    new.ensure(Metrics.required_from(report_date), report_date,
               refresh_from: report_date - AppSettings.refresh_days)
  end

  def initialize(client: Fudo::Client.new, tz: AppSettings.timezone, cutoff_hour: AppSettings.cutoff_hour, logger: Rails.logger)
    @client = client
    @tz     = tz
    @cutoff = cutoff_hour
    @logger = logger
  end

  # Asegura datos para from_date..to_date. Los días >= refresh_from se vuelven a descargar siempre.
  # Devuelve el SyncRun con el resultado.
  def ensure(from_date, to_date, refresh_from: nil)
    run = SyncRun.create!(status: "running", started_at: Time.current, from_date: from_date, to_date: to_date)

    existing = DailySale.where(date: from_date..to_date).pluck(:date).to_set
    missing  = (from_date..to_date).select { |d| !existing.include?(d) || (refresh_from && d >= refresh_from) }

    days  = 0
    sales = 0
    contiguous_ranges(missing).each do |a, b|
      d, s = fetch_range(a, b)
      days  += d
      sales += s
    end

    run.update!(status: "ok", finished_at: Time.current, days_synced: days, sales_count: sales,
                message: missing.empty? ? "Nada que actualizar" : "#{days} días actualizados (#{sales} ventas)")
    run
  rescue StandardError => e
    @logger.error "SalesSync: #{e.class}: #{e.message}"
    run&.update!(status: "error", finished_at: Time.current, message: "#{e.class}: #{e.message}")
    raise
  end

  # Instante (UTC) en que empieza el día de negocio `date` en la zona horaria local.
  def day_start_utc(date)
    naive = Time.utc(date.year, date.month, date.day, @cutoff, 0, 0)
    @tz.local_to_utc(naive) { |periods| periods.first }
  rescue TZInfo::PeriodNotFound
    # Hueco por cambio de hora (ej. las 00:00 no existen ese día): usar la hora siguiente.
    @tz.local_to_utc(naive + 3600) { |periods| periods.first }
  end

  # Día de negocio al que pertenece un instante UTC.
  def business_date(utc_time)
    local = @tz.to_local(utc_time)
    Time.at(utc_time.to_i + local.utc_offset - (@cutoff * 3600)).utc.to_date
  end

  private

  # [1,2,3,7,8] -> [[1,3],[7,8]]
  def contiguous_ranges(dates)
    dates.each_with_object([]) do |d, ranges|
      if ranges.any? && ranges.last[1] + 1 == d
        ranges.last[1] = d
      else
        ranges << [d, d]
      end
    end
  end

  # Descarga un rango de días en trozos de CHUNK_DAYS y guarda los totales. Devuelve [días, ventas].
  def fetch_range(from_date, to_date)
    days_count  = 0
    sales_count = 0
    cur = from_date
    while cur <= to_date
      chunk_end = [cur + CHUNK_DAYS - 1, to_date].min
      @logger.info "SalesSync: descargando ventas #{cur} -> #{chunk_end}"

      sales = @client.closed_sales(day_start_utc(cur), day_start_utc(chunk_end + 1))

      agg = Hash.new { |h, k| h[k] = { total: 0.0, tickets: 0, people: 0, people_sales: 0.0, tips: 0.0 } }
      (cur..chunk_end).each { |d| agg[d] } # días sin ventas quedan en 0 (local cerrado)
      sales.each do |s|
        d = business_date(s[:closed_at])
        next unless d.between?(cur, chunk_end)

        day = agg[d]
        day[:total]   += s[:total]
        day[:tickets] += 1
        day[:tips]    += s[:tips]
        # Ticket por persona: solo cuentan las ventas con comensales registrados (salón).
        if s[:people].positive?
          day[:people]       += s[:people]
          day[:people_sales] += s[:total]
        end
      end

      now  = Time.current
      rows = agg.map do |d, v|
        { date: d, total: v[:total].round(2), tickets: v[:tickets], people: v[:people],
          people_sales: v[:people_sales].round(2), tips: v[:tips].round(2), synced_at: now }
      end
      DailySale.upsert_all(rows, unique_by: :date)

      days_count  += rows.size
      sales_count += sales.size
      cur = chunk_end + 1
    end
    [days_count, sales_count]
  end
end
