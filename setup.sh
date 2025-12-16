#!/bin/bash
# PatchMon Self-Hosting Installation Script
# Automated deployment script for self-hosted PatchMon instances
# Usage: ./setup.sh
# Interactive self-hosting installation script

set -e

# Create main installation log file
INSTALL_LOG="/var/log/patchmon-install.log"
# Only try to write to log if we have permissions (fallback for non-root users during early checks)
if [ -w "/var/log" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === PatchMon Self-Hosting Installation Started ===" >> "$INSTALL_LOG"
else
    INSTALL_LOG="/tmp/patchmon-install.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === PatchMon Self-Hosting Installation Started ===" > "$INSTALL_LOG"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_VERSION="self-hosting-install.sh v1.3.3-selfhost-2025-11-07"
DEFAULT_GITHUB_REPO="https://github.com/hamedhdd/PatchMon"
FQDN=""
CUSTOM_FQDN=""
EMAIL=""

# Logging function
function log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] ${message}" >> "$INSTALL_LOG"
    echo "[${timestamp}] ${message}"
}
DEPLOYMENT_BRANCH="main"
GITHUB_REPO=""
DB_SAFE_NAME=""
DB_PASS=""
JWT_SECRET=""
BACKEND_PORT=""
APP_DIR=""
USE_LETSENCRYPT="false"
SERVER_PROTOCOL_SEL="https"
SERVER_PORT_SEL=""
SETUP_NGINX="true"
UPDATE_MODE="false"
SELECTED_INSTANCE=""
SELECTED_SERVICE_NAME=""

# Functions
print_status() { printf "${GREEN}%s${NC}\n" "$1"; }
print_info() { printf "${BLUE}%s${NC}\n" "$1"; }
print_error() { printf "${RED}%s${NC}\n" "$1"; }
print_warning() { printf "${YELLOW}%s${NC}\n" "$1"; }
print_question() { printf "${BLUE}%s${NC}\n" "$1"; }
print_success() { printf "${GREEN}%s${NC}\n" "$1"; }

# Interactive input functions
read_input() {
    local prompt="$1"
    local var_name="$2"
    local default_value="$3"
    if [ -n "$default_value" ]; then
        echo -n -e "${BLUE}$prompt${NC} [${YELLOW}$default_value${NC}]: "
    else
        echo -n -e "${BLUE}$prompt${NC}: "
    fi
    read -r input
    if [ -z "$input" ] && [ -n "$default_value" ]; then
        eval "$var_name='$default_value'"
    else
        eval "$var_name='$input'"
    fi
}

read_yes_no() {
    local prompt="$1"
    local var_name="$2"
    local default_value="$3"
    while true; do
        if [ -n "$default_value" ]; then
            echo -n -e "${BLUE}$prompt${NC} [${YELLOW}$default_value${NC}]: "
        else
            echo -n -e "${BLUE}$prompt${NC} (y/n): "
        fi
        read -r input
        if [ -z "$input" ] && [ -n "$default_value" ]; then input="$default_value"; fi
        case $input in
            [Yy]|[Yy][Ee][Ss]) eval "$var_name='y'"; break ;;
            [Nn]|[Nn][Oo]) eval "$var_name='n'"; break ;;
            *) print_error "Please answer yes (y) or no (n)" ;;
        esac
    done
}

print_banner() {
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${BLUE}        PatchMon Self-Hosting Installation${NC}"
    echo -e "${BLUE}Running: $SCRIPT_VERSION${NC}"
    echo -e "${BLUE}====================================================${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        print_info "Please run: sudo $0"
        exit 1
    fi
}

detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt update"
        PKG_UPGRADE="apt upgrade -y"
        PKG_INSTALL="apt install -y"
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
        PKG_UPDATE="apt-get update"
        PKG_UPGRADE="apt-get upgrade -y"
        PKG_INSTALL="apt-get install -y"
    else
        print_error "No supported package manager found (apt or apt-get required)"
        exit 1
    fi
}

check_prerequisites() {
    print_info "Running and checking prerequisites..."
    check_root
    detect_package_manager
    print_info "Installing prerequisite applications..."
    if ! command -v sudo >/dev/null 2>&1; then $PKG_INSTALL sudo; fi
    $PKG_INSTALL wget curl jq git netcat-openbsd
}

