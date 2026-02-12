#!/usr/bin/env bash
# =============================================================================
# install.sh — Install all service dependencies for Job Market Intelligence
# =============================================================================
# Usage:
#   ./scripts/install.sh              # Install everything
#   ./scripts/install.sh --skip-clone # Skip git clone (repos already exist)
#   ./scripts/install.sh --service scraper-service  # Install single service
#   ./scripts/install.sh --help       # Show help
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GITHUB_ORG="OferGM-job-market-intelligence"
GITHUB_URL="https://github.com/${GITHUB_ORG}"

# All repositories in the organization
REPOS=(
  ".github"
  "infrastructure"
  "shared"
  "scraper-service"
  "nlp-service"
  "aggregation-service"
  "auth-service"
  "api-gateway"
  "frontend"
)

# Service directories and their language/runtime
declare -A SERVICE_LANG=(
  ["shared"]="bun"
  ["scraper-service"]="bun"
  ["api-gateway"]="bun"
  ["frontend"]="bun"
  ["nlp-service"]="python"
  ["aggregation-service"]="go"
  ["auth-service"]="go"
)

# Workspace root where all repos are cloned side-by-side
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Colors & output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_header()  { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
SKIP_CLONE=false
SINGLE_SERVICE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-clone)
      SKIP_CLONE=true
      shift
      ;;
    --service)
      SINGLE_SERVICE="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --skip-clone          Skip git clone (repos already exist)"
      echo "  --service <name>      Install dependencies for a single service"
      echo "  --help, -h            Show this help message"
      echo ""
      echo "Services: ${!SERVICE_LANG[*]}"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
check_prerequisites() {
  log_header "Checking Prerequisites"

  local missing=()

  # Git
  if command -v git &>/dev/null; then
    log_success "git $(git --version | awk '{print $3}')"
  else
    missing+=("git")
    log_error "git not found"
  fi

  # Docker
  if command -v docker &>/dev/null; then
    log_success "docker $(docker --version | awk '{print $3}' | tr -d ',')"
  else
    missing+=("docker")
    log_error "docker not found"
  fi

  # Docker Compose
  if docker compose version &>/dev/null 2>&1; then
    log_success "docker compose $(docker compose version --short 2>/dev/null || echo 'available')"
  elif command -v docker-compose &>/dev/null; then
    log_success "docker-compose $(docker-compose --version | awk '{print $4}' | tr -d ',')"
  else
    missing+=("docker-compose")
    log_error "docker compose not found"
  fi

  # Bun (for TypeScript services)
  if command -v bun &>/dev/null; then
    log_success "bun $(bun --version)"
  else
    missing+=("bun")
    log_warn "bun not found — required for scraper-service, api-gateway, shared, frontend"
    log_info "  Install: curl -fsSL https://bun.sh/install | bash"
  fi

  # Python (for NLP service)
  if command -v python3 &>/dev/null; then
    log_success "python3 $(python3 --version | awk '{print $2}')"
  else
    missing+=("python3")
    log_warn "python3 not found — required for nlp-service"
  fi

  # pip
  if command -v pip3 &>/dev/null || python3 -m pip --version &>/dev/null 2>&1; then
    log_success "pip3 available"
  else
    missing+=("pip3")
    log_warn "pip3 not found — required for nlp-service"
  fi

  # Go (for aggregation and auth services)
  if command -v go &>/dev/null; then
    log_success "go $(go version | awk '{print $3}' | tr -d 'go')"
  else
    missing+=("go")
    log_warn "go not found — required for aggregation-service, auth-service"
    log_info "  Install: https://go.dev/dl/"
  fi

  # Make (optional but recommended)
  if command -v make &>/dev/null; then
    log_success "make available"
  else
    log_warn "make not found — optional, used for Makefile shortcuts"
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo ""
    log_warn "Missing tools: ${missing[*]}"
    log_warn "Some services may not install correctly."
    echo ""
    read -rp "Continue anyway? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      log_info "Aborting. Please install missing tools and try again."
      exit 1
    fi
  else
    log_success "All prerequisites met!"
  fi
}

# ---------------------------------------------------------------------------
# Clone repositories
# ---------------------------------------------------------------------------
clone_repos() {
  log_header "Cloning Repositories"

  cd "$WORKSPACE_DIR"

  for repo in "${REPOS[@]}"; do
    if [[ -d "$repo" ]]; then
      log_info "$repo already exists — pulling latest..."
      (cd "$repo" && git pull --quiet 2>/dev/null) && log_success "$repo updated" || log_warn "$repo pull failed (may have uncommitted changes)"
    else
      log_info "Cloning $repo..."
      if git clone --quiet "${GITHUB_URL}/${repo}.git" 2>/dev/null; then
        log_success "$repo cloned"
      else
        log_error "Failed to clone $repo"
      fi
    fi
  done
}

# ---------------------------------------------------------------------------
# Install dependencies for a Bun/TypeScript service
# ---------------------------------------------------------------------------
install_bun_service() {
  local service_dir="$1"
  local service_name="$(basename "$service_dir")"

  if [[ ! -f "$service_dir/package.json" ]]; then
    log_warn "$service_name has no package.json — skipping"
    return 0
  fi

  log_info "Installing $service_name (Bun)..."
  (cd "$service_dir" && bun install --frozen-lockfile 2>/dev/null || bun install) \
    && log_success "$service_name dependencies installed" \
    || log_error "$service_name install failed"
}

