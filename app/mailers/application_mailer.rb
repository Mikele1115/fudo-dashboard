class ApplicationMailer < ActionMailer::Base
  # El remitente por defecto era el "from@example.com" que deja Rails al generar la
  # aplicación. Los correos de informes pasan el suyo a mano, pero el de recuperar
  # contraseña no lo hacía: habría salido con esa dirección de muestra.
  default from: -> { AppSettings.mail_from }
  layout "mailer"
end
