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
