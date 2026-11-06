# frozen_string_literal: true

# Trae de Fudo el catálogo de insumos con su categoría.
#
# Fudo es la fuente de verdad de la categoría: aquí solo se copia. Por eso el
# upsert pisa siempre el valor anterior — si el usuario recategoriza en el POS,
# esto lo refleja.
class IngredientsSync
  def self.run! = new.run!

  def initialize(client: Fudo::Client.new, logger: Rails.logger)
    @client = client
    @logger = logger
  end

  def run!
    rows = @client.ingredients
    return 0 if rows.empty?

    now = Time.current
    registros = rows.map do |r|
      {
        fudo_id:            r[:id],
        name:               r[:name],
        unit_name:          r[:unit_name],
        fudo_category_id:   r[:category_id],
        fudo_category_name: r[:category_name],
        synced_at:          now,
        created_at:         now,
        updated_at:         now
      }
    end

    registros.each_slice(500) { |slice| Ingredient.upsert_all(slice, unique_by: :fudo_id) }
    @logger.info "IngredientsSync: #{registros.size} insumos, #{registros.count { |r| r[:fudo_category_name] }} con categoría"
    registros.size
  end
end
