class PasswordsMailer < ApplicationMailer
  # Un correo de contraseña sin contexto parece un intento de phishing y acaba en la
  # papelera, que es lo peor que puede pasarle justo a este. Por eso el asunto dice de
  # qué sistema viene, y el cuerpo quién lo manda y para qué.
  def reset(user)
    @user = user
    @name = AppSettings.restaurant_name
    mail subject: "[#{@name}] Elige tu contraseña del panel", to: user.email_address
  end
end
