#!/usr/bin/env python3
"""
STOA Metrics Simulator
Generates realistic API traffic metrics for the quickstart demo.

OASIS/Ready Player One themed tenants and APIs.
Generates 5 min of historical data on startup so Grafana shows graphs immediately.
"""

import math
import random
import time
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

from prometheus_client import (
    Counter, Gauge, Histogram, CollectorRegistry,
    generate_latest, CONTENT_TYPE_LATEST
)

# Configuration
METRICS_PORT = 9091
SIMULATION_INTERVAL = 5  # seconds
HISTORICAL_MINUTES = 5   # Generate this much fake history on startup

# Create a custom registry
registry = CollectorRegistry()

# ═══════════════════════════════════════════════════════════════════════════
# STOA Metrics (matching what Grafana dashboards expect)
# ═══════════════════════════════════════════════════════════════════════════

stoa_api_requests_total = Counter(
    'stoa_api_requests_total',
    'Total API requests',
    ['tenant_id', 'api_id', 'endpoint', 'method', 'status_code'],
    registry=registry
)

stoa_api_request_duration_seconds = Histogram(
    'stoa_api_request_duration_seconds',
    'API request duration in seconds',
    ['tenant_id', 'api_id', 'endpoint'],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
    registry=registry
)

stoa_api_errors_total = Counter(
    'stoa_api_errors_total',
    'Total API errors',
    ['tenant_id', 'api_id', 'error_type'],
    registry=registry
)

stoa_subscriptions_active = Gauge(
    'stoa_subscriptions_active',
    'Active subscriptions per tenant',
    ['tenant_id'],
    registry=registry
)

stoa_rate_limit_remaining_ratio = Gauge(
    'stoa_rate_limit_remaining_ratio',
    'Rate limit remaining (0-1)',
    ['tenant_id', 'api_id'],
    registry=registry
)

# ═══════════════════════════════════════════════════════════════════════════
# OASIS-themed Data (Ready Player One)
# ═══════════════════════════════════════════════════════════════════════════

TENANTS = {
    "ioi-corp": {
        "display_name": "IOI Corporation",
        "tier": "enterprise",
        "error_rate": 0.08,      # 8% error rate - the baddies have issues
        "base_latency": 0.15,    # Slower legacy systems
        "subscriptions": 45,
        "apis": [
            {"id": "debt-collector-api", "endpoints": ["/debts", "/servants", "/loyalty-centers"]},
            {"id": "surveillance-api", "endpoints": ["/avatars/track", "/sixers/locate", "/oasis/monitor"]},
        ]
    },
    "gregarious-games": {
        "display_name": "Gregarious Games",
        "tier": "business",
        "error_rate": 0.01,      # 1% - well maintained
        "base_latency": 0.03,    # Fast modern APIs
        "subscriptions": 128,
        "apis": [
            {"id": "oasis-auth-api", "endpoints": ["/login", "/logout", "/sessions", "/tokens"]},
            {"id": "avatar-api", "endpoints": ["/avatars", "/customization", "/inventory"]},
            {"id": "inventory-api", "endpoints": ["/items", "/artifacts", "/coins", "/trade"]},
            {"id": "world-builder-api", "endpoints": ["/worlds", "/sectors", "/teleport"]},
        ]
    },
    "gunters-guild": {
        "display_name": "Gunters Guild",
        "tier": "starter",
        "error_rate": 0.02,      # 2% - community maintained
        "base_latency": 0.05,
        "subscriptions": 23,
        "apis": [
            {"id": "almanac-api", "endpoints": ["/clues", "/halliday", "/easter-eggs", "/journals"]},
            {"id": "leaderboard-api", "endpoints": ["/rankings", "/high-five", "/scores"]},
        ]
    }
}

HTTP_METHODS = ["GET", "GET", "GET", "POST", "PATCH", "DELETE"]
SUCCESS_CODES = ["200", "200", "200", "201", "204"]
ERROR_CODES = ["400", "401", "403", "404", "429", "500", "502", "503"]


def get_traffic_multiplier() -> float:
    """Simulate daily traffic patterns."""
    hour = datetime.now().hour
    # Peak: 9-12, 14-17
    if 9 <= hour <= 12 or 14 <= hour <= 17:
        return 1.0 + random.uniform(0, 0.3)
    elif 6 <= hour <= 9 or 17 <= hour <= 20:
        return 0.6 + random.uniform(0, 0.2)
    else:
        return 0.3 + random.uniform(0, 0.1)


