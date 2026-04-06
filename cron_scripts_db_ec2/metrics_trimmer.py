#!/usr/bin/env python3
"""
metrics_trimmer.py
------------------
Keeps the metrics table under 10GB by deleting the oldest rows in batches.
Designed to run every 15 minutes via cron.

Cron entry:
    */15 * * * * /usr/bin/python3 /opt/metrics/metrics_trimmer.py >> /var/log/metrics_trimmer.log 2>&1
"""

import logging
import sys

import psycopg2

# Config
DB_CONFIG = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "postgres",
    "user":     "postgres",
    "password": "yourpassword",
}

SIZE_LIMIT_GB  = 10.0        # Hard ceiling
TARGET_GB      = 9.5         # Trim down to this to give breathing room
BATCH_SIZE     = 10_000      # Rows deleted per iteration

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger(__name__)

# Helpers
def get_table_size_gb(cur) -> float:
    cur.execute("SELECT pg_total_relation_size('metrics') / 1024.0 / 1024.0 / 1024.0;")
    return float(cur.fetchone()[0])

def delete_oldest_batch(cur) -> int:
    cur.execute("""
        DELETE FROM metrics
        WHERE id IN (
            SELECT id FROM metrics
            ORDER BY time ASC, id ASC
            LIMIT %s
        )
    """, (BATCH_SIZE,))
    return cur.rowcount

def main():
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        conn.autocommit = False

        with conn:
            with conn.cursor() as cur:
                size_gb = get_table_size_gb(cur)
                log.info("Current table size: %.3f GB", size_gb)

                if size_gb < SIZE_LIMIT_GB:
                    log.info("Under limit (%.1f GB), nothing to do.", SIZE_LIMIT_GB)
                    return

                log.info("Over limit — trimming to %.1f GB...", TARGET_GB)
                total_deleted = 0

                while size_gb >= TARGET_GB:
                    deleted = delete_oldest_batch(cur)
                    total_deleted += deleted
                    size_gb = get_table_size_gb(cur)
                    log.info("Deleted %d rows this batch | Table now: %.3f GB", deleted, size_gb)

                    if deleted == 0:
                        log.warning("No rows deleted — table may be empty.")
                        break

                # Reclaim disk space from deleted rows
                cur.execute("VACUUM metrics;")
                log.info("VACUUM complete. Total rows deleted: %d | Final size: %.3f GB", total_deleted, size_gb)

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