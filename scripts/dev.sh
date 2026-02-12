#!/usr/bin/env bash
# =============================================================================
# dev.sh — Start all services in development mode
# =============================================================================
# Usage:
#   ./scripts/dev.sh                    # Start infrastructure + all services
#   ./scripts/dev.sh --infra-only       # Start only Docker infrastructure
#   ./scripts/dev.sh --services-only    # Start only application services (infra must be running)
#   ./scripts/dev.sh --service scraper-service  # Start a single service
#   ./scripts/dev.sh --stop             # Stop everything
#   ./scripts/dev.sh --help             # Show help
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"

DOCKER_COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
ENV_FILE="$ROOT_DIR/docker/.env"
PID_DIR="$ROOT_DIR/.pids"
LOG_DIR="$ROOT_DIR/.logs"

# Service startup commands (run from their respective directories)
declare -A SERVICE_CMD=(
  ["scraper-service"]="bun run dev"
  ["nlp-service"]=".venv/bin/python -m uvicorn src.main:app --reload --port 3002"
  ["aggregation-service"]="go run ./cmd/server/main.go"
  ["auth-service"]="go run ./cmd/server/main.go"
  ["api-gateway"]="bun run dev"
  ["frontend"]="bun run dev"
)

# Service ports for readiness checks
declare -A SERVICE_PORT=(
  ["scraper-service"]="3000"
  ["nlp-service"]="3002"
  ["aggregation-service"]="3003"
  ["auth-service"]="3001"
  ["api-gateway"]="4000"
  ["frontend"]="5173"
)

# ---------------------------------------------------------------------------
# Colors & output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_header()  { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
MODE="all"           # all | infra-only | services-only | stop
SINGLE_SERVICE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --infra-only)     MODE="infra-only";    shift ;;
    --services-only)  MODE="services-only"; shift ;;
    --stop)           MODE="stop";          shift ;;
    --service)        SINGLE_SERVICE="$2";  shift 2 ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --infra-only          Start only Docker infrastructure"
      echo "  --services-only       Start only application services"
      echo "  --service <name>      Start a single service"
      echo "  --stop                Stop everything"
      echo "  --help, -h            Show this help"
      echo ""
      echo "Services: ${!SERVICE_CMD[*]}"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Infrastructure management
# ---------------------------------------------------------------------------
start_infrastructure() {
  log_header "Starting Docker Infrastructure"

  if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
    log_error "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
    exit 1
  fi

  # Load env file if it exists
  local env_flag=""
  if [[ -f "$ENV_FILE" ]]; then
    env_flag="--env-file $ENV_FILE"
  else
    log_warn "No .env file found at $ENV_FILE — using defaults"
  fi

  log_info "Starting containers..."
  # shellcheck disable=SC2086
  docker compose -f "$DOCKER_COMPOSE_FILE" $env_flag up -d

  log_info "Waiting for services to become healthy..."
  wait_for_infrastructure
}

wait_for_infrastructure() {
  local max_wait=120
  local elapsed=0
  local interval=5

  local services=("kafka" "redis" "elasticsearch")

  for service in "${services[@]}"; do
    log_info "  Waiting for $service..."
    while [[ $elapsed -lt $max_wait ]]; do
      local health
      health=$(docker inspect --format='{{.State.Health.Status}}' "$(docker compose -f "$DOCKER_COMPOSE_FILE" ps -q "$service" 2>/dev/null)" 2>/dev/null || echo "not_found")

      if [[ "$health" == "healthy" ]]; then
        log_success "  $service is healthy"
        break
      elif [[ "$health" == "not_found" ]]; then
        # Container might not have health check — check if running
        local state
        state=$(docker compose -f "$DOCKER_COMPOSE_FILE" ps --format "{{.State}}" "$service" 2>/dev/null || echo "not_found")
        if [[ "$state" == "running" ]]; then
          log_success "  $service is running"
          break
        fi
      fi

      sleep "$interval"
      elapsed=$((elapsed + interval))
    done

    if [[ $elapsed -ge $max_wait ]]; then
      log_warn "  $service did not become healthy within ${max_wait}s"
    fi
  done
}

stop_infrastructure() {
  log_info "Stopping Docker infrastructure..."
  if [[ -f "$DOCKER_COMPOSE_FILE" ]]; then
    docker compose -f "$DOCKER_COMPOSE_FILE" down
    log_success "Infrastructure stopped"
  fi
}

