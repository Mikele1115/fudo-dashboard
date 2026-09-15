# syntax=docker/dockerfile:1
# check=error=true

# Imagen de producción de la app. Se construye con Kamal (bin/kamal deploy); ver config/deploy.yml.
# Es la plantilla estándar de Rails 8 en dos etapas: "build" instala gemas y compila assets,
# y la imagen final solo lleva lo necesario para correr (más pequeña y sin compiladores).

ARG RUBY_VERSION=3.4.5
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Paquetes que la app necesita en tiempo de ejecución
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 sqlite3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# ---------- etapa de construcción ----------
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Gemas primero (así Docker reutiliza esta capa si solo cambia el código)
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY . .

RUN bundle exec bootsnap precompile app/ lib/

# Compila los assets sin necesitar la clave maestra
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# ---------- imagen final ----------
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# La app corre con un usuario sin privilegios
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Prepara la base de datos (migraciones) antes de arrancar el servidor
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Thruster: servidor HTTP delante de Puma (compresión, caché de assets)
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
