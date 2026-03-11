#!/usr/bin/env python3
import argparse
import json
import pathlib
import subprocess
import sys
import time
from datetime import datetime, timezone
from hashlib import sha1

from audio_route import (
    choose_route,
    download_url,
    ffprobe_duration_seconds,
    recommend_timeouts,
    run_whisper,
)

STATE_DIR = pathlib.Path('/root/.openclaw/workspace/.state/audio-jobs')
DOWNLOAD_DIR = pathlib.Path('/root/.openclaw/workspace/tmp/audio-downloads')
TRANSCRIPT_DIR = pathlib.Path('/root/.openclaw/workspace/transcripts')
LOG_DIR = pathlib.Path('/root/.openclaw/workspace/logs/audio-jobs')


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def is_url(s: str) -> bool:
    return s.startswith('http://') or s.startswith('https://')


def make_job_id(source: str) -> str:
    raw = f"{source}|{time.time()}".encode()
    return sha1(raw).hexdigest()[:12]


def write_json(path: pathlib.Path, data: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2))


def load_json(path: pathlib.Path) -> dict:
    return json.loads(path.read_text())


def plan_job(source: str, threshold_mb: float, speed_model: str, quality_model: str) -> dict:
    if is_url(source):
        local_path = download_url(source, DOWNLOAD_DIR)
        source_kind = 'url'
    else:
        local_path = pathlib.Path(source).expanduser().resolve()
        if not local_path.exists():
            raise FileNotFoundError(local_path)
        source_kind = 'file'

    size_bytes = local_path.stat().st_size
    size_mb = size_bytes / (1024 * 1024)
    duration_sec = ffprobe_duration_seconds(local_path)
    route, _ = choose_route(size_mb, threshold_mb)
    model = speed_model if route == 'A' else quality_model
    timeouts = recommend_timeouts(size_mb, duration_sec)

    return {
        'jobId': make_job_id(source),
        'createdAt': now_iso(),
        'updatedAt': now_iso(),
        'status': 'queued',
        'source': source,
        'sourceKind': source_kind,
        'localPath': str(local_path),
        'sizeBytes': size_bytes,
        'sizeMB': round(size_mb, 2),
        'durationSec': round(duration_sec, 2) if duration_sec is not None else None,
        'thresholdMB': threshold_mb,
        'route': route,
        'model': model,
        'timeouts': timeouts,
        'transcriptPath': None,
        'error': None,
    }


def run_job(job_file: pathlib.Path) -> dict:
    job = load_json(job_file)
    job['status'] = 'running'
    job['updatedAt'] = now_iso()
    write_json(job_file, job)

    try:
        txt = run_whisper(
            pathlib.Path(job['localPath']),
            job['model'],
            TRANSCRIPT_DIR,
            int(job['timeouts']['whisperTimeoutSec']),
        )
        job['status'] = 'done'
        job['transcriptPath'] = str(txt)
    except subprocess.TimeoutExpired:
        job['status'] = 'failed'
        job['error'] = 'TIMEOUT'
    except Exception as e:
        job['status'] = 'failed'
        job['error'] = f'TRANSCRIBE_FAIL: {e}'

    job['updatedAt'] = now_iso()
    write_json(job_file, job)
    return job


def cmd_start(args) -> int:
    plan = plan_job(args.input, args.threshold_mb, args.speed_model, args.quality_model)
    job_file = STATE_DIR / f"{plan['jobId']}.json"
    write_json(job_file, plan)

    if plan['route'] == 'A' and not args.force_detach:
        result = run_job(job_file)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0

    # Route B (or forced detach): run worker process in background
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_file = LOG_DIR / f"{plan['jobId']}.log"
    cmd = [
        sys.executable,
        str(pathlib.Path(__file__).resolve()),
        '_worker',
        '--job-file',
        str(job_file),
    ]
    with open(log_file, 'ab') as lf:
        proc = subprocess.Popen(
            cmd,
            stdout=lf,
            stderr=lf,
            start_new_session=True,
        )

    plan['status'] = 'dispatched'
    plan['updatedAt'] = now_iso()
    plan['pid'] = proc.pid
    plan['logPath'] = str(log_file)
    write_json(job_file, plan)

    print(json.dumps(plan, ensure_ascii=False, indent=2))
    return 0


def cmd_status(args) -> int:
    job_file = STATE_DIR / f"{args.job_id}.json"
    if not job_file.exists():
        print(json.dumps({'error': 'JOB_NOT_FOUND', 'jobId': args.job_id}, ensure_ascii=False))
        return 2
    print(job_file.read_text())
    return 0


def cmd_worker(args) -> int:
    job_file = pathlib.Path(args.job_file)
    run_job(job_file)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description='Audio auto-router with 10MB split policy')
    sub = ap.add_subparsers(dest='cmd', required=True)

    p_start = sub.add_parser('start', help='Create and run/dispatch a job')
    p_start.add_argument('input', help='URL or local file')
    p_start.add_argument('--threshold-mb', type=float, default=10.0)
    p_start.add_argument('--speed-model', default='small')
    p_start.add_argument('--quality-model', default='medium')
    p_start.add_argument('--force-detach', action='store_true', help='Detach even for route A')
    p_start.set_defaults(func=cmd_start)

    p_status = sub.add_parser('status', help='Show job status')
    p_status.add_argument('job_id')
    p_status.set_defaults(func=cmd_status)

    p_worker = sub.add_parser('_worker', help=argparse.SUPPRESS)
    p_worker.add_argument('--job-file', required=True)
    p_worker.set_defaults(func=cmd_worker)

    args = ap.parse_args()
    return args.func(args)


if __name__ == '__main__':
    raise SystemExit(main())
