# STOA Platform - Quick Start

> **Get STOA running in under 5 minutes** 🚀

STOA is an AI-native API Management platform that lets you define APIs once and expose them everywhere (REST, MCP, GraphQL, gRPC).

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (v24+)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2+)
- 4GB RAM available

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
| **API** | http://localhost:8080 | — |
| **Keycloak** | http://localhost:8081 | `admin` / `admin` |

## 👤 Demo Users

| Username | Password | Role |
|----------|----------|------|
| `admin` | `admin` | Platform Admin |
| `developer` | `developer` | API Publisher |
| `consumer` | `consumer` | API Consumer |

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
┌─────────────────────────────────────────────────────────────┐
│                        STOA Platform                        │
├──────────────┬──────────────┬──────────────┬───────────────┤
│    Portal    │ Control Plane│   Keycloak   │    Redis      │
│   (React)    │  (FastAPI)   │   (OIDC)     │   (Cache)     │
│  :3000       │   :8080      │    :8081     │   :6379       │
└──────────────┴──────────────┴──────────────┴───────────────┘
                              │
                    ┌─────────┴─────────┐
                    │    PostgreSQL     │
                    │      :5432        │
                    └───────────────────┘
```

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
```

### Database connection issues?

```bash
# Verify PostgreSQL is healthy
docker compose exec postgres pg_isready -U stoa

# Check database
docker compose exec postgres psql -U stoa -c '\dt stoa.*'
```

### Keycloak not ready?

Keycloak can take 30-60 seconds to start. Check:
```bash
docker compose logs keycloak | grep "started in"
```

### Port already in use?

Edit `docker-compose.yml` or use environment variables:
```bash
PORTAL_PORT=3001 docker compose up -d
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
