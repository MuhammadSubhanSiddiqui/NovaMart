import csv
import sys
from pathlib import Path


def analyze_benchmarks(csv_filepath):
    """Parse Locust CSV output and generate a board-ready report."""
    print("=====================================================")
    print("   NOVAMART FRIDAY PEAK BENCHMARK ANALYSIS REPORT    ")
    print("=====================================================\n")

    csv_path = Path(csv_filepath)

    try:
        with csv_path.open(mode="r", newline="", encoding="utf-8") as file:
            reader = csv.DictReader(file)

            for row in reader:
                if row.get("Name") == "Aggregated":
                    continue

                name = row.get("Name", "Unknown")
                requests = int(row.get("Request Count", 0) or 0)
                failures = int(row.get("Failure Count", 0) or 0)
                median_ms = row.get("Median Response Time", "0")
                p99_ms = row.get("99%", "0")

                success_rate = ((requests - failures) / requests * 100) if requests > 0 else 0

                print(f"Transaction: {name}")
                print(f"  Total Calls:      {requests:,}")
                print(f"  Failures:         {failures:,} ({100 - success_rate:.2f}%)")
                print(f"  Median Latency:   {median_ms} ms")
                print(f"  99th Percentile:  {p99_ms} ms")

                try:
                    if float(p99_ms) > 500:
                        print("  [!] WARNING: 99th percentile exceeds 500ms SLA.")
                    else:
                        print("  [PASS] Transaction meets SLA.")
                except ValueError:
                    print("  [!] WARNING: Could not parse percentile data.")

                print("-" * 53)

    except FileNotFoundError:
        print(f"Error: Could not find raw data file '{csv_filepath}'.")
        print("Please run ./run_benchmark.sh first.")
        sys.exit(1)


if __name__ == "__main__":
    analyze_benchmarks("novamart_friday_peak_stats.csv")