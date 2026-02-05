# Infrastructure

Infrastructure as Code for Job Market Intelligence Platform

## 📁 Structure
```
infrastructure/
├── docker/                  # Docker Compose for local development
│   ├── docker-compose.yml
│   └── .env.example
├── kubernetes/              # Kubernetes manifests
│   ├── namespaces/
│   ├── deployments/
│   ├── services/
│   ├── configmaps/
│   ├── secrets/
│   └── statefulsets/
├── terraform/               # Infrastructure as Code
│   ├── localstack/         # AWS LocalStack for local dev
│   ├── modules/            # Reusable modules
│   └── environments/       # Dev, staging, prod
├── helm/                   # Helm charts
│   └── job-market-platform/
└── scripts/                # Automation scripts
```

## 🚀 Quick Start

### Local Development
```bash
# Start all infrastructure services
docker-compose -f docker/docker-compose.yml up -d

# Check status
docker-compose -f docker/docker-compose.yml ps

# View logs
docker-compose -f docker/docker-compose.yml logs -f

# Stop everything
docker-compose -f docker/docker-compose.yml down -v
```

### Kubernetes Deployment
```bash
# Deploy to Minikube
kubectl apply -f kubernetes/namespaces/
kubectl apply -f kubernetes/

# Verify
kubectl get pods -n job-market

# Access services
kubectl port-forward -n job-market svc/api-gateway 4000:4000
```

## 🛠️ Services

| Service | Port | Description |
|---------|------|-------------|
| Kafka | 29092 | Event streaming |
| Zookeeper | 2181 | Kafka coordination |
| Redis | 6379 | Cache & sessions |
| MongoDB | 27017 | Primary database (Atlas) |
| Elasticsearch | 9200 | Logging & search |
| Kibana | 5601 | Log visualization |
| LocalStack | 4566 | AWS S3 simulation |

## 📋 Prerequisites

- Docker Desktop
- kubectl
- Helm 3+
- Terraform (optional)

## 🔧 Configuration

Copy `.env.example` to `.env` and configure:
```bash
cp docker/.env.example docker/.env
```

Edit `docker/.env` with your credentials.

## 📖 Documentation

- [Docker Setup](docs/docker-setup.md) - Coming soon
- [Kubernetes Guide](docs/kubernetes-guide.md) - Coming soon
- [Terraform Configs](docs/terraform-guide.md) - Coming soon

## 🏗️ Architecture

All microservices connect to these infrastructure components:
- Scraper → Kafka → NLP → MongoDB
- Auth → MongoDB + Redis
- Aggregation → MongoDB + Redis
- API Gateway → MongoDB + Redis + WebSocket

## 📊 Status

- [x] Project structure created
- [ ] Docker Compose setup (Day 3)
- [ ] Kubernetes manifests (Week 13)
- [ ] Terraform configs (Week 15)
- [ ] Helm charts (Week 15)