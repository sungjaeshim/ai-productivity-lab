#!/usr/bin/env python3
import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
from urllib.parse import urlparse

try:
    import requests
except Exception:
    print("requests is required: pip install requests", file=sys.stderr)
    raise

THRESHOLD_MB_DEFAULT = 10.0


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def safe_stem(value: str) -> str:
    s = pathlib.Path(value).stem or "audio"
    s = re.sub(r"[^A-Za-z0-9._-]+", "_", s)
    return s[:80]


def download_url(url: str, out_dir: pathlib.Path, timeout_sec: int = 300) -> pathlib.Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    with requests.get(url, stream=True, allow_redirects=True, timeout=timeout_sec) as r:
        r.raise_for_status()
        final_url = r.url
        cd = r.headers.get("content-disposition", "")

        fname = None
        m = re.search(r"filename\*=utf-8''([^;]+)", cd, re.I)
        if m:
            fname = requests.utils.unquote(m.group(1))
        elif "filename=" in cd:
            m2 = re.search(r'filename="?([^";]+)"?', cd)
            if m2:
                fname = m2.group(1)

        if not fname:
            parsed = urlparse(final_url)
            fname = os.path.basename(parsed.path) or "audio.bin"

        fname = fname.replace("/", "_")
        target = out_dir / fname
        with open(target, "wb") as f:
            for chunk in r.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    f.write(chunk)
    return target


def ffprobe_duration_seconds(path: pathlib.Path) -> float | None:
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        str(path),
    ]
    try:
        out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
        if not out:
            return None
        return float(out)
    except Exception:
        return None


def choose_route(size_mb: float, threshold_mb: float) -> tuple[str, str]:
    if size_mb <= threshold_mb:
        return "A", "small"
    return "B", "medium"


def recommend_timeouts(size_mb: float, duration_sec: float | None) -> dict:
    download_timeout = int(min(900, max(120, size_mb * 8)))
    if duration_sec is not None:
        whisper_timeout = int(max(1800, duration_sec * 2 + 600))
    else:
        whisper_timeout = int(max(1800, size_mb * 120))
    return {
        "downloadTimeoutSec": download_timeout,
        "whisperTimeoutSec": whisper_timeout,
    }


def run_whisper(audio_path: pathlib.Path, model: str, out_dir: pathlib.Path, timeout_sec: int) -> pathlib.Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    cmd = [
        "whisper",
        str(audio_path),
        "--model",
        model,
        "--language",
        "Korean",
        "--output_format",
        "txt",
        "--output_dir",
        str(out_dir),
    ]
    subprocess.run(cmd, check=True, timeout=timeout_sec)
    stem = pathlib.Path(audio_path).stem
    txt = out_dir / f"{stem}.txt"
    if not txt.exists():
        candidates = sorted(out_dir.glob(f"{stem}*.txt"))
        if not candidates:
            raise FileNotFoundError(f"Transcript not found in {out_dir}")
        txt = candidates[0]
    return txt


def main() -> int:
    ap = argparse.ArgumentParser(description="Audio route selector + optional Whisper runner")
    ap.add_argument("input", help="Local file path or URL")
    ap.add_argument("--threshold-mb", type=float, default=THRESHOLD_MB_DEFAULT)
    ap.add_argument("--download-dir", default="/root/.openclaw/workspace/tmp/audio-downloads")
    ap.add_argument("--transcript-dir", default="/root/.openclaw/workspace/transcripts")
    ap.add_argument("--run", action="store_true", help="Run Whisper after routing")
    ap.add_argument("--force-model", default=None, help="Override selected Whisper model")
    args = ap.parse_args()

    download_dir = pathlib.Path(args.download_dir)
    transcript_dir = pathlib.Path(args.transcript_dir)

    src = args.input.strip()
    is_url = src.startswith("http://") or src.startswith("https://")

    local_path: pathlib.Path
    if is_url:
        local_path = download_url(src, download_dir)
        source_kind = "url"
    else:
        local_path = pathlib.Path(src).expanduser().resolve()
        if not local_path.exists():
            raise FileNotFoundError(local_path)
        source_kind = "file"

    size_bytes = local_path.stat().st_size
    size_mb = size_bytes / (1024 * 1024)
    duration_sec = ffprobe_duration_seconds(local_path)

    route, model = choose_route(size_mb, args.threshold_mb)
    if args.force_model:
        model = args.force_model

    timeouts = recommend_timeouts(size_mb, duration_sec)

    job_id = hashlib.sha1(f"{local_path}-{size_bytes}-{now_iso()}".encode()).hexdigest()[:12]
    result = {
        "jobId": job_id,
        "createdAt": now_iso(),
        "sourceKind": source_kind,
        "input": src,
        "localPath": str(local_path),
        "sizeBytes": size_bytes,
        "sizeMB": round(size_mb, 2),
        "durationSec": round(duration_sec, 2) if duration_sec is not None else None,
        "thresholdMB": args.threshold_mb,
        "route": route,
        "model": model,
        "timeouts": timeouts,
        "status": "planned",
    }

    if args.run:
        txt = run_whisper(local_path, model, transcript_dir, timeouts["whisperTimeoutSec"])
        result["status"] = "done"
        result["transcriptPath"] = str(txt)

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
