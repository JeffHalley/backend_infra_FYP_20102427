# Host Checks Schema

TABLE: host_checks

Columns:
- time (TIMESTAMP)
- host_name (TEXT)
- env (TEXT): always 'prd'
- assignment_group (TEXT)
- tool_name (TEXT): always Nagios for host checks

Metrics:
- cpu_load (FLOAT): >1.5 indicates unhealthy
- memory_usage_mb (INTEGER)
- disk_used_gb (INTEGER)
- disk_capacity_gb (INTEGER)
- uptime_epoch (BIGINT): seconds since epoch
- network_throughput_mbps (FLOAT)
- network_latency_ms (FLOAT)
