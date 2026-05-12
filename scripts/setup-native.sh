#!/usr/bin/env bash
set -euo pipefail

# Travium local setup without Docker.
# Supported: Ubuntu 22.04/24.04, Debian 11/12/13.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOMAIN="${DOMAIN:-travium.local}"
DB_NAME="${DB_NAME:-maindb}"
DB_USER="${DB_USER:-maindb}"
DB_PASS="${DB_PASS:-TraviumMainDb_2026}"
DB_ROOT_PASS="${DB_ROOT_PASS:-}"
FORCE_DB_IMPORT="${FORCE_DB_IMPORT:-0}"
RECAPTCHA_PUBLIC="${RECAPTCHA_PUBLIC:-6LdQ8AIsAAAAAM0SKRYd_JiGqVqxZPTYflrdPOvH}"
RECAPTCHA_PRIVATE="${RECAPTCHA_PRIVATE:-6LdQ8AIsAAAAANlEknjUf9LWLODJrpoDiHXTvPAV}"
INSTALLER_KEY="${INSTALLER_KEY:-$(openssl rand -hex 16)}"
VOTING_SECRET="${VOTING_SECRET:-$(openssl rand -hex 8)}"

log() { printf "\033[1;34m[*]\033[0m %s\n" "$*"; }
ok() { printf "\033[1;32m[OK]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERR]\033[0m %s\n" "$*" >&2; }

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    err "Execute como root ou com sudo."
    exit 1
  fi
}

check_os() {
  if [[ ! -r /etc/os-release ]]; then
    err "Nao foi possivel ler /etc/os-release"
    exit 1
  fi

  # shellcheck source=/etc/os-release
  . /etc/os-release

  case "${ID,,}" in
    ubuntu)
      case "${VERSION_ID}" in
        22.04|24.04) ;;
        *) err "Ubuntu ${VERSION_ID} nao suportado"; exit 1 ;;
      esac
      ;;
    debian)
      case "${VERSION_ID}" in
        11|12|13) ;;
        *) err "Debian ${VERSION_ID} nao suportado"; exit 1 ;;
      esac
      ;;
    *) err "SO nao suportado: ${PRETTY_NAME:-desconhecido}"; exit 1 ;;
  esac

  OS_ID="${ID,,}"
  OS_VERSION="${VERSION_ID}"
  ok "SO detectado: ${PRETTY_NAME}"
}

install_base_packages() {
  log "Instalando pacotes base..."
  apt-get update -y
  apt-get install -y \
    ca-certificates \
    curl \
    gettext-base \
    gnupg2 \
    lsb-release \
    software-properties-common \
    unzip \
    git
}

setup_php_repo() {
  log "Configurando repositorio para PHP 7.4..."
  if [[ "${OS_ID}" == "ubuntu" ]]; then
    add-apt-repository -y ppa:ondrej/php
  else
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/keyrings/php.gpg
    if command -v lsb_release >/dev/null 2>&1; then
      codename="$(lsb_release -sc)"
    else
      codename="bookworm"
    fi
    echo "deb [signed-by=/etc/apt/keyrings/php.gpg] https://packages.sury.org/php/ ${codename} main" >/etc/apt/sources.list.d/php-sury.list
  fi
  apt-get update -y
}

install_runtime() {
  log "Instalando Nginx, MariaDB, Redis, Memcached e PHP 7.4..."
  apt-get install -y \
    nginx \
    mariadb-server \
    redis-server \
    memcached \
    php7.4-cli \
    php7.4-fpm \
    php7.4-mysql \
    php7.4-xml \
    php7.4-mbstring \
    php7.4-zip \
    php7.4-gd \
    php7.4-curl \
    php7.4-bcmath \
    php7.4-redis
}

install_composer() {
  if command -v composer >/dev/null 2>&1; then
    ok "Composer ja instalado"
    return
  fi

  log "Instalando Composer..."
  curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
  php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
  rm -f /tmp/composer-setup.php
}

enable_services() {
  log "Ativando servicos..."
  systemctl enable --now mariadb
  systemctl enable --now redis-server
  systemctl enable --now memcached
  systemctl enable --now nginx
  systemctl enable --now php7.4-fpm
}

