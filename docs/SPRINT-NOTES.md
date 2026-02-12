# Sprint Notes

Weekly summaries and reflections.

## Week 1: Foundation (Days 1-7) ✅ Complete

### Goals
- Set up organization and repository structure
- Configure local development infrastructure
- Create shared types and documentation
- Establish development workflow

### Daily Notes

---

#### Day 1: Multi-Repo Setup ✅
**Completed**:
- Created GitHub organization with 9 repositories
- Initialized hybrid documentation structure
- Set up organization profile
**Time**: 3 hours
**Blockers**: None
**Next**: Docker Compose infrastructure

---

#### Day 2: Docker Compose Infrastructure ✅
**Completed**:
- Created comprehensive docker-compose.yml with 6 services
- All services running with health checks
- Resolved LocalStack Windows/WSL2 issue
**Time**: 2.5 hours
**Decisions**: LocalStack in-memory storage for Windows compatibility
**Blockers**: LocalStack volume issue (resolved)
**Next**: MongoDB Atlas setup

---

#### Day 3 + 4: MongoDB Atlas Setup & Testing ✅
**Completed**:
- Created MongoDB Atlas account and M0 cluster
- Configured database with 4 collections
- Implemented comprehensive schema validation
- Created 20+ performance indexes
- Inserted and validated test data across all collections
- Tested queries and verified index performance

**Time**: 2 hours (combined)

**Why Days 3 & 4 Combined**:
The original plan separated MongoDB setup (Day 3) from testing (Day 4), but I completed both comprehensively in one session:
- **Day 3 tasks**: Account, cluster, collections, schema validation ✅
- **Day 4 tasks**: Indexes, test data, query testing, performance validation ✅
- **Efficiency gain**: No context switching, completed end-to-end

**Decisions Made**:

1. **Free Tier M0 Cluster** (512MB)
   - **Why**: Zero cost, sufficient for development
   - **Trade-off**: Limited connections (100 concurrent), no backups
   - **Impact**: Perfect for portfolio project

2. **Schema Validation at Database Level**
   - **Why**: Data integrity safety net beyond application logic
   - **Implementation**: JSON Schema validation on all collections

3. **IP Whitelist: 0.0.0.0/0** (All IPs)
   - **Why**: Simplifies development (dynamic IPs, Docker containers)
   - **Mitigation**: Strong password, will restrict in production

4. **Comprehensive Index Strategy**
   - **Result**: ~20+ indexes optimized for read-heavy workload
   - **Trade-off**: Slightly slower writes (acceptable for this use case)

5. **Test Data Strategy**
   - **Minimal but representative**: 3 users, 5 skills, 3 jobs, 4 trends

**Next**: Day 5 - Shared Types Repository

---

#### Day 5: Shared Types Repository ✅
**Completed**:
- Created comprehensive TypeScript type definitions for all 5 services
- Built validation and formatting utility libraries
- Established shared constants for cross-service configuration
- Full package setup with exports map and strict tsconfig

**Time**: 3 hours
**Blockers**: None

**What Was Built**:

**Type Definitions (4 files)**:
- `types/job.ts` — 10 types/interfaces covering job postings, search, and statistics
- `types/skill.ts` — 12 types/interfaces for skill taxonomy and trend analysis
- `types/user.ts` — 14 types/interfaces for auth and user management
- `types/analytics.ts` — 10 types/interfaces for market analytics

**Constants (`data/constants.ts`)**: Rate limits, JWT expiry, cache TTLs, Kafka topics, Redis keys, password requirements, HTTP status codes, error codes, service ports

**Validators (`utils/validators.ts`)**: 13 functions — email, password, URL, job ID, salary range, date range, pagination, ObjectId, etc.

**Formatters (`utils/formatters.ts`)**: 17 functions — salary, date, relative time, number, percentage, location, experience level, job source, skill name, trend direction

**Decisions Made**:

