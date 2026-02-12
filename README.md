# Infrastructure

Infrastructure as Code for Job Market Intelligence Platform

## 📁 Structure
```
infrastructure/
├── docker/                  # Docker Compose for local development
│   └── docker-compose.yml   # Infrastructure services
├── kubernetes/              # Kubernetes manifests (Week 13)
├── terraform/               # Infrastructure as Code (Week 15)
├── helm/                    # Helm charts (Week 15)
├── scripts/                 # Automation scripts
└── docs/                    # Operational documentation
```

## 🚀 Quick Start

### Prerequisites

- **Docker Desktop** (v4.0+) - [Download](https://www.docker.com/products/docker-desktop)
- **Docker Compose** (v2.0+) - Included with Docker Desktop
- Minimum **8GB RAM** allocated to Docker
- Minimum **20GB** free disk space

### Installation

1. **Clone the repository** (if not already done):
```bash
git clone https://github.com/OferGM-job-market-intelligence/infrastructure.git
cd infrastructure
```

2. **Create environment file**:
```bash
cp docker/.env.example docker/.env
```

3. **Edit `.env` file** with your configurations:
```bash
# Required: Update MongoDB URI with your Atlas connection string
nano docker/.env
```

4. **Start all services**:
```bash
docker-compose -f docker/docker-compose.yml up -d
```

5. **Verify services are healthy**:
```bash
docker-compose -f docker/docker-compose.yml ps
```

Expected output:
```
NAME            IMAGE                              STATUS         PORTS
elasticsearch   docker.elastic.co/elasticsearch... Up (healthy)   0.0.0.0:9200->9200/tcp, 9300/tcp
kafka           confluentinc/cp-kafka:7.5.0        Up (healthy)   0.0.0.0:9092->9092/tcp, 0.0.0.0:29092->29092/tcp
kibana          docker.elastic.co/kibana...        Up (healthy)   0.0.0.0:5601->5601/tcp
localstack      localstack/localstack:3.0          Up (healthy)   0.0.0.0:4566->4566/tcp
redis           redis:7.2-alpine                   Up (healthy)   0.0.0.0:6380->6380/tcp
zookeeper       confluentinc/cp-zookeeper:7.5.0    Up (healthy)   0.0.0.0:2181->2181/tcp
```

## 🛠️ Service Details

| Service | Port | Description | UI/Access |
|---------|------|-------------|-----------|
| **Zookeeper** | 2181 | Kafka coordination | CLI only |
| **Kafka** | 9092, 29092 | Event streaming | CLI only |
| **Redis** | 6380 | Cache & sessions | CLI: `redis-cli` |
| **Elasticsearch** | 9200, 9300 | Search & logging | http://localhost:9200 |
| **Kibana** | 5601 | Log visualization | http://localhost:5601 |
| **LocalStack** | 4566 | AWS S3 simulation | http://localhost:4566 |

## 📊 Common Operations

### View Logs

**All services**:
```bash
docker-compose -f docker/docker-compose.yml logs -f
```

**Specific service**:
```bash
docker-compose -f docker/docker-compose.yml logs -f kafka
```

**Last 100 lines**:
```bash
docker-compose -f docker/docker-compose.yml logs --tail=100 elasticsearch
```

### Check Service Health
```bash
# All services
docker-compose -f docker/docker-compose.yml ps

# Specific service
docker inspect kafka --format='{{.State.Health.Status}}'
```

### Restart Services

**Restart all**:
```bash
docker-compose -f docker/docker-compose.yml restart
```

**Restart specific service**:
```bash
docker-compose -f docker/docker-compose.yml restart kafka
```

### Stop Services

**Stop all (preserves data)**:
```bash
docker-compose -f docker/docker-compose.yml stop
```

**Stop specific service**:
```bash
docker-compose -f docker/docker-compose.yml stop elasticsearch
```

### Shutdown & Cleanup

**Stop and remove containers (preserves volumes)**:
```bash
docker-compose -f docker/docker-compose.yml down
```

**Complete cleanup (⚠️ DELETES ALL DATA)**:
```bash
docker-compose -f docker/docker-compose.yml down -v
```

### Start After Shutdown
```bash
docker-compose -f docker/docker-compose.yml up -d
```

## 🔍 Testing Connections

### Test Redis
```bash
# Using redis-cli
docker exec -it redis redis-cli ping
# Expected: PONG

# Set and get a key
docker exec -it redis redis-cli SET test "Hello World"
docker exec -it redis redis-cli GET test
# Expected: "Hello World"
```

### Test Kafka

**List topics**:
```bash
docker exec -it kafka kafka-topics --list --bootstrap-server localhost:29092
```

**Create test topic**:
```bash
docker exec -it kafka kafka-topics --create \
  --topic test-topic \
  --bootstrap-server localhost:29092 \
  --partitions 1 \
  --replication-factor 1
```

**Produce test message**:
```bash
echo "Hello Kafka" | docker exec -i kafka kafka-console-producer \
  --topic test-topic \
  --bootstrap-server localhost:29092
```

**Consume test message**:
```bash
docker exec -it kafka kafka-console-consumer \
  --topic test-topic \
  --from-beginning \
  --bootstrap-server localhost:29092 \
  --max-messages 1
```

### Test Elasticsearch
```bash
# Health check
curl http://localhost:9200/_cluster/health?pretty

# Index a test document
curl -X POST "http://localhost:9200/test-index/_doc" \
  -H 'Content-Type: application/json' \
  -d '{"message": "Hello Elasticsearch", "timestamp": "2026-02-06"}'

# Search for document
curl "http://localhost:9200/test-index/_search?pretty"
```

### Test LocalStack (S3)
```bash
# Install AWS CLI if needed
pip install awscli-local

# Create test bucket
awslocal s3 mb s3://test-bucket

# Upload test file
echo "Hello S3" > test.txt
awslocal s3 cp test.txt s3://test-bucket/

# List bucket contents
awslocal s3 ls s3://test-bucket/

# Download file
awslocal s3 cp s3://test-bucket/test.txt downloaded.txt
cat downloaded.txt
```

## 🐛 Troubleshooting

### Services Won't Start

**Check Docker resources**:
```bash
docker system df
docker system info | grep -i memory
```

**Increase Docker memory**:
- Docker Desktop → Settings → Resources → Memory → Set to 8GB

### Port Already in Use

Find and kill the process:
```bash
# On Mac/Linux
lsof -ti:9200 | xargs kill -9

# On Windows (PowerShell)
Get-Process -Id (Get-NetTCPConnection -LocalPort 9200).OwningProcess | Stop-Process
```

### Kafka Won't Connect

**Check Zookeeper is healthy**:
```bash
docker-compose -f docker/docker-compose.yml ps zookeeper
```

**Wait for Kafka to fully start** (can take 30-60 seconds):
```bash
docker-compose -f docker/docker-compose.yml logs -f kafka
```

### Elasticsearch "Max virtual memory too low"

**On Mac/Linux**:
```bash
# Increase vm.max_map_count
sudo sysctl -w vm.max_map_count=262144

# Make permanent
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

**On Windows (WSL2)**:
```powershell
# In PowerShell as Administrator
wsl -d docker-desktop
sysctl -w vm.max_map_count=262144
```

### Data Persistence Issues

Verify volumes exist:
```bash
docker volume ls | grep infrastructure
```

Inspect a volume:
```bash
docker volume inspect infrastructure_kafka-data
```

## 📈 Resource Usage

Expected resource consumption with all services running:

- **Memory**: 4-6 GB
- **CPU**: 2-4 cores (during startup, then 1-2 cores)
- **Disk**: ~5 GB (increases with data)

Monitor resources:
```bash
docker stats
```

## 🔗 Service URLs

After starting all services:

- **Kibana UI**: http://localhost:5601
- **Elasticsearch**: http://localhost:9200
- **LocalStack Dashboard**: http://localhost:4566/_localstack/health

## 📚 Next Steps

1. ✅ All services running
2. → Set up MongoDB Atlas (Day 3)
3. → Create shared types (Day 5)
4. → Start building microservices (Week 2+)

## 📖 Additional Documentation

- [Architecture Overview](../.github/docs/architecture-overview.md)
- [90-Day Work Plan](../.github/docs/90-day-detailed-workplan.md)

---

**Status**: Day 2 Complete ✅  
**Services**: 6/6 Running  
**Last Updated**: Day 2 - February 6, 2026