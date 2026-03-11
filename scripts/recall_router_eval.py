#!/usr/bin/env python3
"""
Recall Router Evaluator - Evaluate routing performance.

Metrics:
- route_p95: 95th percentile latency per route
- fallback_rate_estimate: Estimated rate of semantic-to-lexical fallbacks
- top3_hit_rate: Percentage of queries with at least 3 results
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

ROOT = Path('/root/.openclaw/workspace')
FIXTURE_FILE = ROOT / 'data' / 'recall_eval_samples.json'
LOG_FILE = ROOT / '.state' / 'recall_router.log.jsonl'


# Default evaluation samples
DEFAULT_SAMPLES = [
    {"query": "어제 결정", "mode": "temporal", "expected_route": "lexical"},
    {"query": "memory_search fallback 정책", "mode": "topic", "expected_route": "semantic"},
    {"query": "아키텍처 설계 원칙", "mode": "topic", "expected_route": "semantic"},
    {"query": "지난주 회의록", "mode": "temporal", "expected_route": "lexical"},
    {"query": "관련된 링크", "mode": "graph", "expected_route": "hybrid"},
    {"query": "최근 변경사항", "mode": "temporal", "expected_route": "lexical"},
    {"query": "방법론 패턴", "mode": "topic", "expected_route": "semantic"},
    {"query": "연결된 참조", "mode": "graph", "expected_route": "hybrid"},
    {"query": "이번 달 목표", "mode": "temporal", "expected_route": "lexical"},
    {"query": "framework 정의", "mode": "topic", "expected_route": "semantic"},
    {"query": "의존성 관계", "mode": "graph", "expected_route": "hybrid"},
    {"query": "작년 리포트", "mode": "temporal", "expected_route": "lexical"},
    {"query": "strategy 전략", "mode": "topic", "expected_route": "semantic"},
    {"query": "참조 연결", "mode": "graph", "expected_route": "hybrid"},
    {"query": "주간 회고", "mode": "temporal", "expected_route": "lexical"},
    {"query": "design concept", "mode": "topic", "expected_route": "semantic"},
    {"query": "related connection", "mode": "graph", "expected_route": "hybrid"},
    {"query": "월간 목표", "mode": "temporal", "expected_route": "lexical"},
    {"query": "methodology 패턴", "mode": "topic", "expected_route": "semantic"},
    {"query": "dependency 맵", "mode": "graph", "expected_route": "hybrid"}
]


def load_samples() -> list[dict]:
    """Load evaluation samples from file or use defaults."""
    if FIXTURE_FILE.exists():
        with open(FIXTURE_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    else:
        # Create fixture file with defaults
        FIXTURE_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(FIXTURE_FILE, 'w', encoding='utf-8') as f:
            json.dump(DEFAULT_SAMPLES, f, ensure_ascii=False, indent=2)
        return DEFAULT_SAMPLES


def run_query(query: str, mode: str, query_timeout: int = 15) -> dict:
    """Run a single query via recall_router.py."""
    try:
        result = subprocess.run(
            [sys.executable, str(ROOT / 'scripts' / 'recall_router.py'),
             '--query', query, '--mode', mode, '--json'],
            capture_output=True,
            text=True,
            timeout=query_timeout
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
        else:
            return {'error': result.stderr, 'route': 'error', 'result_count': 0, 'latency_ms': 0}
    except subprocess.TimeoutExpired:
        return {'error': 'timeout', 'route': 'error', 'result_count': 0, 'latency_ms': query_timeout * 1000}
    except Exception as e:
        return {'error': str(e), 'route': 'error', 'result_count': 0, 'latency_ms': 0}


def calculate_p95(values: list[float]) -> float:
    """Calculate 95th percentile."""
    if not values:
        return 0.0
    sorted_values = sorted(values)
    idx = int(len(sorted_values) * 0.95)
    return sorted_values[min(idx, len(sorted_values) - 1)]


def evaluate(samples: list[dict], query_timeout: int = 15) -> tuple[dict, list[dict]]:
    """Run evaluation on samples."""
    results = []

    for sample in samples:
        query = sample['query']
        mode = sample['mode']
        expected_route = sample.get('expected_route', 'hybrid')

        print(f"Running: {query[:30]}... ({mode})", file=sys.stderr)
        result = run_query(query, mode, query_timeout=query_timeout)

        results.append({
            'query': query,
            'mode': mode,
            'expected_route': expected_route,
            'actual_route': result.get('route', 'error'),
            'result_count': result.get('result_count', 0),
            'latency_ms': result.get('latency_ms', 0),
            'error': result.get('error')
        })

    # Calculate metrics per route
    route_metrics = {}
    all_latencies = []
    top3_hits = 0

    for r in results:
        route = r['actual_route']
        latency = r['latency_ms']
        all_latencies.append(latency)

        if r['result_count'] >= 3:
            top3_hits += 1

        if route == 'error':
            continue

        if route not in route_metrics:
            route_metrics[route] = {'latencies': [], 'count': 0, 'fallbacks': 0}
        route_metrics[route]['latencies'].append(latency)
        route_metrics[route]['count'] += 1

        # Count fallbacks (semantic queries that returned lexical results)
        # We'll estimate this by checking if semantic route was expected but results are low
        if r['expected_route'] == 'semantic' and route == 'lexical':
            route_metrics[route]['fallbacks'] += 1

    # Calculate p95 per route
    route_p95 = {}
    for route, data in route_metrics.items():
        if data['latencies']:
            route_p95[route] = calculate_p95(data['latencies'])

    # Estimate fallback rate
    total_semantic = route_metrics.get('semantic', {}).get('count', 0)
    semantic_fallbacks = route_metrics.get('semantic', {}).get('fallbacks', 0)
    fallback_rate = (semantic_fallbacks / total_semantic * 100) if total_semantic > 0 else 0.0

    # Calculate top3 hit rate
    top3_hit_rate = (top3_hits / len(results) * 100) if results else 0.0

    # Route agreement (expected vs actual)
    route_match_rate = (
        sum(1 for r in results if r.get('actual_route') == r.get('expected_route')) / len(results) * 100
        if results else 0.0
    )

    metrics = {
        'timestamp': datetime.now().isoformat(),
        'sample_count': len(samples),
        'query_timeout_sec': query_timeout,
        'route_p95': route_p95,
        'fallback_rate_estimate': round(fallback_rate, 2),
        'top3_hit_rate': round(top3_hit_rate, 2),
        'route_match_rate': round(route_match_rate, 2),
        'total_queries': len(results),
        'successful_queries': sum(1 for r in results if r['error'] is None),
        'error_count': sum(1 for r in results if r['error'])
    }

    return metrics, results


def load_baseline() -> dict | None:
    """Load previous baseline metrics for regression detection."""
    baseline_file = ROOT / '.state' / 'recall_router_baseline.json'
    if baseline_file.exists():
        with open(baseline_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    return None


def save_baseline(metrics: dict) -> None:
    """Save current metrics as new baseline."""
    baseline_file = ROOT / '.state' / 'recall_router_baseline.json'
    baseline_file.parent.mkdir(parents=True, exist_ok=True)
    # Store only essential metrics for regression comparison
    baseline = {
        'timestamp': metrics.get('timestamp'),
        'top3_hit_rate': metrics.get('top3_hit_rate'),
        'route_match_rate': metrics.get('route_match_rate'),
        'error_count': metrics.get('error_count'),
        'route_p95': metrics.get('route_p95', {}),
        'sample_count': metrics.get('sample_count'),
    }
    with open(baseline_file, 'w', encoding='utf-8') as f:
        json.dump(baseline, f, ensure_ascii=False, indent=2)


def build_gate_result(
    metrics: dict,
    *,
    min_top3_hit_rate: float,
    max_hybrid_p95: float,
    max_error_count: int,
    min_route_match_rate: float,
    baseline: dict | None = None,
    regression_tolerance: float = 5.0,  # % degradation allowed
) -> dict:
    """Build pass/fail gate from key recall metrics with regression detection."""
    checks: list[dict[str, Any]] = []

    top3 = float(metrics.get('top3_hit_rate', 0.0))
    checks.append({
        'name': 'top3_hit_rate',
        'value': top3,
        'op': '>=',
        'target': min_top3_hit_rate,
        'pass': top3 >= min_top3_hit_rate,
    })

    hybrid_p95 = float(metrics.get('route_p95', {}).get('hybrid', 0.0))
    checks.append({
        'name': 'hybrid_p95_ms',
        'value': hybrid_p95,
        'op': '<=',
        'target': max_hybrid_p95,
        'pass': hybrid_p95 <= max_hybrid_p95,
    })

    errors = int(metrics.get('error_count', 0))
    checks.append({
        'name': 'error_count',
        'value': errors,
        'op': '<=',
        'target': max_error_count,
        'pass': errors <= max_error_count,
    })

    route_match = float(metrics.get('route_match_rate', 0.0))
    checks.append({
        'name': 'route_match_rate',
        'value': route_match,
        'op': '>=',
        'target': min_route_match_rate,
        'pass': route_match >= min_route_match_rate,
    })

    # Regression detection against baseline
    if baseline:
        # top3_hit_rate regression
        baseline_top3 = float(baseline.get('top3_hit_rate', 0.0))
        if baseline_top3 > 0:
            top3_delta = top3 - baseline_top3
            top3_regression_pass = top3_delta >= -regression_tolerance
            checks.append({
                'name': 'top3_vs_baseline',
                'value': top3,
                'baseline': baseline_top3,
                'delta': round(top3_delta, 2),
                'tolerance': -regression_tolerance,
                'pass': top3_regression_pass,
            })

        # route_match_rate regression
        baseline_match = float(baseline.get('route_match_rate', 0.0))
        if baseline_match > 0:
            match_delta = route_match - baseline_match
            match_regression_pass = match_delta >= -regression_tolerance
            checks.append({
                'name': 'route_match_vs_baseline',
                'value': route_match,
                'baseline': baseline_match,
                'delta': round(match_delta, 2),
                'tolerance': -regression_tolerance,
                'pass': match_regression_pass,
            })

        # latency regression (hybrid_p95 should not increase significantly)
        baseline_hybrid_p95 = float(baseline.get('route_p95', {}).get('hybrid', 0.0))
        if baseline_hybrid_p95 > 0:
            latency_increase_pct = ((hybrid_p95 - baseline_hybrid_p95) / baseline_hybrid_p95) * 100
            latency_regression_pass = latency_increase_pct <= regression_tolerance
            checks.append({
                'name': 'latency_vs_baseline',
                'value': hybrid_p95,
                'baseline': baseline_hybrid_p95,
                'increase_pct': round(latency_increase_pct, 2),
                'tolerance_pct': regression_tolerance,
                'pass': latency_regression_pass,
            })

    gate_pass = all(c['pass'] for c in checks)
    failed = [c for c in checks if not c['pass']]
    return {
        'pass': gate_pass,
        'checks': checks,
        'failed_count': len(failed),
        'failed_checks': failed,
        'has_baseline': baseline is not None,
    }


def print_report(metrics: dict, results: list[dict], gate: dict | None = None) -> None:
    """Print evaluation report."""
    print("\n" + "=" * 60)
    print("RECALL ROUTER EVALUATION REPORT")
    print("=" * 60)
    print(f"Timestamp: {metrics['timestamp']}")
    print(f"Samples: {metrics['sample_count']}")
    print(f"Successful: {metrics['successful_queries']}/{metrics['total_queries']}")
    print(f"Errors: {metrics['error_count']}")
    print()
    print("METRICS")
    print("-" * 60)
    print(f"Top-3 Hit Rate: {metrics['top3_hit_rate']:.1f}%")
    print(f"Route Match Rate: {metrics.get('route_match_rate', 0.0):.1f}%")
    print(f"Fallback Rate Estimate: {metrics['fallback_rate_estimate']:.1f}%")
    print()
    print("Route P95 Latency (ms):")
    for route, p95 in metrics['route_p95'].items():
        print(f"  {route:12s}: {p95:.2f}ms")
    print()

    if gate is not None:
        print("GATE")
        print("-" * 60)
        print(f"PASS: {gate.get('pass')}")
        for c in gate.get('checks', []):
            mark = 'OK' if c.get('pass') else 'FAIL'
            print(f"  [{mark}] {c['name']}: {c['value']} {c['op']} {c['target']}")
        print()

    # Print per-query details if verbose
    if '--verbose' in sys.argv:
        print("QUERY DETAILS")
        print("-" * 60)
        for r in results:
            status = "OK" if r['error'] is None else f"ERR: {r['error']}"
            print(f"{r['query'][:40]:40s} | {r['mode']:8s} | {r['actual_route']:8s} | {r['result_count']:2d} | {status}")


def main():
    parser = argparse.ArgumentParser(description='Recall Router Evaluator')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    parser.add_argument('--json', action='store_true', help='Output JSON format')
    parser.add_argument('--offset', type=int, default=0, help='Start index for sample slicing')
    parser.add_argument('--limit', type=int, default=0, help='Max sample count after offset (0 means all)')
    parser.add_argument('--query-timeout', type=int, default=15, help='Per-query timeout in seconds')
    parser.add_argument('--min-top3-hit-rate', type=float, default=90.0, help='Gate threshold: minimum top3 hit rate')
    parser.add_argument('--max-hybrid-p95', type=float, default=35.0, help='Gate threshold: maximum hybrid p95 latency (ms)')
    parser.add_argument('--max-error-count', type=int, default=0, help='Gate threshold: maximum error count')
    parser.add_argument('--min-route-match-rate', type=float, default=95.0, help='Gate threshold: minimum route match rate')
    parser.add_argument('--save-baseline', action='store_true', help='Save current metrics as new baseline when gate passes')
    parser.add_argument('--fail-on-regression', action='store_true', help='Exit code 2 when gate fails')

    args = parser.parse_args()

    # Load and slice samples (for timeout-safe micro-batches)
    all_samples = load_samples()
    offset = max(args.offset, 0)
    if args.limit > 0:
        samples = all_samples[offset: offset + args.limit]
    else:
        samples = all_samples[offset:]

    # Run evaluation
    effective_timeout = max(args.query_timeout, 1)
    metrics, results = evaluate(samples, query_timeout=effective_timeout)
    metrics['sample_offset'] = offset
    metrics['sample_limit'] = args.limit
    metrics['sample_total_available'] = len(all_samples)

    # Load baseline for regression detection
    baseline = load_baseline()

    gate = build_gate_result(
        metrics,
        min_top3_hit_rate=args.min_top3_hit_rate,
        max_hybrid_p95=args.max_hybrid_p95,
        max_error_count=args.max_error_count,
        min_route_match_rate=args.min_route_match_rate,
        baseline=baseline,
        regression_tolerance=5.0,
    )

    # Save new baseline if gate passes and --save-baseline flag
    if gate.get('pass') and '--save-baseline' in sys.argv:
        save_baseline(metrics)
        if not args.json:
            print("Baseline saved.", file=sys.stderr)

    # Print report
    if args.json:
        output = {
            'metrics': metrics,
            'gate': gate,
            'results': results
        }
        print(json.dumps(output, ensure_ascii=False, indent=2))
    else:
        print_report(metrics, results, gate=gate)

    # Save metrics to file
    metrics_file = ROOT / '.state' / 'recall_router_eval_metrics.json'
    with open(metrics_file, 'w', encoding='utf-8') as f:
        json.dump({'metrics': metrics, 'gate': gate}, f, ensure_ascii=False, indent=2)

    if not args.json:
        print(f"\nMetrics saved to: {metrics_file}")

    if args.fail_on_regression and not gate.get('pass', False):
        sys.exit(2)


if __name__ == '__main__':
    main()
