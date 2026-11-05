# frozen_string_literal: true

# Tareas de consola. Ejemplos:
#   bin/rails fudo:check                   # prueba la conexión con Fudo y la configuración
#   bin/rails sales:sync                   # sincroniza ventas (histórico + últimos días)
#   bin/rails report:daily                 # sincroniza y envía el informe de ayer (lo usa la tarea programada)
#   bin/rails "report:daily[2026-09-10]"   # informe de un día concreto
#   bin/rails "report:preview[2026-09-10]" # guarda tmp/informe_2026-09-10.html sin enviar

namespace :fudo do
  desc "Prueba la conexión con Fudo y la configuración de correo"
  task check: :environment do
    puts "Zona horaria: #{AppSettings.timezone_name} (día de negocio actual: #{AppSettings.today})"
    abort "Falta configurar: #{AppSettings.fudo_missing.join(', ')}" unless AppSettings.fudo_configured?
    Fudo::Client.new.ping
    puts "Conexión con Fudo OK"
    if AppSettings.mail_configured?
      puts "Correo configurado: #{AppSettings.mail_from} -> #{AppSettings.mail_to.join(', ')}"
    else
      puts "Correo incompleto, faltan: #{AppSettings.mail_missing.join(', ')}"
    end
    puts "Días sincronizados: #{DailySale.count}"
  end
end

namespace :sales do
  desc "Sincroniza las ventas con Fudo"
  task :sync, [:date] => :environment do |_, args|
    date = args[:date] ? Date.parse(args[:date]) : AppSettings.report_day
    run  = SalesSync.run!(date)
    puts run.message
  end
end

namespace :report do
  desc "Sincroniza y envía por correo el informe del último día completo (o de la fecha dada)"
  task :daily, [:date] => :environment do |_, args|
    date = args[:date] ? Date.parse(args[:date]) : AppSettings.report_day
    SalesSync.run!(date)
    delivery = ReportSender.call(date)
    puts "Informe del #{date} enviado a #{delivery.recipients}"
  end

  desc "Genera el HTML del informe en tmp/ sin enviarlo"
  task :preview, [:date] => :environment do |_, args|
    date = args[:date] ? Date.parse(args[:date]) : AppSettings.report_day
    mail = ReportMailer.daily(date)
    path = Rails.root.join("tmp", "informe_#{date}.html")
    File.write(path, mail.html_part.body.decoded)
    puts mail.text_part.body.decoded
    puts "\nHTML guardado en #{path}"
  end
end

namespace :purchases do
  desc "Sincroniza las compras de insumos con Fudo"
  task :sync, [:from] => :environment do |_, args|
    run = args[:from] ? PurchasesSync.run!(from: Date.parse(args[:from])) : PurchasesSync.catch_up!
    puts run.message
  end

  desc "Busca saltos de precio en las compras recientes y crea las alertas"
  task :alerts, [:since] => :environment do |_, args|
    since = args[:since] ? Date.parse(args[:since]) : nil
    nuevas = PriceAlertDetector.run!(since: since)
    puts "#{nuevas.size} alertas nuevas"
    nuevas.each { |a| puts "  #{a.purchased_on} #{a.ingredient_name}: #{a.change_pct.round(1)}% (#{a.overcost.round} de mas)" }
  end

  desc "Genera el resumen semanal en tmp/ sin enviarlo"
  task :preview, [:date] => :environment do |_, args|
    date = args[:date] ? Date.parse(args[:date]) : AppSettings.today
    mail = PurchasesMailer.weekly(date)
    path = Rails.root.join("tmp", "compras_semana_#{date}.html")
    File.write(path, mail.html_part.body.decoded)
    puts mail.text_part.body.decoded
    puts "\nHTML guardado en #{path}"
  end

  desc "Envia el resumen semanal de compras"
  task :weekly, [:date] => :environment do |_, args|
    WeeklyPurchasesReportJob.perform_now(args[:date])
    puts "Listo"
  end
end
