# frozen_string_literal: true

# Iconos de línea en SVG, escritos a mano y en línea.
#
# Sin librería ni fuente de iconos a propósito: son doce dibujos de cuatro líneas, y una
# dependencia externa por esto costaría una petición más en cada carga y un candidato a
# romperse el día que el CDN falle. Heredan el color del texto (`currentColor`), así que
# se pintan desde el CSS como cualquier otra cosa.
module IconsHelper
  PATHS = {
    # Navegación
    home:     '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/>',
    history:  '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/>',
    box:      '<path d="M3 7.5 12 3l9 4.5v9L12 21l-9-4.5z"/><path d="M3 7.5 12 12l9-4.5M12 12v9"/>',
    # Indicadores
    money:    '<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/>',
    receipt:  '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9.5 8h5M9.5 12h5"/>',
    users:    '<circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5"/><path d="M16 5.2a3.2 3.2 0 0 1 0 5.6M17.5 14.8c2.1.6 3.5 2.3 3.5 4.4"/>',
    person:   '<circle cx="12" cy="8" r="3.5"/><path d="M5 20c0-3.6 3.1-6 7-6s7 2.4 7 6"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
    chart:    '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
    basket:   '<path d="M4 9h16l-1.5 11H5.5z"/><path d="M8.5 9 12 3l3.5 6"/>',
    up:       '<path d="M3 17 9 11l4 4 8-8"/><path d="M15 7h6v6"/>',
    alert:    '<path d="M12 3 2.5 20h19z"/><path d="M12 10v4M12 17h.01"/>',
    search:   '<circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/>',
    refresh:  '<path d="M20 11A8 8 0 0 0 6.3 6.3L4 8.5"/><path d="M4 4v4.5h4.5"/><path d="M4 13a8 8 0 0 0 13.7 4.7L20 15.5"/><path d="M20 20v-4.5h-4.5"/>'
  }.freeze

  def icon(nombre, size: 20, extra_class: nil)
    cuerpo = PATHS[nombre.to_sym] or raise ArgumentError, "no existe el icono #{nombre}"

    tag.svg(cuerpo.html_safe, width: size, height: size, viewBox: "0 0 24 24",
            fill: "none", stroke: "currentColor", "stroke-width": 1.8,
            "stroke-linecap": "round", "stroke-linejoin": "round",
            class: ["icon", extra_class].compact.join(" "), aria: { hidden: true })
  end

  # Pastilla de color con el icono dentro, la que acompaña a cada indicador.
  # `tono` elige el color: blue, green, amber, violet, rose, slate.
  def kpi_icon(nombre, tono: "blue")
    tag.span(icon(nombre), class: "kpi__icon kpi__icon--#{tono}")
  end
end
