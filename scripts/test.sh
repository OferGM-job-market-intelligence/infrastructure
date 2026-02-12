#!/usr/bin/env bash
# =============================================================================
# test.sh — Run tests across all services
# =============================================================================
# Usage:
#   ./scripts/test.sh                      # Run all tests
#   ./scripts/test.sh --service nlp-service # Test a single service
#   ./scripts/test.sh --coverage            # Run tests with coverage reports
#   ./scripts/test.sh --watch               # Run tests in watch mode (Bun services)
#   ./scripts/test.sh --unit                # Unit tests only (skip integration)
#   ./scripts/test.sh --integration         # Integration tests only
#   ./scripts/test.sh --help                # Show help
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"

# Services with their test commands
declare -A TEST_CMD=(
  ["shared"]="bun test"
  ["scraper-service"]="bun test"
  ["nlp-service"]="python -m pytest"
  ["aggregation-service"]="go test ./..."
  ["auth-service"]="go test ./..."
  ["api-gateway"]="bun test"
  ["frontend"]="bun test"
)

# Coverage-enabled test commands
declare -A COVERAGE_CMD=(
  ["shared"]="bun test --coverage"
  ["scraper-service"]="bun test --coverage"
  ["nlp-service"]="python -m pytest --cov=src --cov-report=html --cov-report=term"
  ["aggregation-service"]="go test -coverprofile=coverage.out ./... && go tool cover -html=coverage.out -o coverage.html"
  ["auth-service"]="go test -coverprofile=coverage.out ./... && go tool cover -html=coverage.out -o coverage.html"
  ["api-gateway"]="bun test --coverage"
  ["frontend"]="bun test --coverage"
)

# Watch mode commands (only Bun services support this easily)
declare -A WATCH_CMD=(
  ["shared"]="bun test --watch"
  ["scraper-service"]="bun test --watch"
  ["nlp-service"]="python -m pytest-watch"
  ["api-gateway"]="bun test --watch"
  ["frontend"]="bun test --watch"
)

# Service language type
declare -A SERVICE_LANG=(
  ["shared"]="bun"
  ["scraper-service"]="bun"
  ["api-gateway"]="bun"
  ["frontend"]="bun"
  ["nlp-service"]="python"
  ["aggregation-service"]="go"
  ["auth-service"]="go"
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
log_success() { echo -e "${GREEN}[PASS]${NC}  $*"; }
log_fail()    { echo -e "${RED}[FAIL]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_header()  { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
SINGLE_SERVICE=""
COVERAGE=false
WATCH=false
TEST_TYPE="all"   # all | unit | integration

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)        SINGLE_SERVICE="$2";  shift 2 ;;
    --coverage)       COVERAGE=true;        shift ;;
    --watch)          WATCH=true;           shift ;;
    --unit)           TEST_TYPE="unit";     shift ;;
    --integration)    TEST_TYPE="integration"; shift ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --service <name>      Test a single service"
      echo "  --coverage            Generate coverage reports"
      echo "  --watch               Run in watch mode"
      echo "  --unit                Unit tests only"
      echo "  --integration         Integration tests only"
      echo "  --help, -h            Show this help"
      echo ""
      echo "Services: ${!TEST_CMD[*]}"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------
TOTAL_SERVICES=0
PASSED_SERVICES=0
FAILED_SERVICES=0
SKIPPED_SERVICES=0
declare -a FAILED_LIST=()

