# Datos ficticios para probar el dashboard sin conexión a Fudo:
#   bin/rails db:seed
# Se borran al sincronizar con Fudo (upsert por fecha) o con: bin/rails runner "DailySale.delete_all"
if !Rails.env.development?
  puts "Los datos de demostración solo se cargan en desarrollo (RAILS_ENV=#{Rails.env})."
elsif DailySale.exists?
  puts "daily_sales ya tiene datos; no se cargan datos de demostración."
else
  rng  = Random.new(42)
  to   = AppSettings.report_day
  from = AppSettings.history_from
  rows = (from..to).map do |d|
    next { date: d, total: 0, tickets: 0, people: 0, people_sales: 0, tips: 0, synced_at: Time.current } if d.wday == 1 # cierra los lunes

    base    = 800_000 + (d.year - from.year) * 80_000            # crece año a año
    weekday = { 5 => 1.35, 6 => 1.5, 0 => 1.2 }.fetch(d.wday, 1.0) # viernes, sábado y domingo más fuertes
    season  = 1 + 0.15 * Math.sin((d.yday / 365.0) * 2 * Math::PI) # estacionalidad
    total   = (base * weekday * season * (0.85 + rng.rand * 0.3)).round
    tickets = (total / (9_500 + rng.rand * 2_000)).round
    people  = (tickets * 0.65 * 2.3).round                       # ~65% de las ventas son de salón, 2,3 personas por mesa
    { date: d, total: total, tickets: tickets, people: people, people_sales: (total * 0.7).round,
      tips: (total * 0.08).round, synced_at: Time.current }
  end
  DailySale.insert_all(rows)
  SyncRun.create!(status: "ok", started_at: Time.current, finished_at: Time.current, from_date: from, to_date: to,
                  days_synced: rows.size, message: "Datos de demostración (db/seeds.rb)")
  puts "Cargados #{rows.size} días de demostración (#{from} → #{to})."
end
