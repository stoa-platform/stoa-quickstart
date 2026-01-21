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
