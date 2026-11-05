# frozen_string_literal: true

# Ayudas de presentación del informe de insumos.
module IngredientsHelper
  SPARK_W = 90
  SPARK_H = 24

  # Minigráfico de la evolución del precio, dibujado como SVG en línea.
  # Se usa SVG y no Chart.js porque en la tabla hay 150 filas: un canvas por fila
  # sería pesado, y aquí solo hace falta la silueta de la curva.
  def price_sparkline(series)
    return content_tag(:span, "—", class: "muted") if series.size < 2

    values = series.map(&:last)
    min    = values.min
    max    = values.max
    span   = (max - min).zero? ? 1.0 : (max - min)
    step   = SPARK_W.to_f / (values.size - 1)

    points = values.each_with_index.map do |v, i|
      x = (i * step).round(1)
      y = (SPARK_H - 2 - ((v - min) / span * (SPARK_H - 4))).round(1)
      "#{x},#{y}"
    end.join(" ")

    # Ojo con el color: aqui un precio que SUBE es malo, al reves que en las ventas.
    color = values.last >= values.first ? "var(--down)" : "var(--up)"
    tag.svg(width: SPARK_W, height: SPARK_H, viewBox: "0 0 #{SPARK_W} #{SPARK_H}", class: "spark",
            aria: { hidden: true }) do
      tag.polyline(points: points, fill: "none", stroke: color, "stroke-width": 1.5,
                   "stroke-linejoin": "round", "stroke-linecap": "round")
    end
  end

  # Variacion de un PRECIO DE COSTO: los colores van al reves que en las ventas.
  # Que un insumo suba de precio es una mala noticia (rojo); que baje, buena (verde).
  def price_change_badge(current, base)
    v = pct_value(current, base)
    return tag.span("—", class: "pct pct--na") if v.nil?

    klass = v.positive? ? "pct--down" : "pct--up"
    tag.span(pct_text(current, base), class: "pct #{klass}")
  end

  # "al alza" / "a la baja" / "estable" / "sin comparación"
  def trend_badge(row)
    case row.trend
    when "alza"    then tag.span("▲ al alza",    class: "pct pct--down")
    when "baja"    then tag.span("▼ a la baja",  class: "pct pct--up")
    when "estable" then tag.span("= estable",    class: "pct pct--na")
    else                tag.span("· sin comparación", class: "pct pct--na")
    end
  end

  # Cuántas compras respaldan la variación: con 2 o 3 datos hay que mirarla con cuidado.
  def confidence_note(row)
    n = [row.baseline_n, row.recent_n].min
    return "" if n.zero?

    n < 3 ? tag.span("pocos datos", class: "tag tag--warn", title: "La variación se calcula con #{n} compra(s) en cada extremo") : ""
  end

  def unit_price(row_or_value, unit = nil)
    value = row_or_value.respond_to?(:recent_price) ? row_or_value.recent_price : row_or_value
    unit  = row_or_value.unit_label if unit.nil? && row_or_value.respond_to?(:unit_label)
    return "—" if value.nil?

    "#{money(value)} / #{unit}"
  end

  # Datos del gráfico de detalle (Chart.js, igual que en el dashboard).
  def price_chart_config(history)
    clean = history.reject { |p| p.unit_price.to_f.zero? }
    {
      type:   "line",
      labels: clean.map { |p| p.purchased_on.strftime("%d/%m/%y") },
      datasets: [{ label: "Precio unitario", data: clean.map { |p| p.unit_price.to_f.round(2) } }]
    }
  end
end
