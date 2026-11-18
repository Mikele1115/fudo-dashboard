# frozen_string_literal: true

require "test_helper"

# Corre el banco de pruebas de filtro_controller.js dentro de `bin/rails test`.
#
# Una prueba que hay que acordarse de lanzar a mano no se lanza. El buscador es la única
# parte del panel cuya lógica vive en JavaScript, así que su comprobación entra en la
# suite como cualquier otra: filtro_test.mjs carga el controlador de verdad contra un DOM
# de mentira y devuelve 1 si algo falla.
class FiltroJsTest < ActiveSupport::TestCase
  BANCO = Rails.root.join("test/javascript/filtro_test.mjs")

  test "la lógica del buscador hace lo que dice" do
    skip "node no está instalado" unless system("node --version", out: File::NULL, err: File::NULL)

    salida = `node #{Shellwords.escape(BANCO.to_s)} 2>&1`
    assert $CHILD_STATUS.success?, "falla el banco de pruebas del buscador:\n#{salida}"
  end
end