1. **String Literal Unions over TypeScript Enums**
   - Better tree-shaking, simpler serialization, works naturally with JSON/MongoDB

2. **Comprehensive Utility Libraries from Day 1**
   - Prevents duplicate implementations across 5 services

3. **Strict TypeScript Configuration**
   - `noUnusedLocals`, `noUnusedParameters`, `noImplicitReturns`, `noUncheckedIndexedAccess`

4. **Exports Map in package.json**
   - Enables tree-shaking and direct module imports

**Next**: Day 6 - Skill Taxonomy Data

---

#### Day 6: Skill Taxonomy Data ✅
**Completed**:
- Created comprehensive skill taxonomy JSON with 503 skills
- Covered all 9 categories, exceeding all count targets
- Updated shared types and constants to include new `testing` category
- Every skill includes canonical name, aliases, category, and related skills

**Time**: 3 hours
**Blockers**: None

**Category Breakdown**:
```
framework:            106 skills (target: 100+)  ✅
other:                102 skills
ml_library:            53 skills (target: 50+)   ✅
devops_tool:           52 skills (target: 50+)   ✅
soft_skill:            52 skills (target: 50+)   ✅
programming_language:  50 skills (target: 50+)   ✅
database:              32 skills (target: 30+)   ✅
testing:               31 skills (target: 20+)   ✅
cloud_platform:        25 skills (target: 20+)   ✅
```

**Decisions Made**:

1. **Flat JSON Structure (Not Nested by Category)** — Simpler to iterate, filter, search
2. **Canonical Names as Primary Keys** — Human-readable, consistent with MongoDB `skill_id`
3. **Generous Alias Coverage** — Average ~2.9 aliases per skill for high NLP accuracy
4. **Added `testing` Category** — Split from devops/other, deserves first-class treatment
5. **Related Skills Are Directional** — 3-7 per entry for "if you know X, consider Y" recommendations

**Next**: Day 7 - Scripts & Automation

---

#### Day 7: Scripts & Automation ✅
**Completed**:
- Created 5 bash scripts for full development workflow automation
- Created Makefile with 40+ commands as the primary developer interface
- All scripts pass bash syntax validation
- Designed for WSL2 on Windows (primary dev environment)
- Resolved WSL2 crash during testing

**Time**: 2.5 hours
**Blockers**: WSL2 crashed during `install.sh` testing (resolved with `wsl --shutdown`)

**What Was Built**:

**`scripts/install.sh`**:
- Checks prerequisites: git, docker, bun, python3, go, make
- Reports versions and missing tools with install instructions
- Clones all 9 repos from GitHub org (or `--skip-clone` to pull existing)
- Installs dependencies per language:
  - Bun services: `bun install` (shared, scraper-service, api-gateway, frontend)
  - Python services: creates `.venv`, `pip install -r requirements.txt` (nlp-service)
  - Go services: `go mod download && go mod verify` (aggregation-service, auth-service)
- Creates `.env` files from `.env.example` templates
- Prints summary with install status per service

**`scripts/dev.sh`**:
- `--infra-only`: Starts Docker containers with health-wait polling
- `--services-only`: Starts application services with PID tracking
- Default: starts both infrastructure and services
- Logs captured to `.logs/<service>.log`
- PIDs tracked in `.pids/<service>.pid`
- `--stop`: Graceful shutdown with SIGTERM, falls back to SIGKILL after 10s
- `--service <name>`: Start a single service
- Status display shows all services with port/PID/status

**`scripts/test.sh`**:
- Runs tests across all services, detects test files per language
- `--coverage`: Generates coverage reports (bun coverage, pytest-cov, go cover)
- `--watch`: Watch mode for iterative development
- `--unit` / `--integration`: Filter by test type
- `--service <name>`: Test single service
- Summary with pass/fail/skip counts and timing
- Returns proper exit code for CI

