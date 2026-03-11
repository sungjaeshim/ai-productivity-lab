#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path('/root/.openclaw/workspace')
LATEST_PATH = ROOT / 'data' / 'ralph-experiments' / 'latest.json'


def load_json(path: Path) -> dict[str, Any] | None:
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except Exception:
        return None


def build_experiment_card() -> dict[str, Any]:
    payload = load_json(LATEST_PATH)
    if not payload:
        return {
            'title': '야간 후보 실험 승인',
            'bullets': ['야간 후보 실험: 승인 요청 없음 (artifact 없음)'],
            'status': 'missing',
        }

    best = payload.get('best_candidate') or {}
    baseline = payload.get('baseline') or {}
    status = str(best.get('status') or 'none')

    if status not in {'shortlisted', 'held'}:
        reason = str(payload.get('summary') or best.get('status') or '기준 미통과 또는 후보 없음')
        return {
            'title': '야간 후보 실험 승인',
            'bullets': [f'야간 후보 실험: 승인 요청 없음 ({reason})'],
            'status': status,
        }

    candidate_id = str(best.get('id') or best.get('candidate_id') or '(unnamed)')
    experiment = str(payload.get('experiment') or 'unknown')
    baseline_score = baseline.get('score')
    candidate_score = best.get('score')
    delta = best.get('delta')
    risk_summary = str(best.get('risk_summary') or '특이 리스크 없음')
    change_summary = str(best.get('change_summary') or '변경 요약 없음')
    recommendation = 'A. 오늘 승인 후 반영 / B. 하루 더 hold / C. 폐기'

    evidence = best.get('evidence') or {}
    samples = evidence.get('samples')
    wins = evidence.get('wins')
    losses = evidence.get('losses')
    ties = evidence.get('ties')
    evidence_line = []
    if samples is not None:
        evidence_line.append(f'샘플 {samples}')
    if wins is not None:
        evidence_line.append(f'우세 {wins}')
    if ties is not None:
        evidence_line.append(f'동률 {ties}')
    if losses is not None:
        evidence_line.append(f'열세 {losses}')

    bullets = [
        f'후보: {candidate_id} | 실험: {experiment}',
        f'baseline: {baseline_score} | candidate: {candidate_score} | 개선폭: {delta}',
        f'변경 내용: {change_summary}',
        f'리스크: {risk_summary}',
    ]
    if evidence_line:
        bullets.append('근거: ' + ' / '.join(evidence_line))
    bullets.append(f'권장안: {recommendation}')

    return {
        'title': '야간 후보 실험 승인',
        'bullets': bullets,
        'status': status,
    }


if __name__ == '__main__':
    print(json.dumps(build_experiment_card(), ensure_ascii=False, indent=2))
