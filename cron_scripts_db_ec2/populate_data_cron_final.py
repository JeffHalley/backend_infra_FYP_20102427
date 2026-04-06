#!/usr/bin/env python3
"""
metrics_collector.py
--------------------
Generates one snapshot of metrics for all servers/apps and writes
the rows to a local PostgreSQL database.

Designed to be run every 5 minutes via cron:
    */5 * * * * /usr/bin/python3 /opt/metrics/metrics_collector.py >> /var/log/metrics_collector.log 2>&1
"""

import json
import random
import logging
import sys
from datetime import datetime, timezone

import psycopg2
from psycopg2.extras import execute_values

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger(__name__)

# Database config, obviously dont expose your creds in real life
DB_CONFIG = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "postgres",
    "user":     "postgres",
    "password": "yourpassword",
}

# App config
APP_TEAMS = {
    "Aetheris": ["WebSrvA", "WinAppA", "InternalA"],
    "Nexum":    ["WebSrvB", "WinAppB", "InternalB"],
    "Elyssium": ["WebSrvC", "WinAppC", "InternalC"],
    "Dynamis":  ["WebSrvD", "WinAppD", "InternalD"],
}
APP_CHECKS = [
    "http_ping", "response_time", "error_rate",
    "dynatrace_synth", "current_user_count", "apdex",
]
APP_TOOLS = ["Nagios", "Dyntrace", "Splunk"]

# Host config
HOST_TEAMS = {
    "Aetheris": ["InfraSrv1",  "InfraSrv2",  "InfraSrv3"],
    "Nexum":    ["InfraSrv4",  "InfraSrv5",  "InfraSrv6"],
    "Elyssium": ["InfraSrv7",  "InfraSrv8",  "InfraSrv9"],
    "Dynamis":  ["InfraSrv10", "InfraSrv11", "InfraSrv12"],
}
HOST_CHECKS = [
    "cpu_load", "memory_usage", "disk_space_used",
    "disk_capacity", "uptime", "net_throughput", "net_latency",
]
HOST_TOOL = "Nagios"

# Static app ID mapping
STATIC_APP_IDS = {
    # Aetheris
    "WebSrvA":   11001,
    "WinAppA":   11002,
    "InternalA": 11003,
    # Nexum
    "WebSrvB":   22001,
    "WinAppB":   22002,
    "InternalB": 22003,
    # Elyssium
    "WebSrvC":   33001,
    "WinAppC":   33002,
    "InternalC": 33003,
    # Dynamis
    "WebSrvD":   44001,
    "WinAppD":   44002,
    "InternalD": 44003,
    # Aetheris infra
    "InfraSrv1":  11101,
    "InfraSrv2":  11102,
    "InfraSrv3":  11103,
    # Nexum infra
    "InfraSrv4":  22101,
    "InfraSrv5":  22102,
    "InfraSrv6":  22103,
    # Elyssium infra
    "InfraSrv7":  33101,
    "InfraSrv8":  33102,
    "InfraSrv9":  33103,
    # Dynamis infra
    "InfraSrv10": 44101,
    "InfraSrv11": 44102,
    "InfraSrv12": 44103,
}

# Registry — built once at startup
def build_registry():
    all_servers = {}
    for team, servers in APP_TEAMS.items():
        for s in servers:
            all_servers[s] = team
    for team, servers in HOST_TEAMS.items():
        for s in servers:
            all_servers[s] = team

    return {
        s: {
            "host_name":        f"{s}Host",
            "app_id":           STATIC_APP_IDS[s],
            "assignment_group": f"{team}Developers",
        }
        for s, team in all_servers.items()
    }

# Status helpers
def generate_status(check_name: str, value) -> str:
    if check_name in ("http_ping", "dynatrace_synth"):
        return "healthy" if value == 1 else "unhealthy"
    if check_name == "cpu_load":
        return "healthy" if value <= 1.0 else "unhealthy"
    return "healthy"

