-- STOA Platform - Database Initialization
-- This script sets up the initial schema for quickstart

-- Create Keycloak schema (Keycloak manages its own tables)
CREATE SCHEMA IF NOT EXISTS keycloak;

-- Create STOA schema
CREATE SCHEMA IF NOT EXISTS stoa;

-- Set default search path
SET search_path TO stoa, public;

-- ─────────────────────────────────────────────────────────────────
-- Tenants
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE,
    display_name VARCHAR(255) NOT NULL,
    tier VARCHAR(20) DEFAULT 'starter',
    admin_email VARCHAR(255),
    keycloak_realm VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────
-- APIs / Tools
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS apis (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    display_name VARCHAR(255) NOT NULL,
    description TEXT,
    version VARCHAR(20) DEFAULT 'v1',
    spec_type VARCHAR(20) DEFAULT 'openapi',
    spec_content JSONB,
    status VARCHAR(20) DEFAULT 'draft',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tenant_id, name, version)
);

-- ─────────────────────────────────────────────────────────────────
-- UAC Contracts
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS uac_contracts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_id UUID REFERENCES apis(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    protocol VARCHAR(20) NOT NULL,
    contract_spec JSONB NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────
-- Subscriptions
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    api_id UUID REFERENCES apis(id) ON DELETE CASCADE,
    application_name VARCHAR(255),
    api_key_hash VARCHAR(255),
    status VARCHAR(20) DEFAULT 'pending',
    rate_limit INTEGER DEFAULT 100,
    quota_daily INTEGER DEFAULT 10000,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────
-- API Usage Logs
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS api_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID REFERENCES subscriptions(id),
    api_id UUID REFERENCES apis(id),
    tenant_id UUID REFERENCES tenants(id),
    request_method VARCHAR(10),
    request_path VARCHAR(500),
    response_status INTEGER,
    duration_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_api_logs_created_at ON api_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_api_logs_tenant_id ON api_logs(tenant_id);

-- ─────────────────────────────────────────────────────────────────
-- Invites (CAB-909: Prospect Invite System)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    company VARCHAR(100) NOT NULL,
    token VARCHAR(64) NOT NULL UNIQUE,
    source VARCHAR(50),
    status VARCHAR(20) DEFAULT 'pending',  -- pending|opened|converted|expired
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    opened_at TIMESTAMPTZ                  -- Denormalized for perf metrics
);

CREATE INDEX IF NOT EXISTS idx_invites_token ON invites(token);
CREATE INDEX IF NOT EXISTS idx_invites_email ON invites(email);
CREATE INDEX IF NOT EXISTS idx_invites_status ON invites(status);

