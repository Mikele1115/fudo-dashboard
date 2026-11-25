# frozen_string_literal: true

# Cómo se parte un período para decir si un precio subió o bajó.
#
# Vive aparte porque lo usan los dos análisis —insumos que compras y productos que
# vendes— y la regla tiene esquinas que costaron calibrarse. Dos copias se habrían
# separado en el primer ajuste.
#
# La idea: no se compara la primera compra con la última, que sería un número a merced
# de dos datos sueltos. Se comparan dos BLOQUES y se usa la mediana de cada uno.
#
#   :split    el período da para dos bloques sin pisarse. Se comparan los primeros
#             window_days contra los últimos window_days, contados desde la primera y
#             la última venta/compra de cada ítem, no desde los bordes del calendario.
#   :previous el período es corto (menos de SPLIT_MIN_DAYS). Partirlo en dos no se
#             puede: un tercio quedaría por debajo del suelo, el suelo lo levantaría y
#             los dos bloques se solaparían, con lo que una misma compra sería a la vez
#             el "antes" y el "después". Se compara el período entero contra el período
#             anterior del mismo largo.
class ComparisonWindow
  MAX_WINDOW_DAYS = 90
  MIN_WINDOW_DAYS = 21
  SPLIT_MIN_DAYS  = MIN_WINDOW_DAYS * 3

  attr_reader :from, :to

  def initialize(from, to)
    @from = from
    @to   = to
  end

  def days = (@to - @from).to_i + 1

  def mode   = days >= SPLIT_MIN_DAYS ? :split : :previous
  def split? = mode == :split

  # Un tercio del período, entre 21 y 90 días. Solo se usa en modo :split.
  def window_days
    @window_days ||= ((@to - @from).to_i / 3.0).floor.clamp(MIN_WINDOW_DAYS, MAX_WINDOW_DAYS)
  end

  # Primer día del período anterior, el que hace de referencia en modo :previous.
  def previous_from = @from - days

  # Cómo se calculan las variaciones, para decirlo en pantalla.
  #
  # Ojo con la redacción del caso :split. Decía "primeros N días contra los últimos N",
  # que suena a que se cuentan desde el primer día del período, y no es así: se cuentan
  # desde la primera venta de CADA ítem.
  def note
    if split?
      "variaciones: #{window_days} días al principio contra #{window_days} al final"
    else
      "variaciones: contra los #{days} días anteriores " \
        "(#{previous_from.strftime('%d/%m/%Y')} → #{(@from - 1).strftime('%d/%m/%Y')})"
    end
  end

  # Mediana: el valor del medio. No el promedio, para que un dato suelto no la mueva.
  def self.median(values)
    return nil if values.empty?

    s = values.map(&:to_f).sort
    s.size.odd? ? s[s.size / 2] : (s[(s.size / 2) - 1] + s[s.size / 2]) / 2.0
  end
end
