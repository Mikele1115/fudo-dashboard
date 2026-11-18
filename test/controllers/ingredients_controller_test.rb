# frozen_string_literal: true

require "test_helper"

class IngredientsControllerTest < ActionDispatch::IntegrationTest
  HOY = Date.new(2026, 11, 4)

  setup { sign_in_as(User.take) }

  def buy(name:, qty:, total:, on: HOY, ingredient_id: 1, unit: "kg")
    @seq = (@seq || 0) + 1
    IngredientPurchase.create!(
      fudo_item_id: @seq, fudo_expense_id: 700 + @seq, fudo_ingredient_id: ingredient_id,
      ingredient_name: name, unit_name: unit, provider_name: "La Barra SpA",
      purchased_on: on - @seq, quantity: qty, line_total: total, unit_price: total / qty.to_f
    )
  end

  def cargar_menta
    6.times { buy(name: "Menta", qty: 0.3, total: 6504) }
    2.times { buy(name: "Menta", qty: 0.2, total: 4336) }
    buy(name: "Menta", qty: 0.5, total: 4336)
  end

  test "la pantalla de revisión lista la línea y dice cuál era la cantidad correcta" do
    cargar_menta

    get review_ingredients_path(period: "all")
    assert_response :success
    assert_select "h1", "Revisar cargas"
    assert_match "Menta", response.body
    assert_match "La Barra SpA", response.body
    assert_match "casi seguro", response.body
  end

  test "sin líneas marcadas la pantalla lo dice en vez de romperse" do
    5.times { buy(name: "Harina", qty: 10, total: 12_000) }

    get review_ingredients_path
    assert_response :success
    assert_match "Nada que revisar", response.body
  end

  test "el período filtra las líneas pero no cambia el precio habitual" do
    cargar_menta

    get review_ingredients_path(period: "all")
    con_todo = css_select("table").last.css("tbody tr").size

    get review_ingredients_path(period: "3")
    assert_response :success
    assert_operator css_select("table").last.css("tbody tr").size, :<=, con_todo
  end

  test "insumos enlaza a la pantalla de revisión con el número de líneas" do
    cargar_menta

    get ingredients_path
    assert_response :success
    assert_select "a[href=?]", review_ingredients_path, text: /Revisar cargas \(1\)/
  end

  test "los cuadros se abren y el de Insumos ya no está" do
    6.times { |i| buy(name: "Mozzarella", qty: 10, total: 60_000, on: HOY - (i * 5)) }

    get ingredients_path

    assert_response :success
    etiquetas = css_select("section.kpis details.kpi > summary .kpi__label").map { |e| e.text.strip }
    # El tercero se llama "Ahorro" o "Costó de más" según el signo del impacto.
    assert_equal 5, etiquetas.size
    assert_equal ["Gasto en insumos", "La canasta"], etiquetas.first(2)
    assert_includes ["Ahorro", "Costó de más"], etiquetas[2]
    assert_equal ["Subieron", "A revisar"], etiquetas.last(2)
    assert_equal 5, css_select("section.kpis details.kpi .kpi__detail").size,
                 "cada cuadro tiene su panel de detalle"
    assert_not_includes etiquetas, "Insumos"
  end

  # ---------- buscador de insumos ----------

  def catalogo
    %w[Mozzarella Harina Prosciutto].each_with_index do |nombre, i|
      6.times { |j| buy(name: nombre, qty: 10, total: 60_000, on: HOY - (j * 10), ingredient_id: i + 1) }
    end
  end

  def filas_del_buscador
    seccion = css_select("section.card").find { |s| s.text.include?("Buscar un insumo") }
    seccion.css("table.table--rows tbody tr").size
  end

  test "sin búsqueda no se dibuja la tabla entera, solo el buscador" do
    catalogo

    get ingredients_path

    assert_response :success
    assert_equal 0, filas_del_buscador, "la tabla de 121 filas no se dibuja de entrada"
    assert_select "h2", text: "Buscar un insumo"
    assert_match "Escribe el nombre de un insumo", response.body
  end

  test "buscar deja solo los insumos que coinciden" do
    catalogo

    get ingredients_path(q: "pro")

    assert_equal 1, filas_del_buscador
    assert_match "1 de 3 insumos", response.body
    # Solo se filtra esta sección: "Por categoría" sigue listando todo, como debe.
    tabla = css_select("section.card").find { |s| s.text.include?("Buscar un insumo") }
                                      .css("table.table--rows").to_html
    assert_match "Prosciutto", tabla
    assert_no_match(/Mozzarella/, tabla)
  end

  test "una búsqueda sin resultados lo dice y ofrece salidas" do
    catalogo

    get ingredients_path(q: "trufa blanca")

    assert_equal 0, filas_del_buscador
    assert_match "Ningún insumo coincide", response.body
    assert_select "a", text: "Ver todos"
  end

  test "con all=1 se puede ver el listado completo" do
    catalogo

    get ingredients_path(all: 1)

    assert_equal 3, filas_del_buscador
    assert_match "Volver al buscador", response.body
  end

  test "el cuadro del gasto enseña el desglose por categoría" do
    6.times { |i| buy(name: "Mozzarella", qty: 10, total: 60_000, on: HOY - (i * 5)) }

    get ingredients_path

    detalle = css_select("section.kpis details.kpi").first.css(".kpi__detail").to_html
    assert_match "Categoría", detalle
    assert_match "$360.000", detalle, "el desglose cuadra con el gasto del cuadro"
  end

  def alerta(suspect:)
    PriceAlert.create!(
      fudo_item_id: 9001, fudo_ingredient_id: 1, ingredient_name: "Ndjua piccante", unit_name: "kg",
      provider_name: "QI FOOD", purchased_on: HOY, baseline_price: 17_900, new_price: 47_250,
      change_pct: 164.0, overcost: 21_132, quantity: 0.72, suspect_quantity: suspect,
      twin_quantity: (1.8 if suspect), twin_purchased_on: (HOY - 14 if suspect)
    )
  end

  test "el panel marca la alerta cuya cantidad no cuadra con la plata" do
    buy(name: "Ndjua piccante", qty: 0.72, total: 34_020)
    alerta(suspect: true)

    get ingredients_path

    assert_response :success
    assert_select "h2", text: /Una carga para revisar/
    assert_match "revisar carga", response.body
    assert_no_match(/21\.132/, response.body, "el sobrecosto no ocurrió: no se muestra como plata perdida")
  end

  test "el panel sigue mostrando el sobrecosto de una subida real" do
    buy(name: "Ndjua piccante", qty: 0.72, total: 34_020)
    alerta(suspect: false)

    get ingredients_path

    assert_response :success
    assert_select "h2", text: /Un insumo subió de precio/
    assert_match "21.132", response.body
    assert_no_match(/revisar carga/, response.body)
  end
end
