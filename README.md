# STOA Platform - Quick Start

> **Get STOA running in under 5 minutes** 🚀

STOA is an AI-native API Management platform that lets you define APIs once and expose them everywhere (REST, MCP, GraphQL, gRPC).

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (v24+)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2+)
- **4GB RAM minimum** (8GB recommended for full observability stack)
- Works on: macOS (Intel/Apple Silicon), Linux, Windows (WSL2)

## 🏃 Quick Start (3 steps)

```bash
# 1. Clone the quickstart repo
git clone https://github.com/stoa-platform/stoa-quickstart
cd stoa-quickstart

# 2. Start STOA
docker compose up -d

# 3. Open the Portal
open http://localhost:3000
```

**That's it!** STOA is now running locally.

## 📍 Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| **Portal** | http://localhost:3000 | `admin` / `admin` |
| **Grafana** | http://localhost:3001 | `admin` / `stoa-demo` |
| **API** | http://localhost:8080 | — |
| **Prometheus** | http://localhost:9090 | — |
| **Keycloak** | http://localhost:8081 | `admin` / `admin` |

## 👤 Demo Users

### Platform Users
| Username | Password | Role | Tenant |
|----------|----------|------|--------|
| `admin` | `admin` | Platform Admin | ACME |
| `developer` | `developer` | API Publisher | ACME |
| `consumer` | `consumer` | API Consumer | ACME |

### OASIS Demo Users (Ready Player One themed)
| Username | Password | Role | Tenant |
|----------|----------|------|--------|
| `parzival` | `parzival` | API Publisher | Gunters Guild |
| `art3mis` | `art3mis` | API Publisher | Gunters Guild |
| `sorrento` | `sorrento` | Tenant Admin | IOI Corp |

---

## 👀 What to Look at First

After `docker compose up -d`, here's a 2-minute tour:

### 1. Grafana Dashboards (http://localhost:3001)
- **STOA Platform Overview** — Live traffic by tenant, error rates, latency percentiles
- **API Traffic** — Requests per API, HTTP methods breakdown
- **System Health** — Service status, log streams

> Metrics start generating immediately thanks to the built-in simulator.

### 2. API Catalog (http://localhost:3000)
Login as `parzival` / `parzival` to see:
- 8 pre-loaded OASIS-themed APIs
- 3 tenants: IOI Corp, Gregarious Games, Gunters Guild

### 3. Alerting Demo
Check **Grafana → Alerting** — IOI Corp's services have intentionally high error rates to demonstrate alerting capabilities.

---

## 📖 Tutorial: Your First API in 5 Minutes

### Step 1: Login to the Portal

1. Open http://localhost:3000
2. Click **Login**
3. Enter `developer` / `developer`

### Step 2: Create an API

1. Go to **APIs** → **Create API**
2. Fill in:
   - **Name**: `hello-api`
   - **Display Name**: `Hello World API`
   - **Description**: `My first STOA API`
3. Click **Create**

### Step 3: Add an Endpoint

1. In your API, go to **Endpoints** → **Add Endpoint**
2. Configure:
   - **Method**: `GET`
   - **Path**: `/hello/{name}`
   - **Description**: `Say hello to someone`
3. Add a **Path Parameter**:
   - **Name**: `name`
   - **Type**: `string`
   - **Required**: `true`
4. Click **Save**

### Step 4: Generate MCP Tool

1. Go to **Protocols** → **MCP**
2. Click **Generate MCP Tool**
3. STOA automatically creates a Claude-compatible tool:

```json
{
  "name": "hello_api__say_hello",
  "description": "Say hello to someone",
  "input_schema": {
    "type": "object",
    "properties": {
      "name": { "type": "string", "description": "Name to greet" }
    },
    "required": ["name"]
  }
}
```

### Step 5: Test Your API

**Via REST:**
```bash
curl http://localhost:8080/v1/hello/World
```