# ---------------------------------------------------------------------------
# Install dependencies for a Python service
# ---------------------------------------------------------------------------
install_python_service() {
  local service_dir="$1"
  local service_name="$(basename "$service_dir")"

  log_info "Installing $service_name (Python)..."

  # Create virtual environment if it doesn't exist
  if [[ ! -d "$service_dir/.venv" ]]; then
    log_info "  Creating virtual environment..."
    python3 -m venv "$service_dir/.venv"
  fi

  # Activate venv and install
  # shellcheck disable=SC1091
  source "$service_dir/.venv/bin/activate"

  if [[ -f "$service_dir/requirements.txt" ]]; then
    pip install -r "$service_dir/requirements.txt" --quiet \
      && log_success "$service_name dependencies installed" \
      || log_error "$service_name pip install failed"
  elif [[ -f "$service_dir/pyproject.toml" ]]; then
    pip install -e "$service_dir" --quiet \
      && log_success "$service_name dependencies installed" \
      || log_error "$service_name pip install failed"
  else
    log_warn "$service_name has no requirements.txt or pyproject.toml — skipping"
  fi

  deactivate 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Install dependencies for a Go service
# ---------------------------------------------------------------------------
install_go_service() {
  local service_dir="$1"
  local service_name="$(basename "$service_dir")"

  if [[ ! -f "$service_dir/go.mod" ]]; then
    log_warn "$service_name has no go.mod — skipping"
    return 0
  fi

  log_info "Installing $service_name (Go)..."
  (cd "$service_dir" && go mod download && go mod verify) \
    && log_success "$service_name dependencies installed" \
    || log_error "$service_name go mod download failed"
}

# ---------------------------------------------------------------------------
# Install a single service
# ---------------------------------------------------------------------------
install_service() {
  local service_name="$1"
  local service_dir="$WORKSPACE_DIR/$service_name"

  if [[ ! -d "$service_dir" ]]; then
    log_error "Directory not found: $service_dir"
    return 1
  fi

  local lang="${SERVICE_LANG[$service_name]:-}"
  case "$lang" in
    bun)    install_bun_service "$service_dir" ;;
    python) install_python_service "$service_dir" ;;
    go)     install_go_service "$service_dir" ;;
    *)      log_warn "Unknown language for $service_name — skipping" ;;
  esac
}

# ---------------------------------------------------------------------------
# Setup environment files
# ---------------------------------------------------------------------------
setup_env() {
  log_header "Setting Up Environment"

  local infra_dir="$WORKSPACE_DIR/infrastructure"

  # Copy .env.example to .env if it doesn't exist
  if [[ -f "$infra_dir/docker/.env.example" ]] && [[ ! -f "$infra_dir/docker/.env" ]]; then
    cp "$infra_dir/docker/.env.example" "$infra_dir/docker/.env"
    log_success "Created docker/.env from .env.example"
    log_warn "  ⚠ Review and update docker/.env with your actual values (MongoDB URI, etc.)"
  elif [[ -f "$infra_dir/docker/.env" ]]; then
    log_info "docker/.env already exists — skipping"
  fi

  # Create .env files for individual services if templates exist
  for service_name in "${!SERVICE_LANG[@]}"; do
    local service_dir="$WORKSPACE_DIR/$service_name"
    if [[ -f "$service_dir/.env.example" ]] && [[ ! -f "$service_dir/.env" ]]; then
      cp "$service_dir/.env.example" "$service_dir/.env"
      log_success "Created $service_name/.env from .env.example"
    fi
  done
}

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------
print_summary() {
  log_header "Installation Summary"

  echo -e "${BOLD}Workspace:${NC}  $WORKSPACE_DIR"
  echo -e "${BOLD}Services:${NC}"
  echo ""

  for service_name in "${!SERVICE_LANG[@]}"; do
    local service_dir="$WORKSPACE_DIR/$service_name"
    local lang="${SERVICE_LANG[$service_name]}"
    local status="❌ not found"

    if [[ -d "$service_dir" ]]; then
      case "$lang" in
        bun)
          [[ -d "$service_dir/node_modules" ]] && status="✅ installed" || status="⚠️  no node_modules"
          ;;
        python)
          [[ -d "$service_dir/.venv" ]] && status="✅ installed (.venv)" || status="⚠️  no .venv"
          ;;
        go)
          [[ -f "$service_dir/go.sum" ]] && status="✅ installed" || status="⚠️  no go.sum"
          ;;
      esac
    fi

    printf "  %-25s %-10s %s\n" "$service_name" "($lang)" "$status"
  done

  echo ""
  log_info "Next steps:"
  echo "  1. Review and update docker/.env with your MongoDB URI and other secrets"
  echo "  2. Start infrastructure:  cd infrastructure && docker compose -f docker/docker-compose.yml up -d"
  echo "  3. Start development:     make dev   (or ./scripts/dev.sh)"
  echo "  4. Run health checks:     make health (or ./scripts/health-check.sh)"
  echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo ""
  echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   Job Market Intelligence — Dependency Installer          ║${NC}"
  echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  check_prerequisites

  # Clone or pull repos
  if [[ "$SKIP_CLONE" == false ]]; then
    clone_repos
  else
    log_info "Skipping clone (--skip-clone)"
  fi

  # Install dependencies
  if [[ -n "$SINGLE_SERVICE" ]]; then
    log_header "Installing Single Service: $SINGLE_SERVICE"
    install_service "$SINGLE_SERVICE"
  else
    log_header "Installing All Service Dependencies"
    for service_name in "${!SERVICE_LANG[@]}"; do
      install_service "$service_name"
    done
  fi

  # Setup environment files
  setup_env

  # Summary
  print_summary

  log_success "Installation complete!"
}

main "$@"