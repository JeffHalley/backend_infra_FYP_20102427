# DATA SOURCE: public.metrics table
## 1. TABLE STRUCTURE
Table Name: `public.metrics`

| Column | Type | Description |
| :--- | :--- | :--- |
| time | TIMESTAMPTZ | Event time. |
| host_name | TEXT | Physical/Virtual server ID (e.g., 'WebSrprd6153'). |
| app_name | TEXT | Logical application name OR Infra Service name (e.g., 'WebSrvA', 'InfraSrv3'). |
| env | TEXT | Always 'prd'. |
| assignment_group | TEXT | Responsible team (e.g., 'NexumDevelopers'). |
| tool_name | TEXT | Data source (Nagios, Dyntrace, Splunk). |
| metric_group | TEXT | 'app_metrics' or 'host_metrics'. |
| metric_name | TEXT | **Unique key for the metric (see mapping).** |
| status | TEXT | 'healthy' or 'unhealthy'. |
| value | DOUBLE | The actual measurement. |
| metadata | JSONB | Nested data (e.g., p50, p95). |

## 2. METRIC NAME DICTIONARY
NEVER guess a metric name. Use these exact strings:

### Infra/Host Metrics (`metric_group = 'host_metrics'`)
- CPU: `cpu_load`
- Memory: `memory_usage`
- Disk: `disk_space_used`, `disk_capacity`
- Uptime: `uptime`
- Network: `net_throughput`, `net_latency`

### App Metrics (`metric_group = 'app_metrics'`)
- Response Time: `response_time` (Use `metadata->>'p95'` for tail latency)
- Error Rate: `error_rate`
- Status: `http_ping` or `dynatrace_synth`
- Users: `current_user_count`
- Apdex: `apdex`

## 3. MANDATORY QUERY STRATEGY
Follow these steps to generate SQL:
1. **Identify the Entity**: If the user provides a name like 'InfraSrvX' or 'WebSrvX', check BOTH `app_name` and `host_name` or use a `WHERE (app_name = 'X' OR host_name = 'X')` pattern.
2. **Apply Metric Filter**: Always include `AND metric_name = '...'`.
3. **Time Sorting**: Always `ORDER BY time DESC`.
4. **Aggregation**: If the user asks for "Current" or "Latest", use `LIMIT 1`. If they ask for "Average", use `AVG(value)`.
5. **JSONB Extraction**: When accessing `metadata`, cast to numeric if doing math: `(metadata->>'p95')::numeric`.

## 4. EDGE CASE HANDLING
- **Missing Metric**: If the user asks for a metric not in the dictionary, return `-- ERROR: Metric not found`.
- **Top/Bottom**: Use `ORDER BY value DESC/ASC`.
- **Counts**: Use `COUNT(DISTINCT host_name)` to find how many servers are involved.

## 5. REFERENCE EXAMPLES
-- Average response time for a specific app
SELECT AVG(value) FROM public.metrics WHERE app_name = 'WebSrvA' AND metric_name = 'response_time';

-- Latest uptime for an Infra Service (Note: InfraSrv is often in app_name)
SELECT value FROM public.metrics WHERE app_name = 'InfraSrv3' AND metric_name = 'uptime' ORDER BY time DESC LIMIT 1;

-- Hosts with high error rates
SELECT host_name, value FROM public.metrics WHERE metric_name = 'error_rate' AND value > 0.05 ORDER BY value DESC;