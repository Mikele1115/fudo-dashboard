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
    ingredient_purchase.rb  Una línea de compra de insumo (tabla ingredient_purchases)
    price_alert.rb       Aviso de que un insumo subió mucho de precio (tabla price_alerts)
    sync_run.rb          Registro de cada sincronización con Fudo
    report_delivery.rb   Registro de cada envío del informe
  services/
    fudo/client.rb       Cliente HTTP de la API de Fudo (token, paginación, reintentos)
    sales_sync.rb        Descarga lo que falta y guarda los totales diarios (upsert)
    purchases_sync.rb    Descarga las compras de insumos (upsert por id de línea de Fudo)
    ingredient_prices.rb Comportamiento de los precios: medianas, ventanas y filtro de datos dudosos
    price_alert_detector.rb  Detecta saltos de precio que cuestan dinero de verdad
    alert_notifier.rb    Agrupa las alertas pendientes en un solo correo
    weekly_purchases_report.rb  Resumen semanal de compras (viernes)
    metrics.rb           Calcula todos los indicadores de un día (una consulta, todo en memoria)
    month_report.rb      Vista mensual del historial
    report_sender.rb     Envía el informe y deja registro
  jobs/
    sync_sales_job.rb    Sincronización en segundo plano (botón "Sincronizar")
    daily_report_job.rb  Tarea programada: sincroniza + envía el informe (hoy en pausa)
    weekly_purchases_report_job.rb  Tarea programada: resumen semanal de compras
  mailers/report_mailer.rb     + app/views/report_mailer/daily.{html,text}.erb
  mailers/purchases_mailer.rb  + app/views/purchases_mailer/{weekly,price_alerts}.{html,text}.erb
  controllers/           dashboard, history, ingredients, price_alerts, syncs, reports (todos delgados)
  views/                 dashboard/show, history/index, ingredients/{index,show}, layouts/application
  helpers/format_helper.rb      money, porcentajes y fechas en español (web y correo)
  helpers/ingredients_helper.rb minigráfico SVG y variación de precios (colores invertidos)
  javascript/controllers/   chart_controller.js (Chart.js), autorefresh_controller.js
config/recurring.yml     Tareas programadas: sincronización nocturna y semanal de compras
lib/tasks/report.rake    Tareas de consola (check, sync, daily, preview, purchases:*)
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

## Insumos: comportamiento de los precios de compra

La pestaña **Insumos** (`/insumos`) muestra cómo se han movido los precios de compra
de cada insumo. Los datos salen de los egresos de Fudo (`/expenses`): cada línea de un
egreso que apunta a un insumo se guarda en `ingredient_purchases`.

Dos cosas comprobadas contra la cuenta real, que conviene no olvidar:

- El campo `price` de una línea es el **total de la línea**, no el precio unitario
  (100 cajas por $52.000 son $520 cada una). El unitario es `price / quantity`.
- Ese total es **neto**: el `amount` del egreso es ~1,19× la suma de sus líneas (IVA).
  Todo lo que se muestra en la pestaña es neto, sin IVA.

### Por qué no se compara el primer precio con el último

En los datos reales hay líneas mal cargadas: cantidades en gramos donde van kilos,
totales en cero, cantidades duplicadas. Un solo dato así arruina la comparación —con
el método ingenuo, la menta "subía" un 120.693% y la canasta un 269%.

`IngredientPrices` lo resuelve así:

1. toma la **mediana** de cada insumo como ancla (los extremos no la mueven),
2. marca como **sospechosa** toda compra que se aleje más de 4× de esa mediana y la
   excluye de los cálculos,
3. compara **medianas de dos ventanas de 90 días** (las primeras compras del período
   contra las últimas), nunca dos compras sueltas.

Con eso la canasta da +1,8%, que es una cifra creíble. Las compras sospechosas no se
borran: aparecen en la sección **Compras a revisar en Fudo** al final de la página,
con la fecha y la cantidad, para poder corregirlas en el POS.

### Indicadores

- **La canasta**: variación media ponderada por gasto. Un insumo de $18M pesa más que
  uno de $5.000.
