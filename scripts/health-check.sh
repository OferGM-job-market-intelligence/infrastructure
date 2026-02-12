#!/usr/bin/env bash
# =============================================================================
# health-check.sh — Verify all infrastructure and services are running
# =============================================================================
# Usage:
#   ./scripts/health-check.sh             # Check everything
#   ./scripts/health-check.sh --infra     # Check infrastructure only
#   ./scripts/health-check.sh --services  # Check application services only
#   ./scripts/health-check.sh --wait      # Wait until all healthy (with timeout)
#   ./scripts/health-check.sh --json      # Output results as JSON
#   ./scripts/health-check.sh --help      # Show help
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKER_COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
PID_DIR="$ROOT_DIR/.pids"

# Infrastructure services (Docker containers)
declare -A INFRA_SERVICES=(
  ["zookeeper"]="2181"
  ["kafka"]="9092"
  ["redis"]="6380"
  ["elasticsearch"]="9200"
  ["kibana"]="5601"
  ["localstack"]="4566"
)

# Infrastructure health check endpoints
declare -A INFRA_HEALTH=(
  ["redis"]="redis-cli ping"
  ["elasticsearch"]="http://localhost:9200/_cluster/health"
  ["kibana"]="http://localhost:5601/api/status"
  ["localstack"]="http://localhost:4566/_localstack/health"
)

# Application services
declare -A APP_SERVICES=(
  ["scraper-service"]="3000"
  ["auth-service"]="3001"
  ["nlp-service"]="3002"
  ["aggregation-service"]="3003"
  ["api-gateway"]="4000"
  ["frontend"]="5173"
)

# Application health endpoints
declare -A APP_HEALTH=(
  ["scraper-service"]="http://localhost:3000/health"
  ["auth-service"]="http://localhost:3001/health"
  ["nlp-service"]="http://localhost:3002/health"
  ["aggregation-service"]="http://localhost:3003/health"
  ["api-gateway"]="http://localhost:4000/health"
  ["frontend"]="http://localhost:5173"
)

# ---------------------------------------------------------------------------
# Colors & output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_fail()    { echo -e "${RED}[FAIL]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_header()  { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
CHECK_MODE="all"      # all | infra | services
WAIT_MODE=false
WAIT_TIMEOUT=180
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --infra)      CHECK_MODE="infra";    shift ;;
    --services)   CHECK_MODE="services"; shift ;;
    --wait)       WAIT_MODE=true;        shift ;;
    --timeout)    WAIT_TIMEOUT="$2";     shift 2 ;;
    --json)       JSON_OUTPUT=true;      shift ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --infra               Check infrastructure only"
      echo "  --services            Check application services only"
      echo "  --wait                Wait until healthy (default timeout: 180s)"
      echo "  --timeout <seconds>   Set wait timeout (use with --wait)"
      echo "  --json                Output results as JSON"
      echo "  --help, -h            Show this help"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Health check functions
# ---------------------------------------------------------------------------
TOTAL_CHECKS=0
HEALTHY_COUNT=0
UNHEALTHY_COUNT=0
declare -A RESULTS=()

check_port() {
  local port="$1"
  local timeout="${2:-2}"

  if command -v nc &>/dev/null; then
    nc -z -w "$timeout" localhost "$port" 2>/dev/null
  elif command -v bash &>/dev/null; then
    (echo >/dev/tcp/localhost/"$port") 2>/dev/null
  else
    # Fallback to curl
    curl -sf --max-time "$timeout" "http://localhost:$port" >/dev/null 2>&1
  fi
}

check_http_endpoint() {
  local url="$1"
  local timeout="${2:-5}"

  curl -sf --max-time "$timeout" "$url" >/dev/null 2>&1
}

check_docker_container() {
  local service_name="$1"

  if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
    return 1
  fi

  # Get container ID
  local container_id
  container_id=$(docker compose -f "$DOCKER_COMPOSE_FILE" ps -q "$service_name" 2>/dev/null || echo "")

  if [[ -z "$container_id" ]]; then
    return 1
  fi

  # Check running state
  local state
  state=$(docker inspect --format='{{.State.Running}}' "$container_id" 2>/dev/null || echo "false")

  if [[ "$state" != "true" ]]; then
    return 1
  fi

  # Check health status if available
  local health
  health=$(docker inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "none")

  case "$health" in
    healthy) return 0 ;;
    none)    return 0 ;;  # No health check configured but container is running
    *)       return 1 ;;
  esac
}

