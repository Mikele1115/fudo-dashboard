# frozen_string_literal: true

require "test_helper"

class PurchasesMailerTest < ActionMailer::TestCase
  include FormatHelper # para comparar importes con el mismo formato que la plantilla

  setup do
    ENV["MAIL_TO"]   = "duena@example.com"
    ENV["MAIL_FROM"] = "informes@example.com"
    # Vacío a propósito: el .env del desarrollador no puede decidir a quién escribe un test.
    ENV["PRICE_ALERTS_EXTRA_TO"] = ""
  end

  teardown do
    ENV.delete("MAIL_TO")
    ENV.delete("MAIL_FROM")
    ENV.delete("PRICE_ALERTS_EXTRA_TO")
  end

  def alert(suspect: false, name: "Mozzarella")
    @seq = (@seq || 0) + 1
    PriceAlert.create!(
      fudo_item_id: @seq, fudo_ingredient_id: @seq, ingredient_name: name, unit_name: "kg",
      provider_name: "Lacteos SA", purchased_on: Date.new(2026, 11, 11),
      baseline_price: 7_000, new_price: 17_500, change_pct: 150.0,
      overcost: 126_000, quantity: 12,
      suspect_quantity: suspect,
      twin_quantity: (30 if suspect), twin_purchased_on: (Date.new(2026, 10, 28) if suspect)
    )
  end

  test "una subida real sale como alerta de precios con su sobrecosto" do
    a = alert

    correo = PurchasesMailer.price_alerts([a.id])

    assert_equal ["duena@example.com"], correo.to
    assert_match "Alerta de precios", correo.subject
    assert_match "Mozzarella subió", correo.subject
    [correo.html_part.body.to_s, correo.text_part.body.to_s].each do |cuerpo|
      assert_match "Costó de más", cuerpo
      assert_match "126.000", cuerpo
      assert_no_match(/revisar carga/i, cuerpo)
    end
  end

  test "una cantidad mal cargada no se anuncia como subida de precio" do
    a = alert(suspect: true)

    correo = PurchasesMailer.price_alerts([a.id])

    assert_match "Revisar cargas", correo.subject
    assert_match "revisar la cantidad cargada", correo.subject
    assert_no_match(/subió/, correo.subject)

    [correo.html_part.body.to_s, correo.text_part.body.to_s].each do |cuerpo|
      assert_match "28/10/2026", cuerpo, "dice cuándo se pagó ese mismo monto"
      assert_match "cantidad", cuerpo
      assert_no_match(/Sobrecosto total/, cuerpo, "no hubo sobrecosto: salió la misma plata")
      assert_match "revisar", cuerpo.downcase
    end
    assert_match "/insumos/revisar", correo.text_part.body.to_s
  end

  test "con una subida y una carga el titular dice las dos cosas" do
    ids = [alert.id, alert(suspect: true, name: "Ndjua piccante").id]

    correo = PurchasesMailer.price_alerts(ids)

    assert_match "Un insumo subió de precio y una carga para revisar", correo.subject
    assert_match "Alerta de precios", correo.subject, "hay una subida real: no es solo revisar cargas"
    assert_match "126.000", correo.html_part.body.to_s, "el sobrecosto real se sigue sumando"
  end

  test "el criterio va una sola vez y completo, no repartido y a medias" do
    a = alert(suspect: true)

    correo = PurchasesMailer.price_alerts([a.id])

    [correo.html_part.body.to_s, correo.text_part.body.to_s].each do |cuerpo|
      texto = cuerpo.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ")
      # Dos menciones y no más: la de arriba es el titular con el enlace para actuar, y la
      # de abajo va pegada a los números que la sostienen. La tercera, en el pie, sobraba.
      assert_equal 2, texto.scan(/mal cargada/).size + texto.scan(/corregir en Fudo es la cantidad/).size
      pie = texto.split("Se avisa cuando el precio sube").last
      assert_no_match(/cantidad/, pie, "el pie volvía a explicar lo mismo por tercera vez")
      # El criterio sí se queda: quien lo recibe no siempre puede abrir el panel.
      assert_match "#{PriceAlertDetector::CHANGE_PCT.round}%", texto
      assert_match money(PriceAlertDetector::MIN_OVERCOST), texto
      assert_match money(PriceAlertDetector::MIN_SPEND), texto
    end
  end

  # ---------- quién recibe cada correo ----------

  test "las alertas de precio van también a los destinatarios extra" do
    ENV["PRICE_ALERTS_EXTRA_TO"] = "compras@example.com, bodega@example.com"
    a = alert

    correo = PurchasesMailer.price_alerts([a.id])

    assert_equal %w[duena@example.com compras@example.com bodega@example.com], correo.to
  end

  test "los destinatarios extra NO reciben el informe de ventas ni el resumen semanal" do
    ENV["PRICE_ALERTS_EXTRA_TO"] = "compras@example.com"
    DailySale.create!(date: Date.new(2026, 11, 11), total: 1000, tickets: 10)

    assert_equal ["duena@example.com"], PurchasesMailer.weekly(Date.new(2026, 11, 16)).to
    assert_equal ["duena@example.com"], ReportMailer.daily(Date.new(2026, 11, 11)).to
  end

  test "sin destinatarios extra las alertas siguen yendo solo a MAIL_TO" do
    a = alert

    assert_equal ["duena@example.com"], PurchasesMailer.price_alerts([a.id]).to
  end

  test "un extra repetido en MAIL_TO no duplica el envío" do
    ENV["PRICE_ALERTS_EXTRA_TO"] = "duena@example.com, compras@example.com"
    a = alert

    assert_equal %w[duena@example.com compras@example.com], PurchasesMailer.price_alerts([a.id]).to
  end

  test "el resumen semanal marca las cargas en vez de contarlas como sobrecosto" do
    alert(suspect: true, name: "Ndjua piccante")
    IngredientPurchase.create!(
      fudo_item_id: 99, fudo_expense_id: 99, fudo_ingredient_id: 1,
      ingredient_name: "Ndjua piccante", unit_name: "kg", provider_name: "QI FOOD",
      purchased_on: Date.new(2026, 11, 11), quantity: 12, line_total: 210_000, unit_price: 17_500
    )

    correo = PurchasesMailer.weekly(Date.new(2026, 11, 16)) # lunes: cubre 9 -> 15 de noviembre

    assert_match "revisar carga", correo.html_part.body.to_s.downcase
    assert_match "REVISAR CARGA", correo.text_part.body.to_s
  end
end