# ---------------------------------------------------------------------------
# Service management
# ---------------------------------------------------------------------------
start_service() {
  local service_name="$1"
  local service_dir="$WORKSPACE_DIR/$service_name"
  local cmd="${SERVICE_CMD[$service_name]:-}"
  local port="${SERVICE_PORT[$service_name]:-}"

  if [[ -z "$cmd" ]]; then
    log_warn "No dev command configured for $service_name — skipping"
    return 0
  fi

  if [[ ! -d "$service_dir" ]]; then
    log_warn "Directory not found: $service_dir — skipping"
    return 0
  fi

  # Check if already running
  if [[ -f "$PID_DIR/$service_name.pid" ]]; then
    local existing_pid
    existing_pid=$(cat "$PID_DIR/$service_name.pid")
    if kill -0 "$existing_pid" 2>/dev/null; then
      log_warn "$service_name already running (PID $existing_pid)"
      return 0
    else
      rm -f "$PID_DIR/$service_name.pid"
    fi
  fi

  mkdir -p "$PID_DIR" "$LOG_DIR"

  log_info "Starting $service_name on port $port..."

  # Start service in background, redirect output to log file
  (cd "$service_dir" && $cmd) > "$LOG_DIR/$service_name.log" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_DIR/$service_name.pid"

  log_success "$service_name started (PID $pid, logs: .logs/$service_name.log)"
}

stop_service() {
  local service_name="$1"

  if [[ -f "$PID_DIR/$service_name.pid" ]]; then
    local pid
    pid=$(cat "$PID_DIR/$service_name.pid")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      # Wait for graceful shutdown
      local wait_count=0
      while kill -0 "$pid" 2>/dev/null && [[ $wait_count -lt 10 ]]; do
        sleep 1
        wait_count=$((wait_count + 1))
      done
      # Force kill if still running
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
      fi
      log_success "$service_name stopped (PID $pid)"
    else
      log_info "$service_name was not running"
    fi
    rm -f "$PID_DIR/$service_name.pid"
  else
    log_info "$service_name has no PID file"
  fi
}

start_all_services() {
  log_header "Starting Application Services"

  if [[ -n "$SINGLE_SERVICE" ]]; then
    start_service "$SINGLE_SERVICE"
  else
    for service_name in "${!SERVICE_CMD[@]}"; do
      start_service "$service_name"
    done
  fi
}

stop_all_services() {
  log_header "Stopping Application Services"

  for service_name in "${!SERVICE_CMD[@]}"; do
    stop_service "$service_name"
  done

  # Clean up PID and log directories
  rm -rf "$PID_DIR"
  log_success "All services stopped"
}

# ---------------------------------------------------------------------------
# Status display
# ---------------------------------------------------------------------------
print_status() {
  log_header "Development Environment Status"

  echo -e "${BOLD}Infrastructure:${NC}"
  if [[ -f "$DOCKER_COMPOSE_FILE" ]]; then
    docker compose -f "$DOCKER_COMPOSE_FILE" ps --format "table {{.Name}}\t{{.State}}\t{{.Ports}}" 2>/dev/null || echo "  Docker Compose not running"
  fi

  echo ""
  echo -e "${BOLD}Application Services:${NC}"
  printf "  %-25s %-8s %-8s %s\n" "SERVICE" "PORT" "STATUS" "PID"
  printf "  %-25s %-8s %-8s %s\n" "-------" "----" "------" "---"

  for service_name in "${!SERVICE_CMD[@]}"; do
    local port="${SERVICE_PORT[$service_name]:-N/A}"
    local status="stopped"
    local pid="—"

    if [[ -f "$PID_DIR/$service_name.pid" ]]; then
      pid=$(cat "$PID_DIR/$service_name.pid")
      if kill -0 "$pid" 2>/dev/null; then
        status="${GREEN}running${NC}"
      else
        status="${RED}dead${NC}"
        pid="—"
      fi
    fi

    printf "  %-25s %-8s %-18b %s\n" "$service_name" "$port" "$status" "$pid"
  done

  echo ""
  echo -e "${BOLD}Logs:${NC} $LOG_DIR/"
  echo -e "${BOLD}PIDs:${NC} $PID_DIR/"
  echo ""
  echo -e "View service logs:  ${CYAN}tail -f $LOG_DIR/<service>.log${NC}"
  echo -e "Stop everything:    ${CYAN}$0 --stop${NC}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo ""
  echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   Job Market Intelligence — Development Server           ║${NC}"
  echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  case "$MODE" in
    stop)
      stop_all_services
      stop_infrastructure
      ;;
    infra-only)
      start_infrastructure
      ;;
    services-only)
      start_all_services
      print_status
      ;;
    all)
      start_infrastructure
      start_all_services
      print_status
      ;;
  esac
}

main "$@"