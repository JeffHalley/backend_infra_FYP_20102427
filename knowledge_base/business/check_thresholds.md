# Monitoring Thresholds

App Checks:
- http_status = false → unhealthy
- synthetic_status = false → unhealthy
- Higher response_time_ms is worse
- Higher error_rate is worse
- Lower appdex is worse

Host Checks:
- cpu_load > 1.5 → unhealthy
- Higher memory_usage_mb indicates pressure
- disk_used_gb / disk_capacity_gb > 0.85 → unhealthy
- Higher network_latency_ms is worse
