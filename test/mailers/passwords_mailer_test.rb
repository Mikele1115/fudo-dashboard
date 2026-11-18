# frozen_string_literal: true

require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  setup do
    ENV["MAIL_FROM"] = "informes@example.com"
    @user = User.create!(email_address: "nueva@example.com", password: SecureRandom.base58(40))
  end

  teardown { ENV.delete("MAIL_FROM") }

  test "sale con el remitente del local, no con el de muestra de Rails" do
    correo = PasswordsMailer.reset(@user)

    assert_equal ["informes@example.com"], correo.from
    assert_no_match(/example\.com.*from@/, correo.from.to_s)
  end

  test "dice de qué sistema viene y para qué, para no parecer phishing" do
    correo = PasswordsMailer.reset(@user)

    assert_match AppSettings.restaurant_name, correo.subject
    assert_match "contraseña", correo.subject
    assert_no_match(/Reset your password/, correo.subject, "estaba en inglés")

    [correo.html_part.body.to_s, correo.text_part.body.to_s].each do |cuerpo|
      assert_match AppSettings.restaurant_name, cuerpo
      # El token se firma con la hora, así que cambia en cada llamada: se comprueba la
      # forma del enlace, no su valor.
      assert_match %r{/passwords/[\w\-]+/edit}, cuerpo, "falta el enlace para elegirla"
      assert_match "Si no esperabas este correo", cuerpo
    end
  end

  test "el enlace lleva al panel de verdad, no a example.com" do
    correo = PasswordsMailer.reset(@user)

    host = Rails.application.config.action_mailer.default_url_options[:host]
    assert_match host, correo.text_part.body.to_s
  end
end
