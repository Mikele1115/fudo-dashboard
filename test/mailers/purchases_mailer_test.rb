# frozen_string_literal: true

require "test_helper"

class PurchasesMailerTest < ActionMailer::TestCase
  setup do
    ENV["MAIL_TO"]   = "duena@example.com"
    ENV["MAIL_FROM"] = "informes@example.com"
  end

  teardown do
    ENV.delete("MAIL_TO")
    ENV.delete("MAIL_FROM")
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