**`scripts/lint.sh`**:
- **Bun/TypeScript**: tsc --noEmit, ESLint, Prettier
- **Python**: Ruff (replaces flake8+isort), MyPy, Black
- **Go**: go vet, gofmt, golangci-lint, go mod tidy
- `--fix`: Auto-fix where possible (Prettier write, Ruff fix, gofmt -w, go mod tidy)
- `--check`: CI mode (no modifications)
- `--service <name>`: Lint single service

**`scripts/health-check.sh`**:
- **Infrastructure**: Docker container state, port checks, HTTP health endpoints
  - Redis: `redis-cli ping` via docker exec
  - Elasticsearch: `/_cluster/health` endpoint
  - Kibana: `/api/status` endpoint
  - LocalStack: `/_localstack/health` endpoint
  - Kafka/Zookeeper: port checks
- **MongoDB Atlas**: Checks if `MONGODB_URI` is configured in `.env`
- **Application services**: PID file check, port check, `/health` endpoint
- `--json`: Machine-readable output for CI/monitoring
- `--wait`: Poll until all healthy (configurable timeout, default 180s)
- `--infra` / `--services`: Check specific layer only

**`Makefile`**:
- **Setup**: `install`, `install-skip-clone`, `setup-env`
- **Development**: `dev`, `dev-infra`, `dev-services`, `stop`
- **Docker**: `up`, `down`, `restart`, `logs`, `ps`, `clean`
- **Testing**: `test`, `test-coverage`, `test-watch`, `test-unit`, `test-integration`
- **Linting**: `lint`, `lint-fix`
- **Health**: `health`, `health-infra`, `health-services`, `health-json`, `health-wait`
- **Per-service**: `dev-scraper`, `test-nlp`, `lint-auth`, etc. (18 commands)
- **Utilities**: `status`, `reset`, `deps-update`, `kibana`, `es`, `redis-cli`
- `make help`: Auto-generated command reference from `##` comments

**Decisions Made**:

1. **Bash + Makefile (Not PowerShell)**
   - **Choice**: Keep scripts as bash, run from WSL2
   - **Why**: Bash is the standard for DevOps scripting, portable to CI/CD, Dockerfile, Linux servers
   - **Trade-off**: Requires WSL2 on Windows (already available)
   - **Impact**: Scripts work in GitHub Actions, Docker, and any Linux environment without modification

2. **PID-Based Process Management**
   - **Choice**: Track service PIDs in `.pids/` directory, logs in `.logs/`
   - **Why**: Simple, no external tools needed (vs PM2, supervisord)
   - **Trade-off**: Less robust than a process manager (no auto-restart)
   - **Impact**: `dev.sh --stop` cleanly shuts down all services

3. **Makefile as Primary Interface**
   - **Choice**: Makefile wraps all scripts as short commands
   - **Why**: Universal (`make` is available everywhere), self-documenting with `make help`
   - **Trade-off**: Makefile syntax is arcane, but users only run `make <command>`
   - **Impact**: Developers only need to remember `make dev`, `make test`, `make health`

4. **Language-Aware Tooling**
   - **Choice**: Each script detects Bun/Python/Go and runs appropriate tools
   - **Why**: Polyglot project (3 languages) needs unified interface
   - **Impact**: `make test` runs bun test, pytest, and go test transparently

5. **Graceful Degradation**
   - **Choice**: Missing tools warn but don't block, missing test files skip
   - **Why**: Foundation phase has no source code yet — scripts must handle empty repos
   - **Impact**: Scripts work now (with skips) and will light up as services are built

**Learnings**:

1. **WSL2 + Docker Desktop Can Be Fragile**
   - Docker Desktop's WSL integration can crash the WSL VM
   - Fix: `wsl --shutdown` then restart — works 90% of the time
   - Fallback: `net stop LxssManager && net start LxssManager`
   - Lesson: Always document WSL recovery steps for Windows developers

2. **Scripts Should Validate Before Executing**
   - Checking prerequisites up front saves debugging time
   - Checking for missing files (package.json, go.mod) prevents cryptic errors
   - Color-coded output makes it easy to spot issues at a glance