# Metric generators
def app_metric(check: str) -> tuple:
    """Return (value, metadata_dict) for an app check."""
    if check == "http_ping":
        v = random.choices([1, 0], weights=[0.95, 0.05])[0]
        return v, {}
    if check == "response_time":
        v = round(random.uniform(100, 500), 2)
        return v, {"p50": round(v * 0.8, 2), "p95": round(v * 1.2, 2)}
    if check == "error_rate":
        return round(random.uniform(0, 0.05), 4), {}
    if check == "dynatrace_synth":
        v = random.choices([1, 0], weights=[0.98, 0.02])[0]
        return v, {"step_failed": v == 0}
    if check == "current_user_count":
        return random.randint(0, 1000), {}
    if check == "apdex":
        return round(random.uniform(0.7, 1.0), 2), {}
    raise ValueError(f"Unknown app check: {check}")

def host_metric(check: str) -> tuple:
    """Return (value, metadata_dict) for a host check."""
    if check == "cpu_load":
        return round(random.uniform(0.1, 1.5), 2), {}
    if check == "memory_usage":
        return round(random.uniform(10, 90), 2), {}
    if check == "disk_space_used":
        return round(random.uniform(100, 900), 2), {}
    if check == "disk_capacity":
        return 1000, {}
    if check == "uptime":
        return random.randint(10_000, 500_000), {}
    if check == "net_throughput":
        return random.randint(100, 5000), {}
    if check == "net_latency":
        return round(random.uniform(1, 100), 2), {}
    raise ValueError(f"Unknown host check: {check}")

# Row builders
def build_rows(registry: dict, snapshot_time: datetime) -> list[tuple]:
    rows = []

    # App metrics
    for team_name, servers in APP_TEAMS.items():
        for server in servers:
            identity = registry[server]
            for idx, check in enumerate(APP_CHECKS):
                tool = APP_TOOLS[idx % len(APP_TOOLS)]
                value, metadata = app_metric(check)
                rows.append((
                    snapshot_time,
                    identity["host_name"],
                    "prd",
                    server,
                    identity["app_id"],
                    identity["assignment_group"],
                    tool,
                    "app_metrics",
                    check,
                    generate_status(check, value),
                    float(value),
                    json.dumps(metadata),
                ))

    # Host metrics
    for team_name, servers in HOST_TEAMS.items():
        for server in servers:
            identity = registry[server]
            for check in HOST_CHECKS:
                value, metadata = host_metric(check)
                rows.append((
                    snapshot_time,
                    identity["host_name"],
                    "prd",
                    server,
                    identity["app_id"],
                    identity["assignment_group"],
                    HOST_TOOL,
                    "host_metrics",
                    check,
                    generate_status(check, value),
                    float(value),
                    json.dumps(metadata),
                ))

    return rows

# DDL, run once to create the table if it doesn't exist
CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS metrics (
    id               BIGSERIAL PRIMARY KEY,
    time             TIMESTAMPTZ     NOT NULL,
    host_name        TEXT            NOT NULL,
    env              TEXT            NOT NULL,
    app_name         TEXT            NOT NULL,
    app_id           INTEGER         NOT NULL,
    assignment_group TEXT            NOT NULL,
    tool_name        TEXT            NOT NULL,
    metric_group     TEXT            NOT NULL,
    metric_name      TEXT            NOT NULL,
    status           TEXT            NOT NULL,
    value            DOUBLE PRECISION NOT NULL,
    metadata         JSONB
);


"""

INSERT_SQL = """
INSERT INTO metrics
    (time, host_name, env, app_name, app_id, assignment_group,
     tool_name, metric_group, metric_name, status, value, metadata)
VALUES %s
"""

# Main
def main():
    snapshot_time = datetime.now(tz=timezone.utc)
    log.info("Snapshot time: %s", snapshot_time.isoformat())

    registry = build_registry()
    rows = build_rows(registry, snapshot_time)
    log.info("Generated %d metric rows", len(rows))

    try:
        conn = psycopg2.connect(**DB_CONFIG)
        conn.autocommit = False
        with conn:
            with conn.cursor() as cur:
                cur.execute(CREATE_TABLE_SQL)
                execute_values(cur, INSERT_SQL, rows, page_size=500)
        log.info("Successfully wrote %d rows to PostgreSQL", len(rows))
    except psycopg2.Error as exc:
        log.error("Database error: %s", exc)
        sys.exit(1)
    finally:
        try:
            conn.close()
        except Exception:
            pass

if __name__ == "__main__":
    main()