# frozen_string_literal: true

require "test_helper"

class ProductPricesTest < ActiveSupport::TestCase
  HOY = Date.new(2026, 11, 4)

  def producto(id, nombre, precio, activo: true)
    base, canal = Product.partir_nombre(nombre)
    Product.create!(fudo_product_id: id, name: nombre, base_name: base, channel: canal,
                    price: precio, active: activo)
  end

  def vender(id, nombre, precio, on:, cantidad: 1, veces: 1)
    veces.times do
      @seq = (@seq || 0) + 1
      SaleItem.create!(fudo_item_id: @seq, fudo_sale_id: @seq, fudo_product_id: id,
                       product_name: nombre, sold_on: on, closed_at: on.to_time,
                       quantity: cantidad, line_total: precio * cantidad, unit_price: precio)
    end
  end

  # La Margherita: mismo plato, tres productos en Fudo, tres precios.
  def cargar_margherita
    producto(1, "Margherita 32 cm PLATO", 11_400)
    producto(2, "Margherita 32 cm DELIVERY", 11_400)
    producto(3, "Margherita 32 cm APLICACION", 11_600, activo: false) # inactiva pero vende
    5.times { |i| vender(1, "Margherita 32 cm PLATO", 11_400, on: HOY - (i * 10), veces: 2) }
    5.times { |i| vender(2, "Margherita 32 cm DELIVERY", 11_400, on: HOY - (i * 10)) }
    5.times { |i| vender(3, "Margherita 32 cm APLICACION", 14_250, on: HOY - (i * 10), veces: 3) }
  end

  test "el mismo plato sale una vez, con sus canales al lado" do
    cargar_margherita

    g = ProductPrices.new(period: "3", to: HOY).con_ventas.find { |x| x.name == "Margherita 32 cm" }

    assert_not_nil g
    assert_equal %w[APLICACION DELIVERY PLATO], g.canales.map(&:label).sort
    assert g.multicanal?
    assert_equal 30, g.unidades
  end

  test "un inactivo que ya no vende sale del informe, y se puede volver a ver" do
    producto(1, "Vigente PLATO", 10_000)
    6.times { |i| vender(1, "Vigente PLATO", 10_000, on: HOY - i) }
    producto(2, "Descatalogado PLATO", 9_000, activo: false)
    6.times { |i| vender(2, "Descatalogado PLATO", 9_000, on: HOY - 200 + i) }

    sin = ProductPrices.new(period: "12", to: HOY)
    assert_equal ["Vigente"], sin.con_ventas.map(&:name)
    assert_equal ["Descatalogado PLATO"], sin.descatalogados.map(&:name)

    con = ProductPrices.new(period: "12", to: HOY, descatalogados: true)
    assert_includes con.con_ventas.map(&:name), "Descatalogado"
  end

  test "un inactivo que SÍ vende se queda, pase lo que pase" do
    producto(1, "Margherita 32 cm APLICACION", 11_600, activo: false)
    8.times { |i| vender(1, "Margherita 32 cm APLICACION", 14_250, on: HOY - i) }

    a = ProductPrices.new(period: "12", to: HOY)

    assert_equal ["Margherita 32 cm"], a.con_ventas.map(&:name),
                 "es el más vendido: sacarlo por estar inactivo en Fudo sería el peor error"
    assert_empty a.descatalogados
  end

  test "un producto inactivo que sigue vendiendo no desaparece del informe" do
    cargar_margherita

    g = ProductPrices.new(period: "3", to: HOY).con_ventas.find { |x| x.name == "Margherita 32 cm" }
    app = g.canales.find { |c| c.label == "APLICACION" }

    assert_not_nil app, "era el más vendido y el filtro por «activo» lo tiraba"
    assert_equal 15, app.unidades
  end

  test "distingue el precio de carta del que de verdad se cobra" do
    cargar_margherita

    g = ProductPrices.new(period: "3", to: HOY).con_ventas.find { |x| x.name == "Margherita 32 cm" }
    app   = g.canales.find { |c| c.label == "APLICACION" }
    plato = g.canales.find { |c| c.label == "PLATO" }

    assert_equal 11_600, app.carta
    assert_equal 14_250, app.cobrado
    assert_in_delta 22.8, app.desvio_pct, 0.1, "la aplicación cobra por encima de su carta"
    assert_in_delta 0.0, plato.desvio_pct, 0.01, "el salón cobra exactamente su carta"
    assert_not g.cuadra?
  end

  test "una subida a mitad de período no se confunde con una carta desactualizada" do
    # La Coca Cola pasó de $2.500 a $2.900 y la carta dice $2.900: está AL DÍA. Comparar
    # la carta contra la mediana de los 12 meses la daba por descuadrada en -14%.
    producto(1, "Coca cola Zero", 2_900)
    6.times { |i| vender(1, "Coca cola Zero", 2_500, on: HOY - 170 + i) }
    4.times { |i| vender(1, "Coca cola Zero", 2_900, on: HOY - i) }

    g = ProductPrices.new(period: "6", to: HOY).con_ventas.find { |x| x.name == "Coca cola Zero" }
    c = g.canales.first

    assert_equal 2_500, c.cobrado, "la mediana del período sí recoge el precio viejo"
    assert_equal 2_900, c.ahora
    assert_in_delta 0.0, c.desvio_pct, 0.01, "contra la carta se compara lo que se cobra ahora"
    assert g.cuadra?, "subir un precio y actualizar la carta no es estar descuadrado"
  end

  test "el desvío contra la carta mira los últimos 30 días, no el período elegido" do
    # Un plato que se vendía mal cargado hace meses y hoy ya no se vende no puede
    # seguir en la lista: la pregunta «¿está mi carta al día?» es sobre hoy.
    producto(1, "Viejo PLATO", 10_000)
    8.times { |i| vender(1, "Viejo PLATO", 13_000, on: HOY - 200 + i) } # descuadrado, pero viejo
    producto(2, "Vivo PLATO", 10_000)
    8.times { |i| vender(2, "Vivo PLATO", 13_000, on: HOY - i) }        # descuadrado y vivo

    descuadrados = ProductPrices.new(period: "12", to: HOY).descuadrados.map(&:name)

    # Los grupos van por el nombre sin el canal.
    assert_includes descuadrados, "Vivo"
    assert_not_includes descuadrados, "Viejo", "no se vende hace medio año"
  end

  test "la ventana de la carta no cambia aunque cambies el período" do
    producto(1, "Margherita PLATO", 10_000)
    8.times { |i| vender(1, "Margherita PLATO", 12_000, on: HOY - i) }

    %w[1 3 12].each do |periodo|
      c = ProductPrices.new(period: periodo, to: HOY).con_ventas.first.canales.first
      assert_in_delta 20.0, c.desvio_pct, 0.01, "con período #{periodo} el desvío debería ser el mismo"
    end
  end

  test "la variación compara los dos extremos del período, no compras sueltas" do
    producto(1, "Coca cola Original", 2_900)
    4.times { |i| vender(1, "Coca cola Original", 2_500, on: HOY - 170 + i) }
    4.times { |i| vender(1, "Coca cola Original", 2_900, on: HOY - 3 + i) }

    c = ProductPrices.new(period: "6", to: HOY).con_ventas
                     .find { |g| g.name == "Coca cola Original" }.canales.first

    assert_equal 2_500, c.antes
    assert_equal 2_900, c.ahora
    assert_in_delta 16.0, c.change_pct, 0.1
    assert_equal "alza", c.trend
  end

  test "con pocas ventas en un extremo no se inventa una variación" do
    producto(1, "Trufa", 20_000)
    vender(1, "Trufa", 18_000, on: HOY - 170)           # 1 sola venta al principio
    4.times { |i| vender(1, "Trufa", 20_000, on: HOY - i) }

    c = ProductPrices.new(period: "6", to: HOY).con_ventas
                     .find { |g| g.name == "Trufa" }.canales.first

    assert_not c.comparable?, "1 venta en un extremo no sostiene un porcentaje"
    assert_equal "sin comparación", c.trend
    assert_nil c.impacto
  end

  test "el impacto en pesos nunca contradice a la variación" do
    producto(1, "Sube PLATO", 1_000)
    producto(2, "Baja PLATO", 1_000)
    4.times { |i| vender(1, "Sube PLATO", 1_000, on: HOY - 170 + i) }
    4.times { |i| vender(1, "Sube PLATO", 1_200, on: HOY - i) }
    4.times { |i| vender(2, "Baja PLATO", 1_000, on: HOY - 170 + i) }
    4.times { |i| vender(2, "Baja PLATO", 800, on: HOY - i) }

    a = ProductPrices.new(period: "6", to: HOY)
    a.con_ventas.each do |g|
      next if g.change_pct.nil? || g.impacto.zero?

      assert_equal g.change_pct.positive?, g.impacto.positive?,
                   "#{g.name}: variación #{g.change_pct.round(1)}% con impacto #{g.impacto.round}"
    end
  end

  test "un precio que termina donde empezó no inventa movimiento" do
    producto(1, "Estable PLATO", 5_000)
    4.times { |i| vender(1, "Estable PLATO", 5_000, on: HOY - 170 + i) }
    4.times { |i| vender(1, "Estable PLATO", 5_000, on: HOY - i) }

    c = ProductPrices.new(period: "6", to: HOY).con_ventas.first.canales.first

    assert_in_delta 0.0, c.change_pct, 0.001
    assert_equal 0.0, c.impacto
    assert_equal "estable", c.trend
  end

  test "la variación del menú pondera por lo que factura cada plato" do
    producto(1, "Mucho PLATO", 10_000)
    producto(2, "Poco PLATO", 1_000)
    20.times { |i| vender(1, "Mucho PLATO", 10_000, on: HOY - 170 + (i % 5)) }
    20.times { |i| vender(1, "Mucho PLATO", 10_100, on: HOY - (i % 5)) }   # +1%
    4.times  { |i| vender(2, "Poco PLATO", 1_000, on: HOY - 170 + i) }
    4.times  { |i| vender(2, "Poco PLATO", 2_000, on: HOY - i) }           # +100%

    menu = ProductPrices.new(period: "6", to: HOY).menu_change_pct

    assert_operator menu, :<, 10, "el plato de $1.000 no puede arrastrar el menú entero"
    assert_operator menu, :>, 0
  end

  test "un período corto se compara contra el período anterior" do
    producto(1, "Coca cola Original", 2_900)
    4.times { |i| vender(1, "Coca cola Original", 2_500, on: HOY - 45 + i) } # mes anterior
    4.times { |i| vender(1, "Coca cola Original", 2_900, on: HOY - i) }      # mes elegido

    a = ProductPrices.new(period: "1", to: HOY)
    assert_equal :previous, a.compare_mode

    c = a.con_ventas.find { |g| g.name == "Coca cola Original" }.canales.first
    assert_equal 2_500, c.antes, "el antes sale del mes anterior"
    assert_equal 2_900, c.ahora
    assert_in_delta 16.0, c.change_pct, 0.1
  end

  test "las líneas a precio cero no entran: son promociones y combos" do
    producto(1, "Margherita PLATO", 11_400)
    4.times { |i| vender(1, "Margherita PLATO", 11_400, on: HOY - i) }
    2.times { |i| vender(1, "Margherita PLATO", 0, on: HOY - i) }

    c = ProductPrices.new(period: "3", to: HOY).con_ventas.first.canales.first

    assert_equal 4, c.unidades
    assert_equal 11_400, c.cobrado, "una línea a 0 hundiría la mediana"
  end
end
