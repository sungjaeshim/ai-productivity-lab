#!/usr/bin/env python3
import argparse, json, pathlib, subprocess, sys
from datetime import datetime, timezone


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def extract_with_pdftotext(pdf_path: pathlib.Path, txt_path: pathlib.Path):
    cmd = ["pdftotext", "-layout", str(pdf_path), str(txt_path)]
    subprocess.run(cmd, check=True)


def main():
    ap = argparse.ArgumentParser(description="Extract text from PDF to txt/json metadata")
    ap.add_argument("pdf")
    ap.add_argument("--out-dir", default="/root/.openclaw/workspace/documents")
    args = ap.parse_args()

    pdf_path = pathlib.Path(args.pdf).expanduser().resolve()
    if not pdf_path.exists():
        raise FileNotFoundError(pdf_path)

    out_dir = pathlib.Path(args.out_dir).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    stem = pdf_path.stem
    txt_path = out_dir / f"{stem}.txt"
    meta_path = out_dir / f"{stem}.json"

    extract_with_pdftotext(pdf_path, txt_path)

    text = txt_path.read_text(encoding="utf-8", errors="ignore") if txt_path.exists() else ""
    result = {
        "status": "done",
        "createdAt": now_iso(),
        "pdfPath": str(pdf_path),
        "textPath": str(txt_path),
        "chars": len(text),
        "preview": text[:1000],
    }
    meta_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    raise SystemExit(main())
