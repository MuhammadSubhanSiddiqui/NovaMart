#!/bin/bash

set -euo pipefail

echo "Starting NovaMart Friday Peak Load Simulation..."
echo "Simulating 1000 total concurrent connections over 15 minutes."

# Requires: pip install locust psycopg2-binary
locust -f locustfile.py \
       --headless \
       --users 1000 \
       --spawn-rate 50 \
       --run-time 15m \
       --csv=novamart_friday_peak \
       --csv-full-history \
       --host=localhost

echo "Simulation complete. Raw data exported to novamart_friday_peak_stats.csv"