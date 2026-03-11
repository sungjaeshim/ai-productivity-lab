#!/usr/bin/env python3
import os
import json
from datetime import datetime, timezone
import yfinance as yf

STATE_DIR = '/root/.openclaw/workspace/.state'
STATE_FILE = os.path.join(STATE_DIR, 'market-sentiment-last.txt')
STATE_JSON = os.path.join(STATE_DIR, 'market_sentiment_state.json')


def get_float(path, default=0.0):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return float(f.read().strip())
    except Exception:
        return default


def set_float(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(f'{value:.4f}')


def load_json(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {}


def main():
    # 단순 리스크 감성 점수: (NQ 1h 수익률*100) - (VIX 1h 수익률*2)
    # A안: 진입/해제 분리 + 연속 N회 + 같은 방향 재알림 쿨다운
    entry_delta = float(os.environ.get('MARKET_SENTIMENT_ENTRY_DELTA', '15.0'))
    exit_delta = float(os.environ.get('MARKET_SENTIMENT_EXIT_DELTA', '8.0'))
    consecutive_required = int(os.environ.get('MARKET_SENTIMENT_CONSECUTIVE', '2'))
    cooldown_seconds = int(os.environ.get('MARKET_SENTIMENT_COOLDOWN_SECONDS', str(180 * 60)))

    nq = yf.Ticker('NQ=F').history(period='5d', interval='1h')
    vix = yf.Ticker('^VIX').history(period='5d', interval='1h')
    if len(nq) < 2 or len(vix) < 2:
        print('ALERT MKT|market_sentiment_delta.py|NO_DATA sentiment 데이터 부족')
        return

    nq_c = nq['Close']
    vix_c = vix['Close']
    nq_ret = (float(nq_c.iloc[-1]) / float(nq_c.iloc[-2]) - 1.0) * 100.0
    vix_ret = (float(vix_c.iloc[-1]) / float(vix_c.iloc[-2]) - 1.0) * 100.0

    score = nq_ret * 100.0 - (vix_ret * 2.0)
    prev_score = get_float(STATE_FILE, default=score)
    delta = score - prev_score

    prev_state = load_json(STATE_JSON)
    prev_regime = prev_state.get('regime', 'NORMAL')
    up_streak = int(prev_state.get('up_streak', 0) or 0)
    down_streak = int(prev_state.get('down_streak', 0) or 0)
    last_alert_kind = prev_state.get('last_alert_kind')
    last_alert_ts = float(prev_state.get('last_alert_ts', 0) or 0)

    # streak 업데이트
    if delta >= entry_delta:
        up_streak += 1
    else:
        up_streak = 0

    if delta <= -entry_delta:
        down_streak += 1
    else:
        down_streak = 0

    now_ts = datetime.now(timezone.utc).timestamp()
    new_regime = prev_regime

    # hysteresis + 연속 확인
    if prev_regime == 'NORMAL':
        if up_streak >= consecutive_required:
            new_regime = 'UP'
        elif down_streak >= consecutive_required:
            new_regime = 'DOWN'
    elif prev_regime == 'UP':
        if down_streak >= consecutive_required:
            new_regime = 'DOWN'
        elif abs(delta) <= exit_delta:
            new_regime = 'NORMAL'
    elif prev_regime == 'DOWN':
        if up_streak >= consecutive_required:
            new_regime = 'UP'
        elif abs(delta) <= exit_delta:
            new_regime = 'NORMAL'

    event_type = None
    alert = False

    # 신규 진입/방향전환은 즉시 알림
    if new_regime != prev_regime:
        if new_regime == 'UP':
            event_type = 'SENTIMENT_JUMP_UP'
            alert = True
        elif new_regime == 'DOWN':
            event_type = 'SENTIMENT_JUMP_DOWN'
            alert = True
    else:
        # 같은 방향 유지 시 재알림은 쿨다운 통과 시만
        cooled = (now_ts - last_alert_ts) >= cooldown_seconds
        if new_regime == 'UP' and delta >= entry_delta and cooled and last_alert_kind == 'SENTIMENT_JUMP_UP':
            event_type = 'SENTIMENT_JUMP_UP'
            alert = True
        elif new_regime == 'DOWN' and delta <= -entry_delta and cooled and last_alert_kind == 'SENTIMENT_JUMP_DOWN':
            event_type = 'SENTIMENT_JUMP_DOWN'
            alert = True

    set_float(STATE_FILE, score)

    payload = {
        'score': round(score, 4),
        'delta': round(delta, 4),
        'entry_delta': entry_delta,
        'exit_delta': exit_delta,
        'consecutive_required': consecutive_required,
        'cooldown_seconds': cooldown_seconds,
        'regime': new_regime,
        'up_streak': up_streak,
        'down_streak': down_streak,
        'event_type': event_type,
        'alert': alert,
        'updated_at': datetime.now(timezone.utc).isoformat(),
        'last_alert_kind': last_alert_kind,
        'last_alert_ts': int(last_alert_ts) if last_alert_ts else None,
    }

    if alert and event_type:
        payload['last_alert_kind'] = event_type
        payload['last_alert_ts'] = int(now_ts)

    os.makedirs(STATE_DIR, exist_ok=True)
    with open(STATE_JSON, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    if alert and event_type:
        print(f'ALERT MKT|market_sentiment_delta.py|{event_type} score {score:+.1f}, delta {delta:+.1f} (entry {entry_delta:.1f})')
    else:
        print(f'OK MKT|market_sentiment_delta.py score {score:+.1f}, delta {delta:+.1f} regime={new_regime} streak(up={up_streak},down={down_streak})')


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f'ALERT MKT|market_sentiment_delta.py|ERROR {type(e).__name__}: {e}')
