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
# --- Costos y margen -------------------------------------------------------------

test "el margen descuenta el IVA del precio antes de restar el costo" do
  # El costo de Fudo es NETO y el precio de venta lleva IVA. Comparados tal cual, una
  # Coca a $519 de costo y $2.900 de venta daría 82% de margen; el de verdad es 79%.
  producto(1, "Coca cola Original", 2_900).update!(cost: 519)
  6.times { |i| vender(1, "Coca cola Original", 2_900, on: HOY - i) }

  c = ProductPrices.new(period: "3", to: HOY).con_ventas.first.canales.first

  assert_in_delta 2_436.97, c.precio_neto, 0.5, "2.900 con IVA son 2.437 netos"
  assert_in_delta 1_917.97, c.margen_pesos, 0.5
  assert_in_delta 78.7, c.margen_pct, 0.1, "no 82,1%: eso sería olvidarse del IVA"
end

test "un plato sin costo cargado queda señalado, no en cero" do
  producto(1, "Margherita 32 cm PLATO", 11_400) # cost nil, como 253 de las 281 filas
  6.times { |i| vender(1, "Margherita 32 cm PLATO", 11_400, on: HOY - i) }

  a = ProductPrices.new(period: "3", to: HOY)
  c = a.con_ventas.first.canales.first

  assert c.sin_costo?
  assert_nil c.costo,        "sin dato es nil, nunca 0: un costo de 0 diría 100% de margen"
  assert_nil c.margen_pct
  assert_nil c.margen_pesos
  assert_equal ["Margherita 32 cm"], a.sin_costo.map(&:name)
  assert_empty a.con_costo
  assert_nil a.margen_pct, "sin ningún costo no hay margen de menú que inventar"
end

test "un costo de 0 en Fudo cuenta como sin costo" do
  producto(1, "Rara PLATO", 5_000).update!(cost: 0)
  6.times { |i| vender(1, "Rara PLATO", 5_000, on: HOY - i) }

  assert ProductPrices.new(period: "3", to: HOY).con_ventas.first.canales.first.sin_costo?
end

test "la cobertura mide qué parte de la facturación tiene costo, no cuántos platos" do
  # Un plato con costo que casi no vende no puede decir que el menú está cubierto.
  producto(1, "Pizza PLATO", 10_000)                    # sin costo, factura mucho
  90.times { |i| vender(1, "Pizza PLATO", 10_000, on: HOY - (i % 20)) }
  producto(2, "Agua PLATO", 2_000).update!(cost: 400)   # con costo, factura poco
  5.times { |i| vender(2, "Agua PLATO", 2_000, on: HOY - i) }

  a = ProductPrices.new(period: "3", to: HOY)

  assert_equal 1, a.sin_costo.size
  assert_equal 1, a.con_costo.size
  assert_in_delta 1.1, a.cobertura_costos_pct, 0.2, "10.000 de 910.000 facturados"
end

test "un costo por encima del precio se señala y no se corrige" do
  # El Pisco Norterra está cargado en Fudo a $99.999 y se vende a $6.200.
  producto(1, "Pisco Norterra 40º", 6_200).update!(cost: 99_999)
  6.times { |i| vender(1, "Pisco Norterra 40º", 6_200, on: HOY - i) }

  a = ProductPrices.new(period: "3", to: HOY)
  c = a.con_ventas.first.canales.first

  assert c.margen_negativo?
  assert_equal 99_999, c.costo, "el dato se deja como está para que salte a la vista"
  assert_operator c.margen_pct, :<, 0
  assert_equal ["Pisco Norterra 40º"], a.costos_sospechosos.map(&:name)
end

