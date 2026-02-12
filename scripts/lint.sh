#!/usr/bin/env bash
# =============================================================================
# lint.sh — Run linters and formatters across all services
# =============================================================================
# Usage:
#   ./scripts/lint.sh                       # Lint all services
#   ./scripts/lint.sh --service auth-service # Lint a single service
#   ./scripts/lint.sh --fix                  # Auto-fix where possible
#   ./scripts/lint.sh --check               # Check only (CI mode, no fixes)
#   ./scripts/lint.sh --help                # Show help
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"

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
FIX_MODE=false
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)    SINGLE_SERVICE="$2";  shift 2 ;;
    --fix)        FIX_MODE=true;        shift ;;
    --check)      CHECK_ONLY=true;      shift ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --service <n>      Lint a single service"
      echo "  --fix                 Auto-fix issues where possible"
      echo "  --check               Check only mode (for CI)"
      echo "  --help, -h            Show this help"
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
# Lint functions per language
# ---------------------------------------------------------------------------
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
declare -a FAILED_LIST=()

lint_bun_service() {
  local service_dir="$1"
  local service_name="$(basename "$service_dir")"

  TOTAL=$((TOTAL + 1))

  if [[ ! -f "$service_dir/package.json" ]]; then
    log_warn "$service_name has no package.json — skipping"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  log_info "Linting $service_name (TypeScript)..."
  local exit_code=0

  # TypeScript type checking
  if [[ -f "$service_dir/tsconfig.json" ]]; then
    log_info "  Running tsc --noEmit..."
    if (cd "$service_dir" && npx tsc --noEmit 2>&1); then
      log_success "  TypeScript type check passed"
    else
      log_fail "  TypeScript type check failed"
      exit_code=1
    fi
  fi

  # ESLint (if configured)
  if [[ -f "$service_dir/.eslintrc.js" ]] || [[ -f "$service_dir/.eslintrc.json" ]] || \
     [[ -f "$service_dir/.eslintrc.cjs" ]] || [[ -f "$service_dir/eslint.config.js" ]] || \
     [[ -f "$service_dir/eslint.config.mjs" ]]; then
    local eslint_cmd="npx eslint . --ext .ts,.tsx,.js,.jsx"
    if [[ "$FIX_MODE" == true ]]; then
      eslint_cmd="$eslint_cmd --fix"
    fi

    log_info "  Running ESLint..."
    if (cd "$service_dir" && eval "$eslint_cmd" 2>&1); then
      log_success "  ESLint passed"
    else
      log_fail "  ESLint failed"
      exit_code=1
    fi
  else
    log_info "  No ESLint config found — skipping ESLint"
  fi

  # Prettier (if configured)
  if [[ -f "$service_dir/.prettierrc" ]] || [[ -f "$service_dir/.prettierrc.json" ]] || \
     [[ -f "$service_dir/prettier.config.js" ]]; then
    local prettier_cmd="npx prettier --check ."
    if [[ "$FIX_MODE" == true ]]; then
      prettier_cmd="npx prettier --write ."
    fi

    log_info "  Running Prettier..."
    if (cd "$service_dir" && eval "$prettier_cmd" 2>&1); then
      log_success "  Prettier passed"
    else
      if [[ "$FIX_MODE" == true ]]; then
        log_success "  Prettier formatted files"
      else
        log_fail "  Prettier found formatting issues (run with --fix)"
        exit_code=1
      fi
    fi
  fi

  if [[ $exit_code -eq 0 ]]; then
    log_success "$service_name lint passed"
    PASSED=$((PASSED + 1))
  else
    log_fail "$service_name lint failed"
    FAILED=$((FAILED + 1))
    FAILED_LIST+=("$service_name")
  fi
}

lint_python_service() {
  local service_dir="$1"
  local service_name="$(basename "$service_dir")"

  TOTAL=$((TOTAL + 1))

  log_info "Linting $service_name (Python)..."
  local exit_code=0

  # Activate venv if available
  local activate=""
  local deactivate_cmd=""
  if [[ -d "$service_dir/.venv" ]]; then
    activate="source $service_dir/.venv/bin/activate &&"
    deactivate_cmd="&& deactivate"
  fi

  # Ruff (fast Python linter, replaces flake8 + isort + some pylint)
  if command -v ruff &>/dev/null || [[ -d "$service_dir/.venv" ]]; then
    local ruff_cmd="ruff check ."
    if [[ "$FIX_MODE" == true ]]; then
      ruff_cmd="ruff check --fix . && ruff format ."
    fi

    log_info "  Running Ruff..."
    if (cd "$service_dir" && eval "$activate $ruff_cmd $deactivate_cmd" 2>&1); then
      log_success "  Ruff passed"
    else
      log_fail "  Ruff found issues"
      exit_code=1
    fi
  fi

  # MyPy type checking (if configured)
  if [[ -f "$service_dir/mypy.ini" ]] || [[ -f "$service_dir/pyproject.toml" ]]; then
    log_info "  Running MyPy..."
    if (cd "$service_dir" && eval "$activate python -m mypy src/ $deactivate_cmd" 2>&1); then
      log_success "  MyPy passed"
    else
      log_fail "  MyPy found type errors"
      exit_code=1
    fi
  fi

  # Black formatting check (if configured, fallback if Ruff not present)
  if [[ -f "$service_dir/pyproject.toml" ]] && grep -q "black" "$service_dir/pyproject.toml" 2>/dev/null; then
    local black_cmd="black --check ."
    if [[ "$FIX_MODE" == true ]]; then
      black_cmd="black ."
    fi

    log_info "  Running Black..."
    if (cd "$service_dir" && eval "$activate $black_cmd $deactivate_cmd" 2>&1); then
      log_success "  Black passed"
    else
      log_fail "  Black found formatting issues"
      exit_code=1
    fi
  fi

  if [[ $exit_code -eq 0 ]]; then
    log_success "$service_name lint passed"
    PASSED=$((PASSED + 1))
  else
    log_fail "$service_name lint failed"
    FAILED=$((FAILED + 1))
    FAILED_LIST+=("$service_name")
  fi
}