check_infrastructure() {
  log_header "Infrastructure Health"

  printf "  %-20s %-8s %-12s %-10s %s\n" "SERVICE" "PORT" "CONTAINER" "PORT" "HEALTH"
  printf "  %-20s %-8s %-12s %-10s %s\n" "-------" "----" "---------" "----" "------"

  for service_name in "${!INFRA_SERVICES[@]}"; do
    local port="${INFRA_SERVICES[$service_name]}"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    # Check container status
    local container_status="—"
    if check_docker_container "$service_name"; then
      container_status="${GREEN}running${NC}"
    else
      container_status="${RED}stopped${NC}"
    fi

    # Check port accessibility
    local port_status="—"
    if check_port "$port"; then
      port_status="${GREEN}open${NC}"
    else
      port_status="${RED}closed${NC}"
    fi

    # Check health endpoint (if available)
    local health_status="—"
    local endpoint="${INFRA_HEALTH[$service_name]:-}"
    if [[ -n "$endpoint" ]]; then
      if [[ "$endpoint" == http* ]]; then
        if check_http_endpoint "$endpoint"; then
          health_status="${GREEN}healthy${NC}"
          HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
          RESULTS[$service_name]="healthy"
        else
          health_status="${RED}unhealthy${NC}"
          UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))
          RESULTS[$service_name]="unhealthy"
        fi
      elif [[ "$endpoint" == "redis-cli ping" ]]; then
        if docker exec "$(docker compose -f "$DOCKER_COMPOSE_FILE" ps -q redis 2>/dev/null)" redis-cli ping 2>/dev/null | grep -q PONG; then
          health_status="${GREEN}healthy${NC}"
          HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
          RESULTS[$service_name]="healthy"
        else
          health_status="${RED}unhealthy${NC}"
          UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))
          RESULTS[$service_name]="unhealthy"
        fi
      fi
    else
      # No health endpoint — use port check as indicator
      if check_port "$port"; then
        HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
        RESULTS[$service_name]="healthy"
        health_status="${GREEN}(port ok)${NC}"
      else
        UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))
        RESULTS[$service_name]="unhealthy"
        health_status="${RED}(port closed)${NC}"
      fi
    fi

    printf "  %-20s %-8s %-22b %-20b %b\n" "$service_name" "$port" "$container_status" "$port_status" "$health_status"
  done
}

check_app_services() {
  log_header "Application Services Health"

  printf "  %-25s %-8s %-12s %-10s %s\n" "SERVICE" "PORT" "PROCESS" "PORT" "ENDPOINT"
  printf "  %-25s %-8s %-12s %-10s %s\n" "-------" "----" "-------" "----" "--------"

  for service_name in "${!APP_SERVICES[@]}"; do
    local port="${APP_SERVICES[$service_name]}"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    # Check PID file
    local process_status="—"
    if [[ -f "$PID_DIR/$service_name.pid" ]]; then
      local pid
      pid=$(cat "$PID_DIR/$service_name.pid")
      if kill -0 "$pid" 2>/dev/null; then
        process_status="${GREEN}running${NC}"
      else
        process_status="${RED}dead${NC}"
      fi
    else
      process_status="${YELLOW}no pid${NC}"
    fi

    # Check port
    local port_status="—"
    if check_port "$port"; then
      port_status="${GREEN}open${NC}"
    else
      port_status="${RED}closed${NC}"
    fi

    # Check health endpoint
    local health_status="—"
    local endpoint="${APP_HEALTH[$service_name]:-}"
    if [[ -n "$endpoint" ]]; then
      if check_http_endpoint "$endpoint" 3; then
        health_status="${GREEN}healthy${NC}"
        HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
        RESULTS[$service_name]="healthy"
      else
        health_status="${RED}unreachable${NC}"
        UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))
        RESULTS[$service_name]="unhealthy"
      fi
    else
      if check_port "$port"; then
        HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
        RESULTS[$service_name]="healthy"
      else
        UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))
        RESULTS[$service_name]="unhealthy"
      fi
    fi

    printf "  %-25s %-8s %-22b %-20b %b\n" "$service_name" "$port" "$process_status" "$port_status" "$health_status"
  done
}

