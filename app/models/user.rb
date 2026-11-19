class User < ApplicationRecord
  # El enlace para elegir contraseña dura 24 horas, no los 15 minutos que trae Rails.
  #
  # Esos 15 minutos están pensados para quien acaba de pedir el reinicio y está esperando
  # el correo. Aquí el caso es el contrario: la cuenta se le crea a alguien que no sabe
  # que existe, y hay que avisarle por otro lado antes de que el enlace caduque. A
  # Scarlett y a Luis se les pasó dos veces.
  #
  # A cambio, el enlace vive un día: quien entre en esa bandeja mañana todavía puede
  # usarlo. Para un panel de ventas de una pizzería el intercambio compensa; si algún día
  # esto guarda algo más delicado, hay que volver a mirarlo. Sigue siendo de un solo uso:
  # va firmado con el salt de la contraseña, así que al cambiarla el token deja de valer.
  has_secure_password reset_token: { expires_in: 24.hours }
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
