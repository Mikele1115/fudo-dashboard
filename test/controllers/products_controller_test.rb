# frozen_string_literal: true

require "test_helper"

# Lo que la pantalla de Productos tiene que enseñar de los costos.
#
# La regla de la casa: un dato mal cargado NO se corrige solo. Se deja como está y se
# marca, porque arreglarlo de verdad es entrar a Fudo. Estos tests existen para que
# nadie "mejore" eso más adelante escondiendo el número raro o poniéndolo en cero.
class ProductsControllerTest < ActionDispatch::IntegrationTest
  include FormatHelper

  HOY = Date.new(2026, 11, 4)

  setup { sign_in_as(User.take) }

  # La celda de Costo de la tabla principal. Por posición y no por texto, porque el
  # mismo importe aparece también en el cuadro de abajo, que es justo lo que se quiere.
  CELDA_COSTO = "table.table--rows tbody tr td:nth-child(4)"

  def producto(id, nombre, precio, costo: nil)
    base, canal = Product.partir_nombre(nombre)
    Product.create!(fudo_product_id: id, name: nombre, base_name: base, channel: canal,
                    price: precio, cost: costo, active: true)
  end

  def vender(id, nombre, precio, veces: 6)
    veces.times do |i|
      @seq = (@seq || 0) + 1
      SaleItem.create!(fudo_item_id: @seq, fudo_sale_id: @seq, fudo_product_id: id,
                       product_name: nombre, sold_on: HOY - i, closed_at: (HOY - i).to_time,
                       quantity: 1, line_total: precio, unit_price: precio)
    end
  end

  test "un costo mayor que el precio se marca para revisar y el número se deja intacto" do
    # El Pisco Norterra está cargado en Fudo a $99.999 y se vende a $6.200.
    producto(1, "Pisco Norterra 40º", 6_200, costo: 99_999)
    vender(1, "Pisco Norterra 40º", 6_200)

    get products_path(all: 1)

    assert_response :success
    assert_select CELDA_COSTO, text: /\$99\.999/,
                  message: "el costo torcido tiene que verse tal cual, no corregido ni escondido"
    assert_select "#{CELDA_COSTO} .tag", text: "revisar"
    assert_select ".tag", text: "revisar costo"
    assert_select "#{CELDA_COSTO} .tag--na", { count: 0 },
                  "tiene costo, está mal: no es lo mismo que no tenerlo"
  end

  test "un plato sin costo lo dice, y no inventa un cero" do
    producto(1, "Margherita 32 cm PLATO", 11_400)
    vender(1, "Margherita 32 cm PLATO", 11_400)

    get products_path(all: 1)

    assert_response :success
    assert_select "#{CELDA_COSTO} .tag.tag--na", text: "sin costo"
    assert_select CELDA_COSTO, text: /\$/, count: 0,
                  message: "sin dato no se pinta importe: un $0 diría 100% de margen"
    assert_select ".tag", { text: "revisar", count: 0 }, "no hay costo que revisar"
  end

  test "un costo normal enseña el margen sin el IVA" do
    producto(1, "Coca cola Original", 2_900, costo: 519)
    vender(1, "Coca cola Original", 2_900)

    get products_path(all: 1)

    assert_response :success
    assert_select CELDA_COSTO, text: /\$519/
    assert_select ".pct.pct--up", text: "79%", count: 1
    assert_select ".tag", { text: "revisar", count: 0 }
  end

  test "el detalle del plato también enseña costo y margen por canal" do
    producto(1, "Coca cola Original", 2_900, costo: 519)
    vender(1, "Coca cola Original", 2_900)

    get product_path(1)

    assert_response :success
    assert_select "th", text: "Costo"
    assert_select "th", text: "Margen"
    assert_select ".pct.pct--up", text: "79%"
  end

  test "el detalle avisa cuando el canal que miras no tiene costo" do
    producto(1, "Margherita 32 cm PLATO", 11_400, costo: 4_000)
    producto(2, "Margherita 32 cm APLICACION", 14_250)
    vender(1, "Margherita 32 cm PLATO", 11_400)
    vender(2, "Margherita 32 cm APLICACION", 14_250)

    get product_path(2)

    assert_response :success
    assert_select ".tag.tag--na", text: "sin costo"
    assert_match(/Sin costo en APLICACION/, response.body)
  end

  test "un plato cuya receta se dispara en un canal sale marcado y listado" do
    # Un menú donde la app añade ~2.500 a todos, y una Silvestre que añade 8.678.
    %w[Margherita Serrano Gamberetti Pancetta Diavola].each_with_index do |nombre, i|
      producto(i * 2 + 1, "#{nombre} 32 cm PLATO", 11_400).update!(components_cost: 2_000)
      producto(i * 2 + 2, "#{nombre} 32 cm APLICACION", 14_250).update!(components_cost: 4_500)
      vender(i * 2 + 1, "#{nombre} 32 cm PLATO", 11_400)
      vender(i * 2 + 2, "#{nombre} 32 cm APLICACION", 14_250)
    end
    producto(97, "Silvestre 32 cm PLATO", 11_400).update!(components_cost: 2_000)
    producto(98, "Silvestre 32 cm APLICACION", 14_250).update!(components_cost: 10_678)
    vender(97, "Silvestre 32 cm PLATO", 11_400)
    vender(98, "Silvestre 32 cm APLICACION", 14_250)

    get products_path(all: 1)

    assert_response :success
    assert_select ".tag", { text: "revisar receta", count: 1 },
                  "solo la Silvestre: las otras pagan la misma comisión"
    assert_select "h3", text: /Recetas que se disparan en un canal \(1\)/
  end

  test "si todos los canales pagan lo mismo no se marca a nadie" do
    %w[Margherita Serrano Gamberetti].each_with_index do |nombre, i|
      producto(i * 2 + 1, "#{nombre} 32 cm PLATO", 11_400).update!(components_cost: 2_000)
      producto(i * 2 + 2, "#{nombre} 32 cm APLICACION", 14_250).update!(components_cost: 4_500)
      vender(i * 2 + 1, "#{nombre} 32 cm PLATO", 11_400)
      vender(i * 2 + 2, "#{nombre} 32 cm APLICACION", 14_250)
    end

    get products_path(all: 1)

    assert_response :success
    assert_select ".tag", { text: "revisar receta", count: 0 }
    assert_select "h3", { text: /Recetas que se disparan/, count: 0 }
  end
end