run_tests_for_service() {
  local service_name="$1"
  local service_dir="$WORKSPACE_DIR/$service_name"
  local lang="${SERVICE_LANG[$service_name]:-}"

  TOTAL_SERVICES=$((TOTAL_SERVICES + 1))

  if [[ ! -d "$service_dir" ]]; then
    log_warn "$service_name directory not found — skipping"
    SKIPPED_SERVICES=$((SKIPPED_SERVICES + 1))
    return 0
  fi

  # Check if test infrastructure exists
  local has_tests=false
  case "$lang" in
    bun)
      # Check for test files or test directory
      if find "$service_dir" -name "*.test.ts" -o -name "*.test.js" -o -name "*.spec.ts" -o -name "*.spec.js" 2>/dev/null | head -1 | grep -q .; then
        has_tests=true
      elif [[ -d "$service_dir/__tests__" ]] || [[ -d "$service_dir/tests" ]] || [[ -d "$service_dir/test" ]]; then
        has_tests=true
      fi
      ;;
    python)
      if find "$service_dir" -name "test_*.py" -o -name "*_test.py" 2>/dev/null | head -1 | grep -q .; then
        has_tests=true
      elif [[ -d "$service_dir/tests" ]]; then
        has_tests=true
      fi
      ;;
    go)
      if find "$service_dir" -name "*_test.go" 2>/dev/null | head -1 | grep -q .; then
        has_tests=true
      fi
      ;;
  esac

  if [[ "$has_tests" == false ]]; then
    log_warn "$service_name has no test files — skipping"
    SKIPPED_SERVICES=$((SKIPPED_SERVICES + 1))
    return 0
  fi

  # Determine command based on flags
  local cmd=""
  if [[ "$WATCH" == true ]] && [[ -n "${WATCH_CMD[$service_name]:-}" ]]; then
    cmd="${WATCH_CMD[$service_name]}"
  elif [[ "$COVERAGE" == true ]]; then
    cmd="${COVERAGE_CMD[$service_name]}"
  else
    cmd="${TEST_CMD[$service_name]}"
  fi

  # Add test type filters
  case "$TEST_TYPE" in
    unit)
      case "$lang" in
        bun)    cmd="$cmd --grep 'unit'" ;;
        python) cmd="$cmd -m unit" ;;
        go)     cmd="$cmd -run 'TestUnit'" ;;
      esac
      ;;
    integration)
      case "$lang" in
        bun)    cmd="$cmd --grep 'integration'" ;;
        python) cmd="$cmd -m integration" ;;
        go)     cmd="$cmd -run 'TestIntegration'" ;;
      esac
      ;;
  esac

  # Activate Python venv if needed
  local pre_cmd=""
  local post_cmd=""
  if [[ "$lang" == "python" ]] && [[ -d "$service_dir/.venv" ]]; then
    pre_cmd="source $service_dir/.venv/bin/activate &&"
    post_cmd="&& deactivate"
  fi

  log_info "Testing $service_name ($lang)..."
  echo -e "  ${CYAN}Command: $cmd${NC}"
  echo ""

  # Run tests
  local start_time
  start_time=$(date +%s)

  if (cd "$service_dir" && eval "$pre_cmd $cmd $post_cmd"); then
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_success "$service_name — all tests passed (${duration}s)"
    PASSED_SERVICES=$((PASSED_SERVICES + 1))
  else
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_fail "$service_name — tests failed (${duration}s)"
    FAILED_SERVICES=$((FAILED_SERVICES + 1))
    FAILED_LIST+=("$service_name")
  fi

  echo ""
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
  log_header "Test Summary"

  echo -e "  ${BOLD}Total:${NC}    $TOTAL_SERVICES services"
  echo -e "  ${GREEN}Passed:${NC}   $PASSED_SERVICES"
  echo -e "  ${RED}Failed:${NC}   $FAILED_SERVICES"
  echo -e "  ${YELLOW}Skipped:${NC}  $SKIPPED_SERVICES"

  if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${RED}${BOLD}Failed services:${NC}"
    for svc in "${FAILED_LIST[@]}"; do
      echo -e "    ${RED}✗${NC} $svc"
    done
  fi

  if [[ "$COVERAGE" == true ]]; then
    echo ""
    echo -e "  ${BOLD}Coverage reports:${NC}"
    for service_name in "${!SERVICE_LANG[@]}"; do
      local service_dir="$WORKSPACE_DIR/$service_name"
      local lang="${SERVICE_LANG[$service_name]}"
      case "$lang" in
        go)
          [[ -f "$service_dir/coverage.html" ]] && echo "    $service_name: $service_dir/coverage.html"
          ;;
        python)
          [[ -d "$service_dir/htmlcov" ]] && echo "    $service_name: $service_dir/htmlcov/index.html"
          ;;
        bun)
          echo "    $service_name: see terminal output above"
          ;;
      esac
    done
  fi

  echo ""

  # Exit with failure if any service failed
  if [[ $FAILED_SERVICES -gt 0 ]]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo ""
  echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   Job Market Intelligence — Test Runner                   ║${NC}"
  echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  local flags=""
  [[ "$COVERAGE" == true ]] && flags+="coverage "
  [[ "$WATCH" == true ]] && flags+="watch "
  [[ "$TEST_TYPE" != "all" ]] && flags+="$TEST_TYPE "
  [[ -n "$SINGLE_SERVICE" ]] && flags+="service=$SINGLE_SERVICE "
  [[ -n "$flags" ]] && log_info "Flags: $flags"

  if [[ -n "$SINGLE_SERVICE" ]]; then
    run_tests_for_service "$SINGLE_SERVICE"
  else
    for service_name in "${!TEST_CMD[@]}"; do
      run_tests_for_service "$service_name"
    done
  fi

  print_summary
}

main "$@"