def simulate_requests(multiplier: float = 1.0, batch_size: int = 1):
    """Generate simulated API requests."""
    for tenant_id, config in TENANTS.items():
        for api in config["apis"]:
            for endpoint in api["endpoints"]:
                # Number of requests this cycle
                num_requests = int(random.uniform(5, 25) * multiplier * batch_size)

                for _ in range(num_requests):
                    method = random.choice(HTTP_METHODS)

                    # Determine if this request errors
                    if random.random() < config["error_rate"]:
                        status = random.choice(ERROR_CODES)
                        error_type = f"http_{status}"
                        stoa_api_errors_total.labels(
                            tenant_id=tenant_id,
                            api_id=api["id"],
                            error_type=error_type
                        ).inc()
                    else:
                        status = random.choice(SUCCESS_CODES)

                    # Record request
                    stoa_api_requests_total.labels(
                        tenant_id=tenant_id,
                        api_id=api["id"],
                        endpoint=endpoint,
                        method=method,
                        status_code=status
                    ).inc()

                    # Simulate latency (log-normal for realistic tail)
                    latency = random.lognormvariate(
                        math.log(config["base_latency"]),
                        0.5
                    )
                    stoa_api_request_duration_seconds.labels(
                        tenant_id=tenant_id,
                        api_id=api["id"],
                        endpoint=endpoint
                    ).observe(min(latency, 5.0))


def update_gauges():
    """Update gauge metrics."""
    for tenant_id, config in TENANTS.items():
        # Active subscriptions (with small variation)
        stoa_subscriptions_active.labels(tenant_id=tenant_id).set(
            config["subscriptions"] + random.randint(-2, 2)
        )

        # Rate limit remaining
        for api in config["apis"]:
            if tenant_id == "ioi-corp":
                # IOI is always near their limits (demo for alerts)
                remaining = random.uniform(0.05, 0.15)
            else:
                remaining = random.uniform(0.4, 0.9)

            stoa_rate_limit_remaining_ratio.labels(
                tenant_id=tenant_id,
                api_id=api["id"]
            ).set(remaining)


def generate_historical_data():
    """Generate fake historical data so graphs show immediately."""
    print(f"[STARTUP] Generating {HISTORICAL_MINUTES} minutes of historical data...")

    # Simulate HISTORICAL_MINUTES of data
    # Each "minute" generates ~12 batches (5 sec intervals)
    batches = HISTORICAL_MINUTES * 12

    for i in range(batches):
        multiplier = get_traffic_multiplier()
        # Generate a batch worth of requests
        simulate_requests(multiplier=multiplier, batch_size=3)

        if (i + 1) % 12 == 0:
            minute = (i + 1) // 12
            print(f"[STARTUP] Generated minute {minute}/{HISTORICAL_MINUTES}")

    update_gauges()
    print(f"[STARTUP] Historical data generation complete!")


def simulation_loop():
    """Main simulation loop."""
    print("[SIMULATOR] Starting continuous metric generation...")

    iteration = 0
    while True:
        try:
            multiplier = get_traffic_multiplier()
            simulate_requests(multiplier=multiplier)
            update_gauges()

            iteration += 1
            if iteration % 12 == 0:  # Log every minute
                print(f"[{datetime.now().strftime('%H:%M:%S')}] "
                      f"Metrics generated (iteration {iteration})")

            time.sleep(SIMULATION_INTERVAL)

        except Exception as e:
            print(f"[ERROR] Simulation error: {e}")
            time.sleep(10)


class MetricsHandler(BaseHTTPRequestHandler):
    """HTTP handler for Prometheus metrics endpoint."""

    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', CONTENT_TYPE_LATEST)
            self.end_headers()
            self.wfile.write(generate_latest(registry))
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "healthy", "service": "metrics-simulator"}')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Suppress default logging
        pass


def main():
    print("=" * 60)
    print("  STOA Metrics Simulator")
    print("  OASIS-themed demo data generator")
    print("=" * 60)
    print(f"  Metrics port: {METRICS_PORT}")
    print(f"  Tenants: {', '.join(TENANTS.keys())}")
    print(f"  Historical data: {HISTORICAL_MINUTES} minutes")
    print("=" * 60)
    print()

    # Generate historical data first (so Grafana has graphs immediately)
    generate_historical_data()

    # Start HTTP server for metrics
    server = HTTPServer(('0.0.0.0', METRICS_PORT), MetricsHandler)
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()
    print(f"[SERVER] Metrics available at http://0.0.0.0:{METRICS_PORT}/metrics")

    # Run simulation loop
    simulation_loop()


if __name__ == "__main__":
    main()
