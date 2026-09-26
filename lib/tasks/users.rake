# frozen_string_literal: true

# Los usuarios del dashboard se crean desde la consola (no hay registro público).
#
#   bin/rails users:password           # pregunta correo y contraseña (oculta). Crea o actualiza.
#   bin/rails users:list
#   bin/rails "users:delete[correo@ejemplo.com]"
#
# En producción (dentro del contenedor):
#   bin/kamal app exec -i "bin/rails users:password"
require "io/console"

namespace :users do
  desc "Crea un usuario o cambia su contraseña (la pide por teclado, sin mostrarla)"
  task password: :environment do
    print "Correo: "
    email = $stdin.gets.to_s.strip
    abort "Correo vacío" if email.empty?

    # $stdin.getpass no muestra lo que escribes: la contraseña no queda en el historial
    # del shell ni en los argumentos del proceso, y puede llevar cualquier carácter.
    password = $stdin.getpass("Contraseña (no se ve al escribir): ")
    confirm  = $stdin.getpass("Repite la contraseña: ")
    abort "Las contraseñas no coinciden" unless password == confirm
    abort "La contraseña debe tener al menos 12 caracteres" if password.length < 12

    user = User.find_or_initialize_by(email_address: email)
    nuevo = user.new_record?
    user.password = password
    user.save!
    user.sessions.destroy_all unless nuevo # cierra sesiones abiertas al cambiar la clave
    puts nuevo ? "Usuario creado: #{user.email_address}" : "Contraseña actualizada: #{user.email_address}"
  end

  desc "Crea un usuario pasando correo y contraseña como argumentos (ojo: rake corta en comas)"
  task :create, [:email, :password] => :environment do |_, args|
    abort "Uso: bin/rails \"users:create[correo,contraseña]\" — mejor usa bin/rails users:password" if args[:email].blank? || args[:password].blank?
    abort "La contraseña debe tener al menos 12 caracteres" if args[:password].length < 12

    user = User.find_or_initialize_by(email_address: args[:email])
    nuevo = user.new_record?
    user.password = args[:password]
    user.save!
    puts nuevo ? "Usuario creado: #{user.email_address}" : "Contraseña actualizada: #{user.email_address}"
  end

  desc "Lista los usuarios"
  task list: :environment do
    User.order(:email_address).each { |u| puts "#{u.email_address} (sesiones activas: #{u.sessions.count})" }
  end

  desc "Elimina un usuario y cierra sus sesiones"
  task :delete, [:email] => :environment do |_, args|
    user = User.find_by!(email_address: args[:email])
    user.destroy!
    puts "Eliminado: #{args[:email]}"
  end
end