lint_go_service() {
  local service_dir="$1"
  local service_name="$(basename "$service_dir")"

  TOTAL=$((TOTAL + 1))

  if [[ ! -f "$service_dir/go.mod" ]]; then
    log_warn "$service_name has no go.mod — skipping"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  log_info "Linting $service_name (Go)..."
  local exit_code=0

  # go vet (built-in static analysis)
  log_info "  Running go vet..."
  if (cd "$service_dir" && go vet ./... 2>&1); then
    log_success "  go vet passed"
  else
    log_fail "  go vet found issues"
    exit_code=1
  fi

  # gofmt check
  log_info "  Running gofmt..."
  local unformatted
  unformatted=$(cd "$service_dir" && gofmt -l . 2>/dev/null || echo "")
  if [[ -z "$unformatted" ]]; then
    log_success "  gofmt passed"
  else
    if [[ "$FIX_MODE" == true ]]; then
      (cd "$service_dir" && gofmt -w .)
      log_success "  gofmt formatted files"
    else
      log_fail "  gofmt: unformatted files:"
      echo "$unformatted" | while read -r file; do echo "    $file"; done
      exit_code=1
    fi
  fi

  # golangci-lint (comprehensive linter, if installed)
  if command -v golangci-lint &>/dev/null; then
    local golint_cmd="golangci-lint run"
    if [[ "$FIX_MODE" == true ]]; then
      golint_cmd="golangci-lint run --fix"
    fi

    log_info "  Running golangci-lint..."
    if (cd "$service_dir" && eval "$golint_cmd" 2>&1); then
      log_success "  golangci-lint passed"
    else
      log_fail "  golangci-lint found issues"
      exit_code=1
    fi
  else
    log_info "  golangci-lint not installed — skipping (install: https://golangci-lint.run/)"
  fi

  # go mod tidy check
  log_info "  Checking go.mod tidiness..."
  if (cd "$service_dir" && go mod tidy -diff 2>&1 | head -5); then
    log_success "  go.mod is tidy"
  else
    if [[ "$FIX_MODE" == true ]]; then
      (cd "$service_dir" && go mod tidy)
      log_success "  go.mod tidied"
    else
      log_fail "  go.mod needs tidying (run with --fix)"
      exit_code=1
    fi
  fi

  if [[ $exit_code -eq 0 ]]; then
    log_success "$service_name lint passed"
    PASSED=$((PASSED + 1))
  else
    log_fail "$service_name lint failed"
    FAILED=$((FAILED + 1))
    FAILED_LIST+=("$service_name")
  fi
}

# ---------------------------------------------------------------------------
# Lint dispatcher
# ---------------------------------------------------------------------------
lint_service() {
  local service_name="$1"
  local service_dir="$WORKSPACE_DIR/$service_name"
  local lang="${SERVICE_LANG[$service_name]:-}"

  if [[ ! -d "$service_dir" ]]; then
    log_warn "$service_name directory not found — skipping"
    SKIPPED=$((SKIPPED + 1))
    TOTAL=$((TOTAL + 1))
    return 0
  fi

  case "$lang" in
    bun)    lint_bun_service "$service_dir" ;;
    python) lint_python_service "$service_dir" ;;
    go)     lint_go_service "$service_dir" ;;
    *)      log_warn "Unknown language for $service_name"; SKIPPED=$((SKIPPED + 1)); TOTAL=$((TOTAL + 1)) ;;
  esac

  echo ""
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
  log_header "Lint Summary"

  echo -e "  ${BOLD}Total:${NC}    $TOTAL services"
  echo -e "  ${GREEN}Passed:${NC}   $PASSED"
  echo -e "  ${RED}Failed:${NC}   $FAILED"
  echo -e "  ${YELLOW}Skipped:${NC}  $SKIPPED"

  if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${RED}${BOLD}Failed services:${NC}"
    for svc in "${FAILED_LIST[@]}"; do
      echo -e "    ${RED}✗${NC} $svc"
    done
    echo ""
    echo -e "  Tip: Run with ${CYAN}--fix${NC} to auto-fix where possible"
  fi

  echo ""

  if [[ $FAILED -gt 0 ]]; then
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
  echo -e "${BOLD}${CYAN}║   Job Market Intelligence — Lint Runner                   ║${NC}"
  echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  local mode_label="check"
  [[ "$FIX_MODE" == true ]] && mode_label="fix"
  [[ "$CHECK_ONLY" == true ]] && mode_label="check (CI)"
  log_info "Mode: $mode_label"
  echo ""

  if [[ -n "$SINGLE_SERVICE" ]]; then
    lint_service "$SINGLE_SERVICE"
  else
    for service_name in "${!SERVICE_LANG[@]}"; do
      lint_service "$service_name"
    done
  fi

  print_summary
}

main "$@"