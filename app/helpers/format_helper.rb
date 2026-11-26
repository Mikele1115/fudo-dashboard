# frozen_string_literal: true

# Formato de dinero, porcentajes y fechas en español. Se usa en las vistas web y en el correo.
module FormatHelper
  DAYS   = %w[Domingo Lunes Martes Miércoles Jueves Viernes Sábado].freeze
  MONTHS = %w[enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre].freeze

  # 1234567.8 -> "$1.234.568" (con DECIMALS=0) o "$1.234.567,80" (con DECIMALS=2)
  def money(n)
    return "—" if n.nil?

    decimals = AppSettings.decimals
    rounded  = n.round(decimals)
    int_part, dec_part = format("%.#{decimals}f", rounded.abs).split(".")
    int_part = int_part.reverse.scan(/\d{1,3}/).join(".").reverse
    sign = rounded.negative? ? "-" : ""
    "#{sign}#{AppSettings.currency_symbol}#{int_part}#{dec_part ? ",#{dec_part}" : ''}"
  end

  # 12345 -> "12.345"
  def int(n)
    return "—" if n.nil?

    n.round.to_s.reverse.scan(/\d{1,3}/).join(".").reverse
  end

  # Variación porcentual de current respecto a base. nil si no se puede calcular.
  def pct_value(current, base)
    return nil if current.nil? || base.nil? || base.zero?

    (current - base).to_f / base * 100.0
  end

  # "+12,3%" / "-4,0%" / "—"
  def pct_text(current, base)
    v = pct_value(current, base)
    return "—" if v.nil?

    format("%+.1f%%", v).tr(".", ",")
  end

  # Para la web: <span class="pct pct--up">+12,3%</span>
  def pct_badge(current, base)
    v = pct_value(current, base)
    return %(<span class="pct pct--na">—</span>).html_safe if v.nil?

    klass = v >= 0 ? "pct--up" : "pct--down"
    %(<span class="pct #{klass}">#{pct_text(current, base)}</span>).html_safe
  end

# Un porcentaje que ya ES un porcentaje, sin comparar nada: "79%", "-1.513%".
def pct_plano(v, decimales: 0)
  return "—" if v.nil?

  format("%.#{decimales}f%%", v).tr(".", ",")
end

# El costo de un canal, o el aviso de que Fudo no tiene ninguno cargado. Sin costo no
# se pone 0: un 0 diría 100% de margen, que es justo la conclusión equivocada.
def costo_celda(canal)
  return tag.span("sin costo", class: "tag tag--na",
                  title: "Fudo no tiene costo cargado para este producto. Se carga en el producto o en su receta.") if canal.sin_costo?

  safe_join([money(canal.costo), tag.span("sin IVA", class: "muted small")], " ")
end

# El margen sobre el precio sin IVA. Rojo cuando sale negativo: ahí el costo está mal
# cargado casi siempre, y el dato se deja como está para que se vea.
def margen_celda(canal)
  return tag.span("—", class: "pct pct--na") if canal.margen_pct.nil?

  klass = canal.margen_negativo? ? "pct pct--down" : "pct pct--up"
  titulo = "#{money(canal.precio_neto)} sin IVA − #{money(canal.costo)} de costo = #{money(canal.margen_pesos)}"
  tag.span(pct_plano(canal.margen_pct), class: klass, title: titulo)
end

# Para el correo (los clientes de correo no cargan CSS externo): estilos en línea.
  def pct_inline(current, base)
    v = pct_value(current, base)
    return %(<span style="color:#9ca3af;">—</span>).html_safe if v.nil?

    color = v >= 0 ? "#047857" : "#b91c1c"
    %(<span style="color:#{color};font-weight:600;">#{pct_text(current, base)}</span>).html_safe
  end

  # "Sábado 13 de septiembre de 2026"
  def long_date(date)
    "#{DAYS[date.wday]} #{date.day} de #{MONTHS[date.month - 1]} de #{date.year}"
  end

  # "Sáb 13/09"
  def short_date(date)
    "#{DAYS[date.wday][0, 3]} #{date.strftime('%d/%m')}"
  end

  def weekday_name(date) = DAYS[date.wday]

  # "lunes" -> "lunes", "domingo" -> "domingos"
  def plural_weekday(date)
    name = DAYS[date.wday].downcase
    name.end_with?("s") ? name : "#{name}s"
  end

  def month_name(month) = MONTHS[month - 1]

  # "hace un momento", "hace 3 min", "hace 2 h", "hace 1 d"
  def ago_in_words(time)
    secs = (Time.current - time).to_i
    return "hace un momento" if secs < 60

    mins = secs / 60
    return "hace #{mins} min" if mins < 60

    hours = mins / 60
    return "hace #{hours} h" if hours < 24

    "hace #{hours / 24} d"
  end

  def compare_note
    if AppSettings.compare_mode == "weekday"
      "Se compara con el mismo día de la semana del año pasado."
    else
      "Se compara con la misma fecha del año pasado."
    end
  end

  # Aviso de que las dos ventanas que se comparan no tienen los mismos días de la semana.
  # nil cuando cuadran o cuando el desajuste es demasiado chico para cambiar la lectura.
  #   "Un sábado menos y un martes más que el año anterior: el calendario le resta unos
  #    $1.050.000 a este período, así que la variación se queda corta."
  def weekday_gap_note(period)
    gap = period.weekday_gap
    return nil unless gap&.material?

    verbo   = gap.favourable? ? "suma" : "resta"
    lectura = gap.favourable? ? "la variación se ve mejor de lo que fue" : "la variación se queda corta"
    "#{gap.text.capitalize} que el año anterior: el calendario le #{verbo} unos " \
      "#{money(gap.effect.abs)} a este período, así que #{lectura}."
  end

  # Versión corta para la tarjeta del KPI, donde no hay ancho: "un sábado menos y un martes más".
  def weekday_gap_short(period)
    gap = period.weekday_gap
    gap&.material? ? "#{gap.text} que el año anterior" : nil
  end

  # Aviso de que el día con el que se compara no fue un día corriente, así que el
  # porcentaje de al lado se lee distinto. nil cuando fue normal.
  #
  #   "El 03/11/2025 fue un lunes excepcional: +76% sobre la mediana de los lunes de 2025,
  #    así que la comparación es más exigente de lo normal."
  def outlier_note(outlier)
    return nil if outlier.nil?

    calificativo = outlier.high? ? "excepcional" : "muy flojo"
    lectura      = outlier.high? ? "más exigente" : "más fácil"
    "El #{outlier.date.strftime('%d/%m/%Y')} fue un #{outlier.weekday} #{calificativo}: " \
      "#{format('%+.0f%%', outlier.pct)} sobre la mediana de los #{outlier.weekday_plural} " \
      "de #{outlier.date.year}, así que la comparación es #{lectura} de lo normal."
  end

  # Marca corta para las tablas, con el detalle en el título.
  def outlier_flag(outlier)
    return "" if outlier.nil?

    tag.span("⚠", class: "warn", title: outlier_note(outlier),
             aria: { label: "El día de referencia no fue un día corriente" })
  end

  # Enlace a la pantalla de Fudo donde se corrige un producto o un insumo.
  #
  #   fudo_edit_url(:product, 558)    -> .../app/#!/products/558/edit
  #   fudo_edit_url(:ingredient, 82)  -> .../app/#!/ingredients/82/edit
  #
  # El id es SIEMPRE el de Fudo (fudo_product_id, fudo_ingredient_id), no el nuestro.
  FUDO_RECURSOS = { product: "products", ingredient: "ingredients" }.freeze

  def fudo_edit_url(tipo, fudo_id)
    recurso = FUDO_RECURSOS.fetch(tipo.to_sym)
    "#{AppSettings.fudo_app_url}/#{recurso}/#{fudo_id}/edit"
  end

  # Icono enlazado, para ponerlo junto al nombre en las tablas sin robar ancho.
  # Abre en otra pestaña: corriges en Fudo y vuelves al panel donde lo dejaste.
  def fudo_edit_link(tipo, fudo_id, titulo: nil)
    return "" if fudo_id.blank?

    link_to fudo_edit_url(tipo, fudo_id), class: "fudo-link", target: "_blank",
            rel: "noopener", title: titulo || "Corregir en Fudo" do
      tag.span("↗", aria: { hidden: true }) + tag.span("Fudo", class: "sr-only")
    end
  end

  def cutoff_note
    cutoff = AppSettings.cutoff_hour
    return "" if cutoff.zero?

    "El día de negocio va de las #{format('%02d:00', cutoff)} a las #{format('%02d:00', cutoff)} del día siguiente."
  end

  # Asunto del correo: "Ventas Sábado 13 de septiembre de 2026 — $1.234.567 (87 tickets)"
  def report_subject(m)
    "Ventas #{long_date(m.report_date)} — #{money(m.day&.total)} (#{int(m.day&.tickets)} tickets)"
  end
end
