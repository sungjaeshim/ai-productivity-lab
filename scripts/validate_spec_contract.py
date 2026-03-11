#!/usr/bin/env python3
"""
SPEC contract validator.

Checks:
1) Required 18 headings
2) Mandatory gates (RFE/RFT/FUT)
3) PoW appendix contract (Full PoW default + required evidence fields)
4) Hangul outside HTML comments
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

SPEC_PATH = Path(__file__).resolve().parents[1] / "SPEC.md"

REQUIRED_HEADINGS = [
    "## 1. Problem Statement",
    "## 2. Goals and Non-Goals",
    "## 3. System Overview",
    "## 4. Core Domain Model",
    "## 5. Workflow Specification (Repository Contract)",
    "## 6. Configuration Specification",
    "## 7. Orchestration State Machine",
    "## 8. Polling, Scheduling, and Reconciliation",
    "## 9. Workspace Management and Safety",
    "## 10. Runner Protocol (Agent Integration)",
    "## 11. Integration Contract",
    "## 12. Prompt Construction and Context Assembly",
    "## 13. Observability (Logs/Metrics/Status)",
    "## 14. Failure Model and Recovery Strategy",
    "## 15. Security and Operational Safety",
    "## 16. Reference Algorithms (Pseudo)",
    "## 17. Test and Validation Matrix",
    "## 18. Implementation Checklist (Definition of Done)",
]

MANDATORY_GATES = ["RFE Gate", "RFT Gate", "FUT Decision"]
POW_REQUIRED_MARKERS = [
    "Appendix B: Proof of Work (PoW) Evidence Gate (Normative)",
    "Full PoW (quality-first, default for production-bound changes)",
    "CI Evidence",
    "PR Review Evidence",
    "Test Evidence",
    "Change Summary Evidence",
    "Rollback Evidence",
    "Gate Decision Rules",
    "Automation Hook Contract",
]
HANGUL_RE = re.compile(r"[\u3131-\u318E\uAC00-\uD7A3]")


def find_hangul_outside_comments(lines: list[str]) -> list[tuple[int, str]]:
    violations: list[tuple[int, str]] = []
    in_comment = False

    for i, line in enumerate(lines, start=1):
        remaining = line

        while True:
            start = remaining.find("<!--")
            if start == -1:
                if not in_comment and HANGUL_RE.search(remaining):
                    violations.append((i, remaining.strip()))
                break

            before = remaining[:start]
            if not in_comment and HANGUL_RE.search(before):
                violations.append((i, before.strip()))

            remaining = remaining[start + 4 :]
            end = remaining.find("-->")

            if end == -1:
                in_comment = True
                break

            remaining = remaining[end + 3 :]
            in_comment = False

    return violations


def main() -> int:
    if not SPEC_PATH.exists():
        print(f"ERROR: missing spec file: {SPEC_PATH}")
        return 2

    text = SPEC_PATH.read_text(encoding="utf-8")
    lines = text.splitlines()

    missing_headings = [h for h in REQUIRED_HEADINGS if h not in text]
    missing_gates = [g for g in MANDATORY_GATES if g not in text]
    missing_pow_markers = [m for m in POW_REQUIRED_MARKERS if m not in text]
    hangul_violations = find_hangul_outside_comments(lines)

    print("SPEC Contract Validation Report")
    print("-" * 40)
    print(f"Spec path: {SPEC_PATH}")
    print(f"Missing required headings: {len(missing_headings)}")
    for h in missing_headings:
        print(f"  - {h}")

    print(f"Missing mandatory gates: {len(missing_gates)}")
    for g in missing_gates:
        print(f"  - {g}")

    print(f"Missing PoW markers: {len(missing_pow_markers)}")
    for m in missing_pow_markers:
        print(f"  - {m}")

    print(f"Hangul outside HTML comments: {len(hangul_violations)}")
    for line_no, snippet in hangul_violations[:10]:
        print(f"  - line {line_no}: {snippet[:120]}")

    if (
        not missing_headings
        and not missing_gates
        and not missing_pow_markers
        and not hangul_violations
    ):
        print("RESULT: PASS")
        return 0

    print("RESULT: FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