-- ─────────────────────────────────────────────────────────────────
-- Prospect Events (CAB-909: Event Tracking)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS prospect_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invite_id UUID REFERENCES invites(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL,       -- invite_opened|sandbox_created|tool_called|etc
    metadata JSONB DEFAULT '{}',
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prospect_events_invite_timestamp ON prospect_events(invite_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_prospect_events_type ON prospect_events(event_type);

-- ─────────────────────────────────────────────────────────────────
-- Demo Data: ACME Corp Tenant
-- ─────────────────────────────────────────────────────────────────
INSERT INTO tenants (name, display_name, tier, admin_email, keycloak_realm)
VALUES ('acme', 'ACME Corporation', 'starter', 'admin@acme.example.com', 'stoa')
ON CONFLICT (name) DO NOTHING;

-- Demo API: Weather Service
INSERT INTO apis (tenant_id, name, display_name, description, version, status, spec_content)
SELECT
    t.id,
    'weather-api',
    'Weather API',
    'Get current weather data for any city',
    'v1',
    'active',
    '{"openapi": "3.0.3", "info": {"title": "Weather API", "version": "1.0.0"}, "paths": {"/weather/{city}": {"get": {"summary": "Get weather for a city", "parameters": [{"name": "city", "in": "path", "required": true, "schema": {"type": "string"}}], "responses": {"200": {"description": "Weather data"}}}}}}'::jsonb
FROM tenants t WHERE t.name = 'acme'
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
-- OASIS Demo Data (Ready Player One themed)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- IOI Corporation - The antagonists
-- ─────────────────────────────────────────────────────────────────
INSERT INTO tenants (name, display_name, tier, admin_email, keycloak_realm)
VALUES ('ioi-corp', 'IOI Corporation', 'enterprise', 'sorrento@ioi.corp', 'stoa')
ON CONFLICT (name) DO NOTHING;

-- IOI: Debt Collector API
INSERT INTO apis (tenant_id, name, display_name, description, version, status, spec_content)
SELECT
    t.id,
    'debt-collector-api',
    'Debt Collector API',
    'Manage indentured servitude contracts and loyalty center assignments',
    'v1',
    'active',
    '{
        "openapi": "3.0.3",
        "info": {"title": "IOI Debt Collector API", "version": "1.0.0", "description": "Manage debt collection and loyalty centers"},
        "paths": {
            "/debts": {"get": {"summary": "List all debts", "responses": {"200": {"description": "List of debts"}}}},
            "/debts/{id}": {"get": {"summary": "Get debt details", "parameters": [{"name": "id", "in": "path", "required": true, "schema": {"type": "string"}}], "responses": {"200": {"description": "Debt details"}}}},
            "/servants": {"get": {"summary": "List indentured servants", "responses": {"200": {"description": "Servant list"}}}},
            "/loyalty-centers": {"get": {"summary": "List loyalty centers", "responses": {"200": {"description": "Center list"}}}}
        }
    }'::jsonb
FROM tenants t WHERE t.name = 'ioi-corp'
ON CONFLICT DO NOTHING;

-- IOI: Surveillance API
INSERT INTO apis (tenant_id, name, display_name, description, version, status, spec_content)
SELECT
    t.id,
    'surveillance-api',
    'Surveillance API',
    'Track avatars and monitor OASIS activities for security purposes',
    'v1',
    'active',
    '{
        "openapi": "3.0.3",
        "info": {"title": "IOI Surveillance API", "version": "1.0.0", "description": "Avatar tracking and OASIS monitoring"},
        "paths": {
            "/avatars/track": {"post": {"summary": "Track an avatar", "responses": {"200": {"description": "Tracking initiated"}}}},
            "/sixers/locate": {"get": {"summary": "Locate Sixer operatives", "responses": {"200": {"description": "Sixer locations"}}}},
            "/oasis/monitor": {"get": {"summary": "Monitor OASIS sector activity", "responses": {"200": {"description": "Activity data"}}}}
        }
    }'::jsonb
FROM tenants t WHERE t.name = 'ioi-corp'
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- Gregarious Games - Creators of the OASIS
-- ─────────────────────────────────────────────────────────────────
INSERT INTO tenants (name, display_name, tier, admin_email, keycloak_realm)
VALUES ('gregarious-games', 'Gregarious Games', 'business', 'admin@gregarious.games', 'stoa')
ON CONFLICT (name) DO NOTHING;

-- Gregarious: OASIS Auth API
INSERT INTO apis (tenant_id, name, display_name, description, version, status, spec_content)
SELECT
    t.id,
    'oasis-auth-api',
    'OASIS Authentication API',
    'Secure authentication and session management for OASIS users',
    'v1',
    'active',
    '{
        "openapi": "3.0.3",
        "info": {"title": "OASIS Auth API", "version": "1.0.0", "description": "Authentication for the OASIS"},
        "paths": {
            "/login": {"post": {"summary": "Login to OASIS", "responses": {"200": {"description": "Login successful"}}}},
            "/logout": {"post": {"summary": "Logout from OASIS", "responses": {"200": {"description": "Logout successful"}}}},
            "/sessions": {"get": {"summary": "List active sessions", "responses": {"200": {"description": "Session list"}}}},
            "/tokens": {"post": {"summary": "Generate access token", "responses": {"200": {"description": "Token generated"}}}}
        }
    }'::jsonb
FROM tenants t WHERE t.name = 'gregarious-games'
ON CONFLICT DO NOTHING;

-- Gregarious: Avatar API
INSERT INTO apis (tenant_id, name, display_name, description, version, status, spec_content)
SELECT
    t.id,
    'avatar-api',
    'Avatar Management API',
    'Create and customize your OASIS avatar',
    'v1',
    'active',
    '{
        "openapi": "3.0.3",
        "info": {"title": "Avatar API", "version": "1.0.0", "description": "Avatar management in the OASIS"},
        "paths": {
            "/avatars": {"get": {"summary": "List avatars"}, "post": {"summary": "Create avatar"}},
            "/avatars/{id}": {"get": {"summary": "Get avatar"}, "patch": {"summary": "Update avatar"}},
            "/customization": {"get": {"summary": "Get customization options"}},
            "/inventory": {"get": {"summary": "Get avatar inventory"}}
        }
    }'::jsonb
