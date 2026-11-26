# frozen_string_literal: true

require "test_helper"

# La corrida nocturna encadena ocho pasos y nadie la mira cuando funciona. Esto fija
# qué se ejecuta y en qué orden, que es lo que se rompe al añadir uno nuevo.
class SyncSalesJobTest < ActiveJob::TestCase
  # Anota las llamadas en vez de ir a Fudo.
  module Espia
    def self.llamadas = @llamadas ||= []
    def self.reset    = @llamadas = []
  end

  setup do
    Espia.reset
    @stubs = {
      SalesSync          => :run!,
      PurchasesSync      => :catch_up!,
      IngredientsSync    => :run!,
      IngredientClassifier => :run!,
      PriceAlertDetector => :run!,
      AlertNotifier      => :call,
      ProductsSync       => :run!,
      SaleItemsSync      => :catch_up!
    }
    # Se guarda el método original y se restaura en el teardown. Quitarlo sin más lo
    # borraba de verdad y dejaba sin `run!` a los tests que corrían después.
    @originales = {}
    @stubs.each do |klass, metodo|
      @originales[[klass, metodo]] = klass.method(metodo) if klass.respond_to?(metodo)
      klass.define_singleton_method(metodo) do |*_args, **_kw|
        Espia.llamadas << "#{klass}.#{metodo}"
        nil
      end
    end
  end

  teardown do
    @originales.each { |(klass, metodo), original| klass.define_singleton_method(metodo, original) }
  end

  test "el botón del panel hace lo mismo que la noche, menos avisar" do
    # Es el único botón que queda: sustituye a "Actualizar productos" y a
    # "Actualizar compras", que estaban cada uno en su pantalla.
    SyncSalesJob.perform_now("2026-11-04", with_purchases: true, notify: false)

    assert_equal [
      "SalesSync.run!",
      "PurchasesSync.catch_up!",
      "IngredientsSync.run!",
      "IngredientClassifier.run!",
      "PriceAlertDetector.run!",
      "ProductsSync.run!",
      "SaleItemsSync.catch_up!"
    ], Espia.llamadas
  end

  test "el botón del panel NO manda correos" do
    # Las alertas de precios van a varias personas: no pueden salir cada vez que
    # alguien pulsa un botón. Se detectan igual y el aviso sale por la noche.
    SyncSalesJob.perform_now("2026-11-04", with_purchases: true, notify: false)

    assert_not_includes Espia.llamadas, "AlertNotifier.call"
  end

  test "sin pedir nada sigue siendo solo las ventas del día" do
    SyncSalesJob.perform_now("2026-11-04")

    assert_equal ["SalesSync.run!"], Espia.llamadas
  end

  test "la corrida nocturna hace los ocho pasos, y los de venta al final" do
    SyncSalesJob.perform_now("2026-11-04", with_purchases: true)

    assert_equal [
      "SalesSync.run!",
      "PurchasesSync.catch_up!",
      "IngredientsSync.run!",
      "IngredientClassifier.run!",
      "PriceAlertDetector.run!",
      "AlertNotifier.call",
      "ProductsSync.run!",
      "SaleItemsSync.catch_up!"
    ], Espia.llamadas
  end

  test "la corrida nocturna sí avisa por correo" do
    SyncSalesJob.perform_now("2026-11-04", with_purchases: true)

    assert_includes Espia.llamadas, "AlertNotifier.call",
                    "quitar el correo de la noche dejaría las alertas sin salir nunca"
  end

  test "los precios de venta van después de las alertas" do
    SyncSalesJob.perform_now("2026-11-04", with_purchases: true)

    # Si lo nuevo fallara, lo que se mira cada mañana ya está guardado.
    assert_operator Espia.llamadas.index("AlertNotifier.call"), :<,
                    Espia.llamadas.index("ProductsSync.run!")
  end
end
