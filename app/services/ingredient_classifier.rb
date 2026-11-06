# frozen_string_literal: true

# Crea el catálogo de categorías y asigna los insumos por palabras clave.
#
# Medido contra 12 meses de compras reales: estas reglas clasifican solas el
# 96,6% del gasto (105 de 151 insumos). El resto se asigna a mano en la pantalla
# de categorías — son insumos de poco peso y casos que solo el local sabe
# resolver (si la leña va con la cocina, si el helado es postre).
#
# Regla de oro: **nunca pisa una asignación hecha por una persona**. Si el
# usuario movió un insumo de categoría, volver a correr esto lo respeta.
class IngredientClassifier
  # Orden importante: gana la primera que coincida. Las más específicas van
  # antes que las genéricas (p. ej. "salsa de tomate" antes que "tomate").
  CATALOGO = [
    # [categoría, área, posición, regla]
    ["Quesos",                "Cocina",   1, /queso|mozzarell?a|parmesano|pecorino|gorgonzola|mascarpone|burrata|bufala|búfala|provolone|ricotta|grana|bocconcini|scamorza|stracciatella|ciliegine/i],
    ["Embutidos y carnes",    "Cocina",   2, /prosciutto|jam(o|ó)n|salame|salami|salsiccia|guanciale|ventricina|ndjua|nduja|speck|panceta|tocino|pepperoni|chorizo|carne|pollo|lomo|porchetta|spianata/i],
    ["Pescados y mariscos",   "Cocina",   3, /camar(o|ó)n|pulpo|at(u|ú)n|anchoa|salm(o|ó)n|marisco|pescado|calamar|mejill/i],
    ["Aceites y conservas",   "Cocina",   4, /aceite|vinagre|salsa de tomate|conserva|pesto|oliva|aceitun/i],
    ["Salsas y condimentos",  "Cocina",   5, /salsa (inglesa|tabasco|de soya|soya)|tabasco|merken|mostaza|mayonesa|ketchup|s(e|é)samo/i],
    ["Verduras y frutas",     "Cocina",   6, /tomate|tomatito|cebolla|albahaca|r(u|ú)cula|lechuga|papa|lim(o|ó)n|naranja|frutilla|mango|maracuy|berries|alcachofa|champi|hongo|pimient|piment(o|ó)n|zapallo|ajo\b|jengibre|menta|palta|pulpa|platano|plátano|manzana|nuez|nueces|frutos secos|zanahoria|acelga|espinaca|pepino|br(o|ó)coli|poroto|choclo|arveja/i],
    ["Harinas y secos",       "Cocina",   7, /harina|s(e|é)mola|semolina|levadura|az(u|ú)car|arroz|fideo|pasta|garbanzo|legumbre|gelatina|galleta|almid|or(e|é)gano|canela|especia|sal\b/i],
    ["Lácteos y huevos",      "Cocina",   8, /leche|crema|mantequilla|manteca|huevo|yog(h)?ur/i],
    ["Postres y helados",     "Cocina",   9, /helado|postre|tiramis|cacao|chocolate/i],
    ["Leña y combustible",    "Cocina",  10, /le(ñ|n)a|carb(o|ó)n|gas\b/i],

    ["Cerveza y barriles",    "Bar",      1, /barril|cerveza|austral|coda|stout|\bipa\b|lager|\bale\b|calafate/i],
    ["Vinos y destilados",    "Bar",      2, /vino|vermouth|pisco|whisky|\bron\b|vodka|\bgin\b|tequi|aperol|campari|licor|espumante|champ|triple sec|amaretto|disaronno|ramazotti|amaro|drambuie|fernet|jager|araucano/i],
    ["Bebidas sin alcohol",   "Bar",      3, /bebida|coca|sprite|fanta|agua|soda|jugo|ginger|t(o|ó)nica|red bull|energ/i],
    ["Café, té e infusiones", "Bar",      4, /caf(e|é)|\bt(e|é)\b|infusi|yerba/i],
    ["Hielo y gas",           "Bar",      5, /hielo|\bco2\b|tanque/i],

    ["Envases y desechables", "Envases",  1, /caja|servilleta|bolsa|vaso|envase|contenedor|film|papel|tapa\b|cubierto|individual|delivery|pocillo/i],

    ["Limpieza",              "Limpieza", 1, /deterg|cloro|limpia|lavaloza|desinfect|gu(a|á)nte|escoba|jab(o|ó)n|sanitiz|toalla/i]
  ].freeze

  # Crea las categorías que falten. Idempotente: no toca las que ya existen,
  # para no deshacer los cambios de nombre o de área que haga el usuario.
  def self.seed_categories!
    CATALOGO.each do |nombre, area, posicion, _|
      IngredientCategory.find_or_create_by!(name: nombre) do |c|
        c.area     = area
        c.position = posicion
      end
    end
    IngredientCategory.count
  end

  def self.run! = new.run!

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  # Asigna por reglas los insumos que aún no tienen categoría puesta a mano.
  # Devuelve [asignados, sin_asignar].
  def run!
    self.class.seed_categories!
    categorias = IngredientCategory.all.index_by(&:name)
    manuales   = IngredientAssignment.manual.pluck(:fudo_ingredient_id).to_set

    asignados = 0
    sin_asignar = []

    ingredientes.each do |id, nombre|
      next if manuales.include?(id) # lo decidió una persona: no se toca

      nombre_categoria = self.class.categoria_para(nombre)
      if nombre_categoria.nil?
        sin_asignar << nombre
        next
      end

      categoria = categorias[nombre_categoria]
      asignacion = IngredientAssignment.find_or_initialize_by(fudo_ingredient_id: id)
      asignacion.ingredient_category = categoria
      asignacion.ingredient_name     = nombre
      asignacion.automatic           = true
      asignacion.save!
      asignados += 1
    end

    @logger.info "IngredientClassifier: #{asignados} asignados por regla, #{sin_asignar.size} sin categoría"
    [asignados, sin_asignar]
  end

  def self.categoria_para(nombre)
    CATALOGO.find { |_, _, _, regla| nombre.to_s =~ regla }&.first
  end

  private

  # { fudo_ingredient_id => nombre más reciente }, de todo lo que se ha comprado.
  def ingredientes
    IngredientPurchase.newest.pluck(:fudo_ingredient_id, :ingredient_name)
                      .each_with_object({}) { |(id, nombre), h| h[id] ||= nombre }
  end
end
