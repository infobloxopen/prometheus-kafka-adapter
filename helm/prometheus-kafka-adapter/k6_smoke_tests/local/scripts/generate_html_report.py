#!/usr/bin/env python3
"""Generate HTML report from K6 JSON output — Grafana dashboard style."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def generate_html_report(json_file: str, output_file: str = "report.html"):
    """Parse K6 JSON summary and generate a Grafana-style HTML report."""
    data = json.loads(Path(json_file).read_text())
    metrics = data.get("metrics", {})
    root_group = data.get("root_group", {})

    # Core metrics
    checks = metrics.get("checks", {}).get("values", {})
    passes = int(checks.get("passes", 0))
    fails = int(checks.get("fails", 0))
    total = passes + fails
    rate = (passes / total) if total > 0 else 0
    rate_pct = rate * 100

    duration = metrics.get("iteration_duration", {}).get("values", {})
    exec_time_ms = duration.get("avg", 0)

    iterations = int(metrics.get("iterations", {}).get("values", {}).get("count", 0))

    http_duration = metrics.get("http_req_duration", {}).get("values", {})
    http_reqs = int(metrics.get("http_reqs", {}).get("values", {}).get("count", 0))

    data_recv = int(metrics.get("data_received", {}).get("values", {}).get("count", 0))
    data_sent = int(metrics.get("data_sent", {}).get("values", {}).get("count", 0))
    http_rate = metrics.get("http_reqs", {}).get("values", {}).get("rate", 0)

    skipped = 0  # K6 doesn't have skip concept

    # Status
    status_text = "PASS" if rate >= 0.8 else "FAIL"
    status_color = "#73BF69" if rate >= 0.8 else "#F2495C"

    # Per-group results from root_group.checks
    group_checks = root_group.get("checks", [])
    group_rows = ""
    for c in group_checks:
        c_passes = c.get("passes", 0)
        c_fails = c.get("fails", 0)
        c_total = c_passes + c_fails
        c_rate = (c_passes / c_total) if c_total > 0 else 0
        c_status = "PASS" if c_rate >= 0.8 else "FAIL"
        c_color = "#73BF69" if c_rate >= 0.8 else "#F2495C"
        group_rows += f"""        <tr>
          <td>{c.get("name", "")}</td>
          <td style="text-align:center"><span class="badge" style="background:{c_color}">{c_status}</span></td>
          <td style="text-align:center">{c_rate*100:.1f}%</td>
        </tr>\n"""

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PKA Smoke Test Report</title>
<style>
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{ font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif; background: #181b1f; color: #d8d9da; padding: 24px; }}
  .dashboard {{ max-width: 1400px; margin: 0 auto; }}
  .header {{ display: flex; align-items: center; justify-content: space-between; margin-bottom: 20px; padding: 16px 20px; background: #1f2228; border-radius: 8px; border: 1px solid #2c3035; }}
  .header h1 {{ font-size: 20px; font-weight: 600; color: #fff; }}
  .header .timestamp {{ font-size: 12px; color: #8e8e8e; }}
  .info-bar {{ background: #1f2228; border: 1px solid #2c3035; border-radius: 8px; padding: 16px 20px; margin-bottom: 20px; }}
  .info-bar table {{ width: 100%; border-collapse: collapse; }}
  .info-bar th {{ text-align: left; padding: 6px 12px; color: #8e8e8e; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; font-weight: 500; }}
  .info-bar td {{ padding: 6px 12px; font-size: 13px; color: #d8d9da; }}
  .info-bar code {{ background: #2c3035; padding: 2px 6px; border-radius: 3px; font-size: 12px; color: #73BF69; }}
  .stat-row {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 12px; }}
  .stat-row-3 {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-bottom: 20px; }}
  .stat-card {{ background: #1f2228; border: 1px solid #2c3035; border-radius: 8px; padding: 20px; text-align: center; }}
  .stat-card .label {{ font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; color: #8e8e8e; margin-bottom: 8px; }}
  .stat-card .value {{ font-size: 36px; font-weight: 700; }}
  .stat-card.status {{ background: {status_color}22; border-color: {status_color}44; }}
  .stat-card.status .value {{ color: {status_color}; }}
  .stat-card.pass-rate {{ background: {status_color}22; border-color: {status_color}44; }}
  .stat-card.pass-rate .value {{ color: {status_color}; }}
  .stat-card.exec-time .value {{ color: #56A64B; }}
  .stat-card.iterations .value {{ color: #56A64B; }}
  .stat-card.passed {{ background: #73BF6922; border-color: #73BF6944; }}
  .stat-card.passed .value {{ color: #73BF69; }}
  .stat-card.failed {{ background: {"#F2495C22" if fails > 0 else "#73BF6922"}; border-color: {"#F2495C44" if fails > 0 else "#73BF6944"}; }}
  .stat-card.failed .value {{ color: {"#F2495C" if fails > 0 else "#73BF69"}; }}
  .stat-card.skipped {{ background: #B877D922; border-color: #B877D944; }}
  .stat-card.skipped .value {{ color: #B877D9; }}
  .panel {{ background: #1f2228; border: 1px solid #2c3035; border-radius: 8px; margin-bottom: 20px; overflow: hidden; }}
  .panel-title {{ padding: 12px 20px; font-size: 14px; font-weight: 600; border-bottom: 1px solid #2c3035; color: #fff; }}
  .panel-body {{ padding: 16px 20px; }}
  table.results {{ width: 100%; border-collapse: collapse; }}
  table.results th {{ text-align: left; padding: 10px 12px; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; color: #8e8e8e; border-bottom: 1px solid #2c3035; font-weight: 500; }}
  table.results td {{ padding: 10px 12px; border-bottom: 1px solid #2c303544; font-size: 13px; }}
  table.results tr:last-child td {{ border-bottom: none; }}
  table.results tr:hover {{ background: #2c303544; }}
  .badge {{ display: inline-block; padding: 3px 10px; border-radius: 4px; font-size: 11px; font-weight: 700; color: #fff; letter-spacing: 0.5px; }}
  .http-panel {{ margin-bottom: 20px; }}
  .http-grid {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }}
  .http-stat {{ text-align: center; padding: 12px; }}
  .http-stat .label {{ font-size: 10px; color: #8e8e8e; text-transform: uppercase; margin-bottom: 4px; }}
  .http-stat .value {{ font-size: 18px; font-weight: 600; color: #d8d9da; }}
  .coverage-table {{ width: 100%; border-collapse: collapse; }}
  .coverage-table th {{ text-align: left; padding: 10px 12px; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; color: #8e8e8e; border-bottom: 1px solid #2c3035; font-weight: 500; }}
  .coverage-table td {{ padding: 10px 12px; border-bottom: 1px solid #2c303544; font-size: 13px; }}
  .coverage-table tr:last-child td {{ border-bottom: none; }}
</style>
</head>
<body>
<div class="dashboard">
  <!-- Header -->
  <div class="header">
    <h1>Prometheus Kafka Adapter — K6 Smoke Test Results</h1>
    <span class="timestamp">{timestamp}</span>
  </div>

  <!-- Test Info Bar -->
  <div class="info-bar">
    <table>
      <tr>
        <th>Service</th><th>Cluster</th><th>Scenarios</th><th>Threshold</th>
      </tr>
      <tr>
        <td><code>prometheus-kafka-adapter</code></td>
        <td><code>us-dev-5</code></td>
        <td>9 (SMOKE-001 → SMOKE-NEG-007)</td>
        <td>≥ 80% = PASS</td>
      </tr>
    </table>
  </div>

  <!-- Status Row: Status / Pass Rate / Execution Time / Iterations -->
  <div class="stat-row">
    <div class="stat-card status">
      <div class="label">Status</div>
      <div class="value">{status_text}</div>
    </div>
    <div class="stat-card pass-rate">
      <div class="label">Pass Rate</div>
      <div class="value">{rate_pct:.1f}%</div>
    </div>
    <div class="stat-card exec-time">
      <div class="label">Execution Time</div>
      <div class="value">{exec_time_ms:.0f}<span style="font-size:14px;color:#8e8e8e"> ms</span></div>
    </div>
    <div class="stat-card iterations">
      <div class="label">Iterations</div>
      <div class="value">{iterations}</div>
    </div>
  </div>

  <!-- Passed / Failed / Skipped -->
  <div class="stat-row-3">
    <div class="stat-card passed">
      <div class="label">Passed</div>
      <div class="value">{passes}</div>
    </div>
    <div class="stat-card failed">
      <div class="label">Failed</div>
      <div class="value">{fails}</div>
    </div>
    <div class="stat-card skipped">
      <div class="label">Skipped</div>
      <div class="value">{skipped}</div>
    </div>
  </div>

  <!-- Per-Group Results -->
  <div class="panel">
    <div class="panel-title">Per-Check Results</div>
    <div class="panel-body">
      <table class="results">
        <tr><th>Check Name</th><th style="text-align:center">Status</th><th style="text-align:center">Pass Rate</th></tr>
{group_rows}      </table>
    </div>
  </div>

  <!-- HTTP Performance -->
  <div class="panel http-panel">
    <div class="panel-title">HTTP Performance</div>
    <div class="panel-body">
      <div class="http-grid">
        <div class="http-stat"><div class="label">Requests</div><div class="value">{http_reqs}</div></div>
        <div class="http-stat"><div class="label">Avg Duration</div><div class="value">{http_duration.get("avg", 0):.2f} ms</div></div>
        <div class="http-stat"><div class="label">P95 Duration</div><div class="value">{http_duration.get("p(95)", 0):.2f} ms</div></div>
        <div class="http-stat"><div class="label">Min</div><div class="value">{http_duration.get("min", 0):.2f} ms</div></div>
        <div class="http-stat"><div class="label">Max</div><div class="value">{http_duration.get("max", 0):.2f} ms</div></div>
        <div class="http-stat"><div class="label">Median</div><div class="value">{http_duration.get("med", 0):.2f} ms</div></div>
      </div>
      <div class="http-grid" style="margin-top:12px">
        <div class="http-stat"><div class="label">Data Received</div><div class="value">{data_recv/1024:.1f} KB</div></div>
        <div class="http-stat"><div class="label">Data Sent</div><div class="value">{data_sent/1024:.1f} KB</div></div>
        <div class="http-stat"><div class="label">Req/s</div><div class="value">{http_rate:.2f}</div></div>
      </div>
    </div>
  </div>

  <!-- Endpoint Coverage -->
  <div class="panel">
    <div class="panel-title">Endpoint Coverage</div>
    <div class="panel-body">
      <table class="coverage-table">
        <tr><th>Scenario</th><th>Auth</th><th>Key Endpoints</th></tr>
        <tr><td>SMOKE-001 — Health Check</td><td>none</td><td>GET /healthz</td></tr>
        <tr><td>SMOKE-002 — Metrics Prometheus Endpoint</td><td>none</td><td>GET /metrics</td></tr>
        <tr><td>SMOKE-003 — Receive Endpoint Reachability</td><td>none</td><td>POST /receive</td></tr>
        <tr><td>SMOKE-004 — Metrics Counter Validation</td><td>none</td><td>GET /metrics</td></tr>
        <tr><td>SMOKE-NEG-001 — Non-Snappy Body</td><td>none</td><td>POST /receive</td></tr>
        <tr><td>SMOKE-NEG-002 — Invalid Protobuf</td><td>none</td><td>POST /receive</td></tr>
        <tr><td>SMOKE-NEG-003 — Empty Body</td><td>none</td><td>POST /receive</td></tr>
        <tr><td>SMOKE-NEG-004 — Invalid Credentials</td><td>basic</td><td>POST /receive</td></tr>
        <tr><td>SMOKE-NEG-005 — Missing Credentials</td><td>basic</td><td>POST /receive</td></tr>
        <tr><td>SMOKE-NEG-006 — Undefined Route</td><td>none</td><td>GET /undefined</td></tr>
        <tr><td>SMOKE-NEG-007 — Wrong Method</td><td>none</td><td>GET /receive</td></tr>
      </table>
    </div>
  </div>
</div>
</body>
</html>"""

    Path(output_file).parent.mkdir(parents=True, exist_ok=True)
    Path(output_file).write_text(html)
    print(f"Report generated: {output_file}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <k6-summary.json> [output.html]")
        sys.exit(1)
    reports_dir = Path(__file__).resolve().parent.parent / "reports"
    reports_dir.mkdir(parents=True, exist_ok=True)
    default_out = str(reports_dir / "report.html")
    out = sys.argv[2] if len(sys.argv) > 2 else default_out
    generate_html_report(sys.argv[1], out)