configure_database() {
  log "Configurando banco ${DB_NAME}..."

  if [[ -n "${DB_ROOT_PASS}" ]]; then
    mysql_cmd=(mysql -uroot "-p${DB_ROOT_PASS}")
  else
    mysql_cmd=(mysql -uroot)
  fi

  "${mysql_cmd[@]}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

  if [[ -f "${ROOT_DIR}/maindb.sql" ]]; then
    table_count="$("${mysql_cmd[@]}" -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';")"
    if [[ "${FORCE_DB_IMPORT}" == "1" ]]; then
      log "FORCE_DB_IMPORT=1 detectado, reimportando maindb.sql..."
      "${mysql_cmd[@]}" "${DB_NAME}" <"${ROOT_DIR}/maindb.sql"
      ok "Import forcado de maindb.sql concluido"
    elif [[ "${table_count}" -gt 0 ]]; then
      log "Banco ${DB_NAME} ja possui ${table_count} tabelas. Pulando import do maindb.sql."
    else
      "${mysql_cmd[@]}" "${DB_NAME}" <"${ROOT_DIR}/maindb.sql"
      ok "Import de maindb.sql concluido"
    fi
  else
    err "Arquivo maindb.sql nao encontrado em ${ROOT_DIR}"
    exit 1
  fi
}

configure_project() {
  log "Configurando projeto..."

  if [[ ! -f "${ROOT_DIR}/config.sample.php" ]]; then
    err "config.sample.php nao encontrado"
    exit 1
  fi

  cp -f "${ROOT_DIR}/config.sample.php" "${ROOT_DIR}/config.php"

  sed -i \
    -e "s/INIT_RECAPTCHA_PUBLIC_KEY/${RECAPTCHA_PUBLIC//\//\\/}/g" \
    -e "s/INIT_RECAPTCHA_PRIVATE_KEY/${RECAPTCHA_PRIVATE//\//\\/}/g" \
    -e "s/INIT_DOMAIN/${DOMAIN//\//\\/}/g" \
    -e "s/INIT_MAIN_DB_PASSWORD/${DB_PASS//\//\\/}/g" \
    -e "s/INIT_INSTALLER_SECRET_KEY/${INSTALLER_KEY//\//\\/}/g" \
    -e "s/INIT_SECRET_TOKEN/${VOTING_SECRET//\//\\/}/g" \
    "${ROOT_DIR}/config.php"

  find "${ROOT_DIR}/homepage" -type f -name "*.js" -print0 2>/dev/null \
    | xargs -0 -r sed -i "s/INIT_RECAPTCHA_PUBLIC_KEY/${RECAPTCHA_PUBLIC//\//\\/}/g"

  cd "${ROOT_DIR}"
  COMPOSER_MEMORY_LIMIT=-1 composer install --no-interaction --prefer-dist --optimize-autoloader

  ok "Projeto configurado"
}

configure_nginx() {
  log "Gerando configuracao Nginx..."

  php_fpm_sock="/run/php/php7.4-fpm.sock"
  if [[ ! -S "${php_fpm_sock}" ]]; then
    err "Socket PHP-FPM nao encontrado em ${php_fpm_sock}"
    exit 1
  fi

  install -d -m 0755 /etc/nginx/sites-available /etc/nginx/sites-enabled
  env ROOT_DIR="$ROOT_DIR" DOMAIN="$DOMAIN" php_fpm_sock="$php_fpm_sock" \
    envsubst '$ROOT_DIR $DOMAIN $php_fpm_sock' \
    <"${ROOT_DIR}/nginx/travium.local.conf.template" \
    >"/etc/nginx/sites-available/travium.local.conf"

  ln -sfn /etc/nginx/sites-available/travium.local.conf /etc/nginx/sites-enabled/travium.local.conf
  rm -f /etc/nginx/sites-enabled/default

  nginx -t
  systemctl reload nginx

  ok "Nginx configurado"
}

print_summary() {
  cat <<TXT

Ambiente pronto sem Docker.

Dominio base: ${DOMAIN}
Projeto: ${ROOT_DIR}
Banco: ${DB_NAME}
Usuario DB: ${DB_USER}
Senha DB: ${DB_PASS}

Adicione no /etc/hosts:
127.0.0.1 ${DOMAIN} www.${DOMAIN} install.${DOMAIN} api.${DOMAIN} cdn.${DOMAIN} voting.${DOMAIN} payment.${DOMAIN} s1.${DOMAIN}

Depois abra:
http://install.${DOMAIN}/?key=${INSTALLER_KEY}

TXT
}

main() {
  require_root
  check_os
  install_base_packages
  setup_php_repo
  install_runtime
  install_composer
  enable_services
  configure_database
  configure_project
  configure_nginx
  print_summary
}

main "$@"
