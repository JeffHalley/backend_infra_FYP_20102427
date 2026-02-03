# App Checks Schema

TABLE: app_checks

Columns:
- time (TIMESTAMP): Time of the measurement
- host_name (TEXT): Host identifier
- env (TEXT): Environment, always 'prd'
- app_name (TEXT): Application name (roman, latin, or greek inspired)
- app_id (INTEGER): Random 5-digit identifier
- assignment_group (TEXT): {app_name}Developers
- tool_name (TEXT): One of [Nagios, Dynatrace, Splunk]

Metrics:
- http_status (BOOLEAN): true = healthy, false = unhealthy
- response_time_ms (INTEGER): Latency in milliseconds
- error_rate (FLOAT): Error percentage
- synthetic_status (BOOLEAN): true = healthy, false = unhealthy
- user_count (INTEGER): Current active users
- appdex (FLOAT): Application performance index