# ---------------------------------------------------------------------------
# MongoDB Atlas check
# ---------------------------------------------------------------------------
check_mongodb() {
  log_header "MongoDB Atlas"

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  # Check if MONGODB_URI is set
  local env_file="$ROOT_DIR/docker/.env"
  if [[ -f "$env_file" ]] && grep -q "MONGODB_URI" "$env_file" 2>/dev/null; then
    local uri
    uri=$(grep "MONGODB_URI" "$env_file" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    if [[ -n "$uri" && "$uri" != "mongodb+srv://"* && "$uri" != "mongodb://"* ]] || [[ -z "$uri" ]]; then
      log_warn "  MONGODB_URI not configured in .env"
      RESULTS["mongodb"]="not_configured"
      UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))
    else
      log_success "  MONGODB_URI is configured"
      RESULTS["mongodb"]="configured"
      HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
      # Note: Can't directly ping Atlas from a bash script without mongosh
      log_info "  (Use mongosh to verify connectivity)"
    fi
  else
    log_warn "  No .env file or MONGODB_URI not found"
    RESULTS["mongodb"]="not_configured"
    UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# Wait mode
# ---------------------------------------------------------------------------
wait_for_healthy() {
  log_header "Waiting for All Services (timeout: ${WAIT_TIMEOUT}s)"

  local elapsed=0
  local interval=10

  while [[ $elapsed -lt $WAIT_TIMEOUT ]]; do
    # Reset counters
    TOTAL_CHECKS=0
    HEALTHY_COUNT=0
    UNHEALTHY_COUNT=0
    RESULTS=()

    # Silent checks
    for service_name in "${!INFRA_SERVICES[@]}"; do
      local port="${INFRA_SERVICES[$service_name]}"
      TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
      if check_port "$port"; then
        HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
      else
        UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))
      fi
    done

    if [[ $UNHEALTHY_COUNT -eq 0 ]]; then
      log_success "All services healthy! (${elapsed}s elapsed)"
      return 0
    fi

    log_info "  ${HEALTHY_COUNT}/${TOTAL_CHECKS} healthy — waiting... (${elapsed}s / ${WAIT_TIMEOUT}s)"
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  log_fail "Timeout reached: ${UNHEALTHY_COUNT} services still unhealthy"
  return 1
}

# ---------------------------------------------------------------------------
# JSON output
# ---------------------------------------------------------------------------
output_json() {
  echo "{"
  echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"total\": $TOTAL_CHECKS,"
  echo "  \"healthy\": $HEALTHY_COUNT,"
  echo "  \"unhealthy\": $UNHEALTHY_COUNT,"
  echo "  \"services\": {"

  local first=true
  for service_name in "${!RESULTS[@]}"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      echo ","
    fi
    echo -n "    \"$service_name\": \"${RESULTS[$service_name]}\""
  done

  echo ""
  echo "  }"
  echo "}"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
  if [[ "$JSON_OUTPUT" == true ]]; then
    output_json
    return
  fi

  log_header "Health Check Summary"

  local overall_status="${GREEN}HEALTHY${NC}"
  if [[ $UNHEALTHY_COUNT -gt 0 ]]; then
    overall_status="${RED}DEGRADED${NC}"
  fi

  echo -e "  ${BOLD}Status:${NC}     $overall_status"
  echo -e "  ${BOLD}Total:${NC}      $TOTAL_CHECKS checks"
  echo -e "  ${GREEN}Healthy:${NC}    $HEALTHY_COUNT"
  echo -e "  ${RED}Unhealthy:${NC}  $UNHEALTHY_COUNT"
  echo ""

  if [[ $UNHEALTHY_COUNT -gt 0 ]]; then
    echo -e "  ${BOLD}Unhealthy services:${NC}"
    for service_name in "${!RESULTS[@]}"; do
      if [[ "${RESULTS[$service_name]}" != "healthy" && "${RESULTS[$service_name]}" != "configured" ]]; then
        echo -e "    ${RED}✗${NC} $service_name (${RESULTS[$service_name]})"
      fi
    done
    echo ""
    echo -e "  ${BOLD}Troubleshooting:${NC}"
    echo "    1. Start infrastructure:  ./scripts/dev.sh --infra-only"
    echo "    2. Check Docker logs:     docker compose -f docker/docker-compose.yml logs <service>"
    echo "    3. Start app services:    ./scripts/dev.sh --services-only"
    echo "    4. Check service logs:    tail -f .logs/<service>.log"
  fi

  echo ""

  if [[ $UNHEALTHY_COUNT -gt 0 ]]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  if [[ "$JSON_OUTPUT" != true ]]; then
    echo ""
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║   Job Market Intelligence — Health Check                  ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
  fi

  if [[ "$WAIT_MODE" == true ]]; then
    wait_for_healthy
    exit $?
  fi

  case "$CHECK_MODE" in
    infra)
      check_infrastructure
      check_mongodb
      ;;
    services)
      check_app_services
      ;;
    all)
      check_infrastructure
      check_mongodb
      check_app_services
      ;;
  esac

  print_summary
}

main "$@"