init_instance_vars() {
    DB_SAFE_NAME=$(echo "$FQDN" | sed 's/[^a-zA-Z0-9]/_/g' | sed 's/^_*//' | sed 's/_*$//')
    if [[ "$FQDN" =~ ^[0-9] ]]; then
        RANDOM_PREFIX=$(tr -dc 'a-z' < /dev/urandom | head -c 2)
        DB_SAFE_NAME="${RANDOM_PREFIX}${DB_SAFE_NAME}"
    fi
    DB_NAME="${DB_SAFE_NAME}"
    DB_USER="${DB_SAFE_NAME}"
    DB_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    JWT_SECRET=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-50)
    BACKEND_PORT=$((3001 + RANDOM % 999))
    if [ "$SERVER_PROTOCOL_SEL" = "https" ]; then SERVER_PORT_SEL=443; else SERVER_PORT_SEL=$BACKEND_PORT; fi
    APP_DIR="/opt/${FQDN}"
    SERVICE_NAME="${FQDN}"
    INSTANCE_USER=$(echo "$DB_SAFE_NAME" | cut -c1-32)
}

install_nodejs() {
    export PATH="/usr/bin:/usr/local/bin:$PATH"
    if command -v node >/dev/null 2>&1; then
        NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
        if [ "$NODE_VERSION" -ge 18 ]; then return 0; fi
    fi
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    $PKG_INSTALL nodejs
}

install_postgresql() {
    if ! systemctl is-active --quiet postgresql; then
        $PKG_INSTALL postgresql postgresql-contrib
        systemctl start postgresql
        systemctl enable postgresql
    fi
}

install_redis() {
    if ! systemctl is-active --quiet redis-server; then
        $PKG_INSTALL redis-server
        systemctl start redis-server
        systemctl enable redis-server
    fi
}

install_nginx() {
    if ! systemctl is-active --quiet nginx; then
        $PKG_INSTALL nginx
        systemctl start nginx
        systemctl enable nginx
    fi
}

create_instance_user() {
    mkdir -p "$APP_DIR"
    if ! id "$INSTANCE_USER" &>/dev/null; then
        useradd --system --no-create-home --shell /bin/false "$INSTANCE_USER"
    fi
    chown -R "$INSTANCE_USER:$INSTANCE_USER" "$APP_DIR"
    chmod 755 "$APP_DIR"
}

setup_database() {
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" || true
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" || true
}

clone_application() {
    if [ -d "$APP_DIR" ]; then rm -rf "$APP_DIR"; fi
    git clone "$GITHUB_REPO" "$APP_DIR"
    chown -R "$INSTANCE_USER:$INSTANCE_USER" "$APP_DIR"
}

install_dependencies() {
    cd "$APP_DIR/backend"
    npm install
    cd "$APP_DIR/frontend"
    npm install
    npm run build
    chown -R "$INSTANCE_USER:$INSTANCE_USER" "$APP_DIR"
}

create_env_files() {
    cat > "$APP_DIR/backend/.env" << EOF
DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME"
JWT_SECRET="$JWT_SECRET"
PORT=$BACKEND_PORT
NODE_ENV=production
EOF
}

run_migrations() {
    cd "$APP_DIR/backend"
    npx prisma migrate deploy
    npx prisma generate
}

create_systemd_service() {
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=PatchMon Service for $FQDN
After=network.target postgresql.service

[Service]
Type=simple
User=$INSTANCE_USER
Group=$INSTANCE_USER
WorkingDirectory=$APP_DIR/backend
ExecStart=/usr/bin/node src/index.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PATH=/usr/bin:/usr/local/bin

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
}

create_agent_version() {
    print_info "Copying agent script..."
    if [ -f "$APP_DIR/agent/patchmon-agent.sh" ]; then
        cp "$APP_DIR/agent/patchmon-agent.sh" "$APP_DIR/backend/"
        chmod +x "$APP_DIR/backend/patchmon-agent.sh"
    fi
}

interactive_setup() {
    print_banner
    check_prerequisites
    read_input "Enter your domain name or IP (e.g., patchmon.internal)" FQDN "patchmon.internal"
    read_yes_no "Enable SSL with Let's Encrypt?" SSL_ENABLED "n"
    if [ "$SSL_ENABLED" = "y" ]; then
        read_input "Enter email for SSL" EMAIL
        USE_LETSENCRYPT="true"
    fi
    GITHUB_REPO="$DEFAULT_GITHUB_REPO"
    
    init_instance_vars
    install_nodejs
    install_postgresql
    install_redis
    install_nginx
    
    create_instance_user
    setup_database
    clone_application
    install_dependencies
    create_env_files
    run_migrations
    create_systemd_service
    create_agent_version
    
    systemctl start "$SERVICE_NAME"
    print_success "PatchMon deployed to http://localhost:$BACKEND_PORT or configure Nginx proxy."
}

# Main execution
if [ "$1" = "--update" ]; then
    echo "Update mode not fully implemented in this simplified wrapper. Please run git pull manualy."
else
    interactive_setup
fi