FROM tenants t WHERE t.name = 'gregarious-games'
ON CONFLICT DO NOTHING;

-- Gregarious: Inventory API
INSERT INTO apis (tenant_id, name, display_name, description, version, status, spec_content)
SELECT
    t.id,
    'inventory-api',
    'Inventory & Trading API',
    'Manage items, artifacts, and OASIS coins',
    'v1',
    'active',
    '{
        "openapi": "3.0.3",
        "info": {"title": "Inventory API", "version": "1.0.0", "description": "Item and artifact management"},
        "paths": {
            "/items": {"get": {"summary": "List items"}, "post": {"summary": "Add item"}},
            "/artifacts": {"get": {"summary": "List artifacts"}},
            "/coins": {"get": {"summary": "Get coin balance"}},
            "/trade": {"post": {"summary": "Initiate trade"}}
        }
    }'::jsonb
FROM tenants t WHERE t.name = 'gregarious-games'
ON CONFLICT DO NOTHING;

-- Gregarious: World Builder API
INSERT INTO apis (tenant_id, name, display_name, description, version, status, spec_content)
SELECT
    t.id,
    'world-builder-api',
    'World Builder API',
    'Create and manage OASIS worlds and sectors',
    'v1',
    'active',
    '{
        "openapi": "3.0.3",
        "info": {"title": "World Builder API", "version": "1.0.0", "description": "OASIS world creation"},
        "paths": {
            "/worlds": {"get": {"summary": "List worlds"}, "post": {"summary": "Create world"}},
            "/worlds/{id}/sectors": {"get": {"summary": "List sectors in world"}},
            "/teleport": {"post": {"summary": "Teleport to location"}}
        }
    }'::jsonb
FROM tenants t WHERE t.name = 'gregarious-games'
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- Gunters Guild - Easter egg hunters community
-- ─────────────────────────────────────────────────────────────────
INSERT INTO tenants (name, display_name, tier, admin_email, keycloak_realm)
VALUES ('gunters-guild', 'Gunters Guild', 'starter', 'parzival@gunters.guild', 'stoa')
ON CONFLICT (name) DO NOTHING;

-- Gunters: Almanac API
INSERT INTO apis (tenant_id, name, display_name, description, version, status, spec_content)
SELECT
    t.id,
    'almanac-api',
    'Halliday Almanac API',
    'Access clues, journals, and easter egg research from Anorak''s Almanac',
    'v1',
    'active',
    '{
        "openapi": "3.0.3",
        "info": {"title": "Halliday Almanac API", "version": "1.0.0", "description": "The complete guide to Halliday"},
        "paths": {
            "/clues": {"get": {"summary": "Search clues"}},
            "/halliday": {"get": {"summary": "Halliday biography and timeline"}},
            "/easter-eggs": {"get": {"summary": "Known easter eggs"}},
            "/journals": {"get": {"summary": "Anorak journal entries"}}
        }
    }'::jsonb
FROM tenants t WHERE t.name = 'gunters-guild'
ON CONFLICT DO NOTHING;

-- Gunters: Leaderboard API
INSERT INTO apis (tenant_id, name, display_name, description, version, status, spec_content)
SELECT
    t.id,
    'leaderboard-api',
    'Gunter Leaderboard API',
    'Track the High Five and other gunter rankings',
    'v1',
    'active',
    '{
        "openapi": "3.0.3",
        "info": {"title": "Leaderboard API", "version": "1.0.0", "description": "Gunter rankings and scores"},
        "paths": {
            "/rankings": {"get": {"summary": "Get current rankings"}},
            "/high-five": {"get": {"summary": "The legendary High Five"}},
            "/scores": {"get": {"summary": "Detailed scoring breakdown"}}
        }
    }'::jsonb
FROM tenants t WHERE t.name = 'gunters-guild'
ON CONFLICT DO NOTHING;

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_apis_tenant_id ON apis(tenant_id);
CREATE INDEX IF NOT EXISTS idx_apis_status ON apis(status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_tenant_id ON subscriptions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_api_id ON subscriptions(api_id);
CREATE INDEX IF NOT EXISTS idx_uac_contracts_api_id ON uac_contracts(api_id);

-- Grant permissions
GRANT ALL ON SCHEMA stoa TO stoa;
GRANT ALL ON ALL TABLES IN SCHEMA stoa TO stoa;
GRANT ALL ON ALL SEQUENCES IN SCHEMA stoa TO stoa;