**Via MCP (in Claude.ai):**
Once connected, Claude can use your tool:
> "Say hello to Alice using the hello API"

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           STOA Platform                                  │
├─────────────┬─────────────┬─────────────┬─────────────┬─────────────────┤
│   Portal    │Control Plane│  Keycloak   │   Redis     │     Grafana     │
│  (React)    │ (FastAPI)   │   (OIDC)    │  (Cache)    │  (Dashboards)   │
│   :3000     │   :8080     │   :8081     │   :6379     │     :3001       │
└─────────────┴─────────────┴─────────────┴─────────────┴─────────────────┘
                     │                            │
          ┌──────────┴──────────┐      ┌─────────┴─────────┐
          │    PostgreSQL       │      │    Prometheus     │
          │      :5432          │      │      :9090        │
          └─────────────────────┘      └───────────────────┘
                                                │
                                       ┌────────┴────────┐
                                       │      Loki       │
                                       │     :3100       │
                                       └─────────────────┘
```

### Services

| Service | Purpose | Port |
|---------|---------|------|
| **Portal** | React Web UI | 3000 |
| **Control Plane** | FastAPI backend | 8080 |
| **Keycloak** | Identity & Access | 8081 |
| **PostgreSQL** | Primary database | 5432 |
| **Redis** | Cache & sessions | 6379 |
| **Grafana** | Dashboards | 3001 |
| **Prometheus** | Metrics | 9090 |
| **Loki** | Logs | 3100 |
| **Metrics Simulator** | Demo traffic | - |

## 🛠️ Common Commands

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f

# View specific service logs
docker compose logs -f control-plane

# Stop all services
docker compose down

# Stop and remove volumes (clean reset)
docker compose down -v

# Restart a single service
docker compose restart control-plane
```

## 🔍 Troubleshooting

### Services not starting?

```bash
# Check service status
docker compose ps

# Check for errors
docker compose logs --tail=50

# Check specific service
docker compose logs control-plane --tail=100
```

### Database connection issues?

```bash
# Verify PostgreSQL is healthy
docker compose exec postgres pg_isready -U stoa

# Check database tables
docker compose exec postgres psql -U stoa -c '\dt stoa.*'

# Check OASIS data loaded
docker compose exec postgres psql -U stoa -c "SELECT name, display_name FROM stoa.tenants;"
```

### Keycloak not ready?

Keycloak can take 30-60 seconds to start. Check:
```bash
docker compose logs keycloak | grep "started in"
```

### Grafana shows no data?

The metrics simulator needs control-plane to be healthy first:
```bash
# Check simulator logs
docker compose logs metrics-simulator

# Should see "Historical data generation complete!"
```

### Port already in use?

Default ports:
- 3000: Portal
- 3001: Grafana
- 8080: API
- 8081: Keycloak
- 9090: Prometheus

Change conflicting ports:
```bash
# Edit docker-compose.yml "ports" section, or:
docker compose down
# Edit ports in docker-compose.yml
docker compose up -d
```

### Not enough memory?

STOA requires ~4GB RAM. Check:
```bash
docker stats --no-stream
```

If running low, you can disable observability temporarily by commenting out the prometheus, grafana, loki, promtail, and metrics-simulator services.

### Mac M1/M2/M3 (Apple Silicon)?

All images are multi-arch and should work automatically. If you see issues:
```bash
# Force rebuild
docker compose build --no-cache
docker compose up -d
```

### Clean reset

```bash
# Stop and remove everything (including data)
docker compose down -v

# Start fresh
docker compose up -d
```

## 📚 Next Steps

- **[Full Documentation](https://docs.gostoa.dev)** — Complete guides and API reference
- **[UAC Contracts](https://docs.gostoa.dev/concepts/uac)** — Learn about Universal API Contracts
- **[MCP Integration](https://docs.gostoa.dev/guides/mcp)** — Connect to Claude.ai
- **[Production Deployment](https://docs.gostoa.dev/deployment)** — Kubernetes & Helm charts

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](https://github.com/stoa-platform/stoa/blob/main/CONTRIBUTING.md).

## 📄 License

Apache 2.0 — See [LICENSE](LICENSE) for details.

---

<p align="center">
  <strong>STOA</strong> — The Cilium of API Management<br>
  <a href="https://gostoa.dev">Website</a> •
  <a href="https://docs.gostoa.dev">Docs</a> •
  <a href="https://github.com/stoa-platform/stoa">GitHub</a>
</p>