test "el margen del plato pondera sus canales y el del menú lo que factura cada plato" do
  # Mismo plato, dos canales con el mismo costo: el que cobra más deja más margen, y
  # el margen del plato tiene que caer entre los dos, no ser el promedio simple.
  producto(1, "Margherita 32 cm PLATO", 11_400).update!(cost: 4_000)
  producto(2, "Margherita 32 cm APLICACION", 14_250).update!(cost: 4_000)
  20.times { |i| vender(1, "Margherita 32 cm PLATO", 11_400, on: HOY - (i % 10)) }
  2.times  { |i| vender(2, "Margherita 32 cm APLICACION", 14_250, on: HOY - i) }

  g = ProductPrices.new(period: "3", to: HOY).con_ventas.first
  plato = g.canales.find { |c| c.label == "PLATO" }
  app   = g.canales.find { |c| c.label == "APLICACION" }

  assert_operator app.margen_pct, :>, plato.margen_pct
  assert_operator g.margen_pct, :>, plato.margen_pct
  assert_operator g.margen_pct, :<, app.margen_pct
  assert_in_delta plato.margen_pct, g.margen_pct, 1.5,
                  "20 unidades contra 2: manda el canal PLATO"
end

test "un canal con costo basta para que el plato no cuente como sin costo" do
  producto(1, "Margherita 32 cm PLATO", 11_400).update!(cost: 4_000)
  producto(2, "Margherita 32 cm APLICACION", 14_250) # sin costo
  6.times { |i| vender(1, "Margherita 32 cm PLATO", 11_400, on: HOY - i) }
  6.times { |i| vender(2, "Margherita 32 cm APLICACION", 14_250, on: HOY - i) }

  g = ProductPrices.new(period: "3", to: HOY).con_ventas.first

  assert_not g.sin_costo?, "el costo de hacer la pizza ya se conoce"
  assert_equal ["PLATO"], g.con_costo.map(&:label)
  assert_not_nil g.margen_pct
