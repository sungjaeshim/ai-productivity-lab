#!/usr/bin/env python3
"""Compatibility shim for archived notion_log.py.

Keeps legacy cron/manual invocations working after archival move.
"""

from __future__ import annotations

import os
import runpy
import sys
from pathlib import Path

ARCHIVED = Path(__file__).resolve().parent / "_attic" / "2026-03" / "notion_log.py"

if not ARCHIVED.exists():
    print(
        f"[notion_log shim] archived target missing: {ARCHIVED}",
        file=sys.stderr,
    )
    sys.exit(2)

# Keep argv semantics identical for the archived script.
sys.argv[0] = str(ARCHIVED)
runpy.run_path(str(ARCHIVED), run_name="__main__")