- **Costó de más / Ahorro**: la variación de precio multiplicada por el volumen
  comprado, en pesos. Es lo que de verdad llegó al bolsillo.
- **Los que más encarecieron la cuenta**: ordenados por ese impacto, no por porcentaje.
  Un insumo barato que sube 100% puede dar igual; uno caro que sube 5% puede costar
  millones.
- La etiqueta **pocos datos** avisa cuando la variación se calcula con menos de tres
  compras en algún extremo.

Ojo con el color: aquí un precio que **sube se pinta en rojo** (malo) y uno que baja en
verde, al revés que en las ventas.

### Sincronización

El botón **Actualizar compras** descarga lo nuevo. La primera vez trae
`PurchasesSync::DEFAULT_YEARS` años (puede tardar un par de minutos); después solo los
últimos `REFRESH_DAYS` días. La tarea nocturna de las 00:00 también las actualiza.

En consola:

```bash
bin/rails runner 'PurchasesSync.run!(from: Date.new(2024,1,1))'  # histórico
bin/rails runner 'PurchasesSync.catch_up!'                       # incremental
```

### Alertas de precio

Cuando un insumo se compra bastante más caro de lo habitual, el sistema deja un aviso
en la pestaña Insumos y manda un correo. Los umbrales están en `PriceAlertDetector`:

| Constante | Valor | Qué hace |
|---|---|---|
| `CHANGE_PCT` | 15% | subida mínima respecto a la mediana reciente |
| `MIN_OVERCOST` | $20.000 | lo que esa compra costó de más |
| `MIN_SPEND` | $500.000 | gasto anual del insumo: por debajo, no avisa |
| `COOLDOWN_DAYS` | 14 | no repite aviso del mismo insumo dentro de ese plazo |

No son números inventados: se midieron contra 12 meses de compras reales (1.546
comparaciones). Avisar solo por porcentaje daba 137 avisos al año con +15% —más de uno
cada tres días—. Con los filtros de dinero quedan unos 30, todos con un motivo económico.
El hallazgo que importa: **con esos filtros puestos, mover el umbral de +10% a +30% solo
quita 4 avisos al año**. El que hace el trabajo es el filtro de plata, no el porcentaje.

Dos detalles que evitan falsos positivos:

- Se compara contra la **mediana reciente** del insumo, no contra la compra anterior.
  Hay precios que oscilan entre dos valores (dos formatos, dos proveedores): comparando
  con la anterior, la Salsiccia saltaba "+150%" una y otra vez sin estar subiendo.
- Las líneas mal cargadas se ignoran, igual que en el resto del análisis.

Fudo no tiene webhooks: su API es solo de lectura por consulta. Los saltos se detectan
en la sincronización nocturna, así que el aviso llega **a la mañana siguiente**.

El botón **Vista** de cada alerta la archiva para que deje de aparecer arriba; queda en
el historial del insumo.

### Resumen semanal de compras

Los **lunes a las 12:00** sale un correo con la **semana anterior completa, de lunes a
domingo**: gasto contra la semana de antes, en qué se fue la plata, qué subió y bajó de
precio, insumos comprados por primera vez, las alertas de esa semana y las líneas mal
cargadas para corregirlas.

Ojo con la ventana: el informe nunca incluye el día en que se envía. Si cubriera "desde
el lunes hasta hoy", al salir el lunes a mediodía llegaría casi vacío.

Igual que en el resto: el **gasto** suma todas las líneas (es la plata que salió), pero
los **precios que se comparan** solo salen de las líneas limpias. Sin eso, un total en
cero aparecía como "bajó -100%".

En consola:

```bash
bin/rails purchases:sync                    # sincroniza compras (incremental)
bin/rails "purchases:sync[2024-01-01]"      # histórico desde una fecha
bin/rails purchases:alerts                  # busca saltos de precio
bin/rails "purchases:preview[2026-10-23]"   # genera el semanal en tmp/ sin enviarlo
bin/rails purchases:weekly                  # envía el semanal
```

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