end

  test "un costo imposible se marca aunque el producto lleve meses sin venderse" do
    # El Amaretto Sour está a $99.999 y no vende desde septiembre. Comparando contra lo
    # cobrado no había contra qué comparar y se escapaba: 8 de los 13 rotos eran así.
    producto(1, "Amaretto Sour", 5_500, activo: false).update!(cost: 99_999)
    producto(2, "Vivo PLATO", 10_000).update!(cost: 3_000)
    6.times { |i| vender(2, "Vivo PLATO", 10_000, on: HOY - i) }

    a = ProductPrices.new(period: "3", to: HOY)

    assert_equal ["Amaretto Sour"], a.costos_sospechosos.map(&:name)
    assert_empty a.con_ventas.map(&:name) - ["Vivo"], "el parado no entra en el informe de ventas"
  end

  test "el costo se compara contra la carta SIN IVA, no contra la carta a secas" do
    # El Jamón pierna: costo $8.119, carta $8.190. Contra la carta parece que deja $71;
    # contra la carta sin IVA ($6.882) está $1.237 por debajo del costo.
    p = producto(1, "Jamón pierna", 8_190)
    p.update!(cost: 8_119)

    assert_operator p.cost_value, :<, p.price, "contra la carta con IVA no saltaría"
    assert p.cost_impossible?, "pero el IVA no es tuyo: el costo se come el precio"
    assert_in_delta 6_882.35, p.price_net, 0.5
  end

  test "un costo que es el precio del insumo por kilo canta solo" do
    # El Prosciutto crudo se vende a $2.200 y tiene costo $19.561, que es justo lo que
    # cuesta el kilo de jamón: la receta se está comiendo un kilo por porción.
    p = producto(1, "Prosciutto crudo", 2_200)
    p.update!(cost: 19_561)

    assert p.cost_impossible?
    assert_in_delta 10.6, p.cost_ratio, 0.1, "diez veces el precio de venta"
  end

  test "un costo normal no se marca, y uno justo en el límite tampoco" do
    sano  = producto(1, "Coca cola Original", 2_900)
    sano.update!(cost: 519)
    justo = producto(2, "Al límite", 1_190)
    justo.update!(cost: 1_000) # 1.190 / 1,19 = 1.000 exactos: empata, no supera

    assert_not sano.cost_impossible?
    assert_not justo.cost_impossible?, "empatar no es pasarse"
    assert_nil sano.cost_ratio
    assert_empty ProductPrices.new(period: "3", to: HOY).costos_sospechosos
  end

  test "sin carta no se puede juzgar el costo, y no se inventa" do
    p = producto(1, "Producto genérico", 0)
    p.update!(cost: 5_000)

    assert_nil p.price_net
    assert_not p.cost_impossible?, "sin precio no hay con qué comparar"
  end

  test "la lista de costos rotos va del más disparatado al menos" do
    producto(1, "Leve", 8_190).update!(cost: 8_119)        # 1,2x
    producto(2, "Disparate", 5_500).update!(cost: 99_999)  # 21,6x
    producto(3, "Medio", 2_200).update!(cost: 19_561)      # 10,6x

    assert_equal %w[Disparate Medio Leve],
                 ProductPrices.new(period: "3", to: HOY).costos_sospechosos.map(&:name)
  end

  # --- Los dos costos de Fudo ------------------------------------------------------

  test "el costo de la receta vale aunque no haya ninguno tecleado a mano" do
    # El caso que destapó esto: la Margherita 32 APLICACION salía "sin costo" en el
    # panel mientras Fudo enseñaba $4.914,91. El tecleado estaba vacío; el de la receta no.
    p = producto(1, "Margherita 32 cm APLICACION", 11_600)
    p.update!(cost: nil, components_cost: 4_914.914)
    6.times { |i| vender(1, "Margherita 32 cm APLICACION", 14_250, on: HOY - i) }

    c = ProductPrices.new(period: "3", to: HOY).con_ventas.first.canales.first

    assert_not c.sin_costo?, "tiene receta: no puede salir como que no tiene costo"
    assert_in_delta 4_914.91, c.costo, 0.01
    assert_equal :receta, p.cost_source
    assert_in_delta 59.0, c.margen_pct, 0.5
  end

  test "con los dos costos manda la receta, que es la que se actualiza sola" do
    # El Austral Calafate: $2.123 tecleado y $1.062 por receta, justo el doble.
    p = producto(1, "Austral Calafate 500cc", 5_500)
    p.update!(cost: 2_123.3, components_cost: 1_061.65)

    assert_in_delta 1_061.65, p.cost_value, 0.01,
                    "el tecleado se queda con el valor del día que se escribió"
    assert_in_delta 2_123.3, p.typed_cost, 0.01, "pero el dato sigue guardado, no se pierde"
    assert_equal :receta, p.cost_source
  end

  test "sin receta se usa el tecleado, y se dice que es el tecleado" do
    p = producto(1, "Coca cola Original", 2_900)
    p.update!(cost: 519, components_cost: nil)

    assert_in_delta 519, p.cost_value, 0.01
    assert_nil p.recipe_cost
    assert_equal :tecleado, p.cost_source
  end

  test "sin ninguno de los dos no hay costo ni origen que enseñar" do
    p = producto(1, "Nada PLATO", 10_000)

    assert_nil p.cost_value
    assert_nil p.cost_source
  end

  test "una receta a cero cuenta como que no hay receta" do
    p = producto(1, "Rara PLATO", 5_000)
    p.update!(cost: 800, components_cost: 0)

    assert_nil p.recipe_cost, "un 0 no es un costo: diría 100% de margen"
    assert_in_delta 800, p.cost_value, 0.01
    assert_equal :tecleado, p.cost_source
  end

  test "un costo de receta imposible también se marca para revisar" do
    p = producto(1, "Prosciutto crudo", 2_200)
    p.update!(components_cost: 19_561)

    assert p.cost_impossible?
    assert_equal ["Prosciutto crudo"], ProductPrices.new(period: "3", to: HOY).costos_sospechosos.map(&:name)
  end
end