3. **Automation Pays Off Immediately**
   - Even before services exist, `make health-infra` validates Docker setup
   - `make help` serves as a project onboarding guide
   - Consistent interface across 3 languages reduces cognitive load

**Files Created**:
```
infrastructure/
├── Makefile
└── scripts/
    ├── install.sh              # Dependency installer
    ├── dev.sh                  # Dev server manager
    ├── test.sh                 # Test runner
    ├── lint.sh                 # Lint runner
    └── health-check.sh         # Health checker
```

**Commits**:
```bash
feat(infra): add automation scripts and Makefile

Day 7 Complete: Scripts & Automation ✅ (2.5h)
- install.sh: prerequisite checks, repo cloning, dependency installation
- dev.sh: infrastructure + service startup with PID management
- test.sh: cross-language test runner with coverage/watch modes
- lint.sh: TypeScript/Python/Go linters with auto-fix support
- health-check.sh: infrastructure + service health with JSON output
- Makefile: 40+ commands for common development workflows
- All scripts pass bash syntax validation
- Designed for WSL2 on Windows
```

**Next**: Day 8 - Scraper Service Bun.js project setup

---

### Week 1 Final Summary ✅

**Days Completed**: 7/7 (100%)  
**Total Time Spent**: ~16 hours  
**Pace**: On schedule ✅  
**Phase**: Foundation → Complete 🎉

**What Was Built This Week**:

| Day | Deliverable | Key Metric |
|-----|-------------|------------|
| 1 | GitHub org + 9 repos | 9 repositories |
| 2 | Docker Compose infrastructure | 6 services running |
| 3+4 | MongoDB Atlas + testing | 4 collections, 20+ indexes |
| 5 | Shared TypeScript types | 46+ types, 30+ utilities |
| 6 | Skill taxonomy | 503 skills, 1,441 aliases |
| 7 | Automation scripts | 5 scripts + Makefile (2,277 lines) |

**Foundation Assets Created**:
- ✅ 9 GitHub repositories with documentation
- ✅ 6 Docker infrastructure services (Kafka, Redis, Elasticsearch, Kibana, LocalStack, Zookeeper)
- ✅ MongoDB Atlas cluster with 4 validated collections and 20+ indexes
- ✅ 46+ TypeScript type definitions covering all services
- ✅ 30+ shared utility functions (validators + formatters)
- ✅ 503-skill taxonomy with 1,441 aliases for NLP matching
- ✅ 5 automation scripts + Makefile with 40+ commands
- ✅ Comprehensive documentation (architecture, work plan, decisions, conventions, progress, sprint notes)

**Challenges Overcome**:
1. LocalStack Windows volume issue (Day 2) — solved with in-memory storage
2. WSL2 crash during script testing (Day 7) — solved with `wsl --shutdown`

**Velocity Analysis**:
- Day 1: 3h (on target)
- Day 2: 2.5h (0.5h under estimate)
- Day 3+4: 2h (combined, 2h under estimate)
- Day 5: 3h (on target)
- Day 6: 3h (on target)
- Day 7: 2.5h (on target)
- **Average**: 2.3h per day vs 2-3h estimated
- **Total**: ~16h vs 15-20h budgeted

**Technical Debt**: Zero 🎉

**Key Success Factors**:
1. Comprehensive upfront planning (90-day work plan)
2. Proper documentation at every step
3. Efficient execution (combined Days 3+4)
4. Early shared code (types + taxonomy) — prevents duplication in services
5. Automation from day one — establishes workflow before complexity grows

**What's Next**:
- Week 2: Scraper Service (Bun.js) — Days 8-14
- First real microservice with Kafka integration
- First tests written against shared types

---

**Last Updated**: Day 7 - 12/02/2026  
**Week 1**: ✅ Complete  
**Next Sprint Notes**: Week 2 (Days 8-14) — Scraper Service