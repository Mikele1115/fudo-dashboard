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
