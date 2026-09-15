# frozen_string_literal: true

# Los usuarios del dashboard se crean desde la consola (no hay registro público):
#   bin/rails "users:create[correo@ejemplo.com,una-clave-larga]"
#   bin/rails users:list
#   bin/rails "users:delete[correo@ejemplo.com]"
namespace :users do
  desc "Crea un usuario, o cambia su contraseña si ya existe"
  task :create, [:email, :password] => :environment do |_, args|
    abort "Uso: bin/rails \"users:create[correo,contraseña]\"" if args[:email].blank? || args[:password].blank?
    abort "La contraseña debe tener al menos 12 caracteres" if args[:password].length < 12

    user = User.find_or_initialize_by(email_address: args[:email])
    user.password = args[:password]
    user.save!
    puts "#{user.previously_new_record? ? 'Usuario creado' : 'Contraseña actualizada'}: #{user.email_address}"
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
