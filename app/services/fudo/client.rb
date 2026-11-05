# frozen_string_literal: true

require "net/http"

module Fudo
  # Cliente mínimo para la API de propósito general de Fudo.
  # Docs: https://dev.fu.do/api  (spec: https://api.fu.do/v1alpha1/openapi.yml)
  class Client
    AUTH_URL    = "https://auth.fu.do/api"
    BASE_URL    = "https://api.fu.do/v1alpha1"
    PAGE_SIZE   = 500 # máximo permitido por la API
    MAX_RETRIES = 4

    class Error < StandardError; end

    def initialize(api_key: ENV.fetch("FUDO_API_KEY", ""), api_secret: ENV.fetch("FUDO_API_SECRET", ""), logger: Rails.logger)
      @api_key    = api_key
      @api_secret = api_secret
      @logger     = logger
      @token      = nil
      @token_exp  = 0
    end

    # Ventas con estado CLOSED cuyo closedAt está en [from_utc, to_utc).
    # Devuelve un array de:
    #   { closed_at: Time (UTC), total: Float, sale_type: "EAT-IN"|"TAKEAWAY"|"DELIVERY",
    #     people: Integer (comensales; 0 en delivery/takeaway), tips: Float (propinas, no incluidas en total) }
    def closed_sales(from_utc, to_utc)
      sales = []
      page  = 1
      loop do
        body = get("/sales",
                   "filter[closedAt]"  => "and(gte.#{iso(from_utc)},lt.#{iso(to_utc)})",
                   "filter[saleState]" => "in.(CLOSED)",
                   "fields[sale]"      => "closedAt,total,saleType,people,tips",
                   "include"           => "tips",
                   "sort"              => "closedAt",
                   "page[size]"        => PAGE_SIZE,
                   "page[number]"      => page)
        # JSON:API: los recursos relacionados (propinas) vienen aparte en "included"; los indexamos por [tipo, id].
        tips_by_id = body.fetch("included", []).each_with_object({}) do |r, h|
          h[[r["type"], r["id"]]] = r["attributes"] || {}
        end

        rows = body.fetch("data", [])
        rows.each do |row|
          attrs = row["attributes"] || {}
          next if attrs["closedAt"].nil?

          tip_refs = row.dig("relationships", "tips", "data") || []
          tips = tip_refs.sum do |ref|
            tip = tips_by_id[[ref["type"], ref["id"]]]
            tip && !tip["canceled"] ? tip["amount"].to_f : 0.0
          end

          sales << {
            closed_at: Time.iso8601(attrs["closedAt"]).utc,
            total:     attrs["total"].to_f,
            sale_type: attrs["saleType"],
            people:    attrs["people"].to_i,
            tips:      tips
          }
        end
        # La API no devuelve total de ítems: la última página es la que trae menos que PAGE_SIZE.
        break if rows.size < PAGE_SIZE

        page += 1
      end
      sales
    end

    # Lineas de compra de insumos entre dos fechas (ambas inclusive).
    #
    # En Fudo una compra es un "egreso" (/expenses) con varias lineas (expenseItems).
    # Cada linea puede apuntar a un insumo (ingredient), a un producto, o a nada;
    # aqui solo interesan las que tienen insumo.
    #
    # Ojo con dos cosas, comprobadas contra la cuenta real:
    #   - `price` de la linea es el TOTAL de la linea, no el precio unitario
    #     (100 cajas por 52.000 = 520 c/u). El unitario es price / quantity.
    #   - ese total es NETO: el `amount` del egreso es ~1,19x la suma de sus lineas (IVA).
    #
    # Devuelve un array de:
    #   { item_id:, expense_id:, ingredient_id:, ingredient_name:, unit_name:,
    #     detail:, provider_name:, date: Date, quantity: Float, line_total: Float }
    def ingredient_purchases(from_date, to_date)
      purchases = []
      page = 1
      loop do
        body = get("/expenses",
                   "filter[date]"        => "and(gte.#{from_date},lte.#{to_date})",
                   "filter[canceled]"    => "neq.true",
                   "include"             => "expenseItems.ingredient,expenseItems.ingredient.unit,provider",
                   "fields[expense]"     => "date,amount,canceled,provider,expenseItems",
                   "fields[expenseItem]" => "price,quantity,detail,canceled,ingredient",
                   "fields[ingredient]"  => "name,unit",
                   "fields[provider]"    => "name",
                   "sort"                => "id",
                   "page[size]"          => PAGE_SIZE,
                   "page[number]"        => page)

        # JSON:API devuelve los relacionados aparte, en "included"; se indexan por [tipo, id].
        included = body.fetch("included", []).each_with_object({}) { |r, h| h[[r["type"], r["id"]]] = r }

        rows = body.fetch("data", [])
        rows.each do |expense|
          attrs = expense["attributes"] || {}
          next if attrs["canceled"] || attrs["date"].nil?

          date     = Date.parse(attrs["date"])
          prov_ref = expense.dig("relationships", "provider", "data")
          provider = prov_ref && included[[prov_ref["type"], prov_ref["id"]]]&.dig("attributes", "name")

          (expense.dig("relationships", "expenseItems", "data") || []).each do |item_ref|
            item  = included[[item_ref["type"], item_ref["id"]]]
            next if item.nil?

            iattr = item["attributes"] || {}
            next if iattr["canceled"]

            ing_ref = item.dig("relationships", "ingredient", "data")
            next if ing_ref.nil? # linea sin insumo (producto o gasto suelto): no es compra de insumo

            ingredient = included[[ing_ref["type"], ing_ref["id"]]]
            unit_ref   = ingredient&.dig("relationships", "unit", "data")
            unit       = unit_ref && included[[unit_ref["type"], unit_ref["id"]]]&.dig("attributes", "name")

            quantity   = iattr["quantity"].to_f
            next unless quantity.positive? # sin cantidad no hay precio unitario que calcular

            purchases << {
              item_id:         item["id"].to_i,
              expense_id:      expense["id"].to_i,
              ingredient_id:   ing_ref["id"].to_i,
              ingredient_name: ingredient&.dig("attributes", "name").presence || iattr["detail"].to_s,
              unit_name:       unit,
              detail:          iattr["detail"],
              provider_name:   provider,
              date:            date,
              quantity:        quantity,
              line_total:      iattr["price"].to_f
            }
          end
        end

        break if rows.size < PAGE_SIZE

        page += 1
      end
      purchases
    end

    # Prueba de conexión: autentica y pide 1 venta.
    def ping
      token
      get("/sales", "page[size]" => 1, "page[number]" => 1)
      true
    end

    private

    def iso(time)
      time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    end

    def token
      return @token if @token && Time.now.to_i < @token_exp - 300

      raise Error, "Faltan FUDO_API_KEY / FUDO_API_SECRET en el archivo .env" if @api_key.empty? || @api_secret.empty?

      uri = URI(AUTH_URL)
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Accept" => "application/json")
      req.body = JSON.generate(apiKey: @api_key, apiSecret: @api_secret)
      res = http(uri).request(req)
      unless res.is_a?(Net::HTTPSuccess)
        raise Error, "Autenticación en Fudo fallida (HTTP #{res.code}): #{res.body.to_s[0, 300]}"
      end

      data   = JSON.parse(res.body)
      @token = data["token"]
      raise Error, "Respuesta de autenticación sin token: #{res.body.to_s[0, 300]}" if @token.blank?

      exp = data["exp"].to_i
      @token_exp = exp.positive? ? exp : Time.now.to_i + (24 * 3600)
      @logger.info "Fudo: token obtenido"
      @token
    end

    def get(path, params)
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params)

      attempt = 0
      loop do
        attempt += 1
        req = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{token}", "Accept" => "application/json")
        res = http(uri).request(req)

        return JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)

        if res.code == "401" && attempt == 1
          @token = nil # token vencido o inválido: renovar y reintentar una vez
          next
        end

        retryable = res.code == "429" || res.code.start_with?("5")
        if retryable && attempt <= MAX_RETRIES
          wait = 2**attempt
          @logger.warn "Fudo: HTTP #{res.code} en GET #{path}; reintento en #{wait}s"
          sleep wait
          next
        end

        raise Error, "GET #{path} -> HTTP #{res.code}: #{res.body.to_s[0, 300]}"
      end
    end

    def http(uri)
      h = Net::HTTP.new(uri.host, uri.port)
      h.use_ssl      = true
      h.open_timeout = 15
      h.read_timeout = 90
      h
    end
  end
end
