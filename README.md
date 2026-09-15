# Dashboard de ventas — Fudo

Aplicación Ruby on Rails que descarga las ventas cerradas desde la API de Fudo, las muestra
en un dashboard con todos los indicadores, y envía un informe por correo todos los días a las 00:00.

## Indicadores

**Dashboard (`/`)** — para cualquier día (por defecto, ayer):

- Venta bruta y venta neta (sin IVA, `VAT_RATE`), tickets, ticket promedio, comensales, ticket por persona
  (venta de salón ÷ comensales) y propinas, todo con variación contra el año anterior.
- Comparativa de todos los años del histórico (`HISTORY_FROM`): tabla año a año, mismo período de cada
  año (1 ene → misma fecha) y gráfico de ventas por mes con una línea por año.
- Comparación con el año anterior: mismo día de la semana (`COMPARE_MODE=weekday`, D − 364 días)
  o misma fecha (`COMPARE_MODE=date`).
- Acumulados: semana en curso, mes en curso y año en curso contra el mismo período del año anterior.
- Venta promedio diaria: año en curso, año anterior mismo período, año anterior completo, y
  cuánto se desvía el día de cada promedio.
- Mismo día de la semana: promedio de todos los lunes (o el día que corresponda) del año en curso
  y del anterior, y cómo se compara el día.
- Gráficos: últimos 30 días vs. día comparable del año anterior, ventas por mes (año vs. año
  anterior) y venta promedio por día de la semana.
- Tabla de los últimos 14 días.

**Historial (`/historial`)** — un mes completo día a día con su comparable del año anterior y
los totales del mes.

**Informe diario por correo** — los mismos indicadores (sin gráficos) en HTML y texto plano.
Se puede ver la vista previa (`/informe/AAAA-MM-DD`) y enviarlo a mano desde el dashboard.

Los promedios cuentan solo los días con al menos una venta cerrada (los días cerrados no bajan el promedio).

## Estructura del código

```
app/
  models/
    app_settings.rb      Lee la configuración del .env (zona horaria, modo de comparación, correo…)
    daily_sale.rb        Total y tickets de cada día de negocio (tabla daily_sales)
    sync_run.rb          Registro de cada sincronización con Fudo
    report_delivery.rb   Registro de cada envío del informe
  services/
    fudo/client.rb       Cliente HTTP de la API de Fudo (token, paginación, reintentos)
    sales_sync.rb        Descarga lo que falta y guarda los totales diarios (upsert)
    metrics.rb           Calcula todos los indicadores de un día (una consulta, todo en memoria)
    month_report.rb      Vista mensual del historial
    report_sender.rb     Envía el informe y deja registro
  jobs/
    sync_sales_job.rb    Sincronización en segundo plano (botón "Sincronizar")
    daily_report_job.rb  Tarea programada: sincroniza + envía el informe
  mailers/report_mailer.rb  + app/views/report_mailer/daily.{html,text}.erb
  controllers/           dashboard, history, syncs, reports (todos delgados)
  views/                 dashboard/show, history/index, layouts/application
  helpers/format_helper.rb  money, porcentajes y fechas en español (web y correo)
  javascript/controllers/   chart_controller.js (Chart.js), autorefresh_controller.js
config/recurring.yml     Programación del informe (Solid Queue, modo producción)
lib/tasks/report.rake    Tareas de consola (check, sync, daily, preview)
install_task.ps1         Tarea programada de Windows (ejecuta report:daily vía WSL)
```

## Instalación (Ruby en WSL / Ubuntu)

Ruby 3.4 (rbenv) y Rails 8.1 están instalados en WSL. El proyecto vive en `~/fudo-dashboard`.

1. Entrar a la carpeta e instalar dependencias:
   ```bash
   cd ~/fudo-dashboard
   bundle install
   ```

2. Crear la configuración:
   ```bash
   cp .env.example .env
   nano .env
   ```
   Completa `FUDO_API_KEY`, `FUDO_API_SECRET`, la zona horaria y los datos de correo.
   Para Gmail hace falta una **contraseña de aplicación** (no la contraseña normal):
   https://myaccount.google.com/apppasswords

3. Crear la base de datos:
   ```bash
   bin/rails db:prepare
   ```

4. Probar la conexión:
   ```bash
   bin/rails fudo:check
   ```

5. Arrancar el dashboard:
   ```bash
   bin/rails server
   ```
   Abre http://localhost:3000 y pulsa **Sincronizar**. La primera vez descarga el histórico
   desde el 1 de enero del año anterior (unos minutos). Las siguientes solo descargan los
   últimos `REFRESH_DAYS` días.

## Informe diario a las 00:00

Hay dos formas; usa una sola.

**A) Tarea programada de Windows (recomendada si la app corre en tu PC)** — en PowerShell,
desde la copia de esta carpeta en Windows:
```powershell
.\install_task.ps1
```
Ejecuta `bin/rails report:daily` en WSL cada día a las 00:00 (sincroniza y envía). No hace
falta que el servidor web esté encendido. Registro en `log/report_task.log`.

**B) Solid Queue (si la app corre como servidor en producción)** — `config/recurring.yml` ya
programa `DailyReportJob` a las 00:00 en la zona horaria del local. Solo se ejecuta si corre
el worker de jobs: `bin/jobs`, o Puma con `SOLID_QUEUE_IN_PUMA=true` en el `.env`.

## Tareas de consola

```bash
bin/rails fudo:check                    # conexión con Fudo + configuración
bin/rails sales:sync                    # sincroniza ventas
bin/rails report:daily                  # sincroniza y envía el informe de ayer
bin/rails "report:daily[2026-09-10]"    # informe de un día concreto
bin/rails "report:preview[2026-09-10]"  # guarda tmp/informe_2026-09-10.html sin enviar
bin/rails test                          # ejecuta los tests
```

## Notas

- El informe de las 00:00 corresponde al día que acaba de terminar. Las ventas que a esa hora
  sigan abiertas no entran; al día siguiente se refrescan los últimos días y el histórico queda corregido.
- Si el local cierra pasada la medianoche y quieres que esas ventas cuenten para el día anterior,
  pon `BUSINESS_DAY_CUTOFF_HOUR=4` (por ejemplo) y programa la tarea a esa hora.
- Para volver a descargar todo el histórico: `bin/rails runner "DailySale.delete_all"` y sincroniza.
- Base de datos: SQLite en `storage/development.sqlite3`.
