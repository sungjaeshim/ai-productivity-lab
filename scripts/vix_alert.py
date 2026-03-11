#!/usr/bin/env python3
import yfinance as yf
import json
import os
from datetime import datetime, timezone

STATE_FILE = '/root/.openclaw/workspace/.state/vix_alert_state.json'


def _load_state():
    try:
        with open(STATE_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {}


def _save_state(payload):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def _allow_alert(prev_state, event_type, now_ts, cooldown_seconds):
    alerts = prev_state.get('alerts', {}) if isinstance(prev_state, dict) else {}
    last_ts = alerts.get(event_type)
    if not isinstance(last_ts, (int, float)):
        return True
    return (now_ts - float(last_ts)) >= cooldown_seconds


def main():
    threshold = 20.0
    spike_pct_threshold = 5.0   # 1시간 변동률 절대값
    spike_abs_threshold = 1.5   # 1시간 절대 변동값
    cooldown_seconds = 90 * 60  # 90분

    df = yf.Ticker('^VIX').history(period='5d', interval='1h')
    if df is None or len(df) < 2:
        print('ALERT MKT|vix_alert.py|NO_DATA VIX 데이터 부족')
        return

    prev_state = _load_state()
    close = df['Close']
    vix = float(close.iloc[-1])
    prev = float(close.iloc[-2])
    chg = vix - prev
    chg_pct = (chg / prev * 100.0) if prev else 0.0

    prev_value = prev_state.get('value') if isinstance(prev_state, dict) else None
    cross_up = isinstance(prev_value, (int, float)) and (prev_value < threshold <= vix)
    cross_down = isinstance(prev_value, (int, float)) and (prev_value >= threshold > vix)
    spike = abs(chg_pct) >= spike_pct_threshold or abs(chg) >= spike_abs_threshold

    now_ts = datetime.now(timezone.utc).timestamp()
    event_type = None
    if cross_up:
        event_type = 'VIX_CROSS_UP'
    elif cross_down:
        event_type = 'VIX_CROSS_DOWN'
    elif spike:
        event_type = 'VIX_SPIKE'

    alert = False
    if event_type and _allow_alert(prev_state, event_type, now_ts, cooldown_seconds):
        alert = True

    regime = 'HIGH' if vix >= threshold else 'NORMAL'

    alerts = prev_state.get('alerts', {}) if isinstance(prev_state, dict) else {}
    if alert and event_type:
        alerts[event_type] = int(now_ts)

    state = {
        'symbol': '^VIX',
        'value': round(vix, 4),
        'chg': round(chg, 4),
        'chg_pct': round(chg_pct, 4),
        'threshold': threshold,
        'spike_pct_threshold': spike_pct_threshold,
        'spike_abs_threshold': spike_abs_threshold,
        'cooldown_seconds': cooldown_seconds,
        'regime': regime,
        'event_type': event_type,
        'alert': alert,
        'alerts': alerts,
        'updated_at': datetime.now(timezone.utc).isoformat()
    }
    _save_state(state)

    if alert and event_type == 'VIX_CROSS_UP':
        print(f'ALERT MKT|vix_alert.py|VIX_CROSS_UP VIX {vix:.2f} (Δ{chg:+.2f}, {chg_pct:+.2f}%) crossed >= {threshold:.1f}')
    elif alert and event_type == 'VIX_CROSS_DOWN':
        print(f'ALERT MKT|vix_alert.py|VIX_CROSS_DOWN VIX {vix:.2f} (Δ{chg:+.2f}, {chg_pct:+.2f}%) crossed < {threshold:.1f}')
    elif alert and event_type == 'VIX_SPIKE':
        print(f'ALERT MKT|vix_alert.py|VIX_SPIKE VIX {vix:.2f} (Δ{chg:+.2f}, {chg_pct:+.2f}%)')
    else:
        print(f'OK MKT|vix_alert.py VIX {vix:.2f} (Δ{chg:+.2f}, {chg_pct:+.2f}%) regime={regime}')


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f'ALERT MKT|vix_alert.py|ERROR {type(e).__name__}: {e}')
