#!/usr/bin/env python3
# Archived on 2026-03-06: inactive market alert helper kept for recovery.
import yfinance as yf
import json
import os
from datetime import datetime, timezone

STATE_FILE = '/root/.openclaw/workspace/.state/usdkrw_alert_state.json'

def _save_state(payload):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

def main():
    # 1시간 변동률 기준 급변 감지
    threshold_pct = 0.40
    df = yf.Ticker('KRW=X').history(period='5d', interval='1h')
    if df is None or len(df) < 2:
        print('ALERT MKT|usdkrw_alert.py|NO_DATA USDKRW 데이터 부족')
        return

    close = df['Close']
    cur = float(close.iloc[-1])
    prev = float(close.iloc[-2])
    chg = cur - prev
    chg_pct = (chg / prev * 100.0) if prev else 0.0

    alert = abs(chg_pct) >= threshold_pct
    _save_state({
        'symbol': 'KRW=X',
        'value': round(cur, 4),
        'chg': round(chg, 4),
        'chg_pct': round(chg_pct, 4),
        'threshold_pct': threshold_pct,
        'alert': alert,
        'updated_at': datetime.now(timezone.utc).isoformat()
    })

    if alert:
        direction = 'UP' if chg_pct > 0 else 'DOWN'
        print(f'ALERT MKT|usdkrw_alert.py|USDKRW_{direction} USD/KRW {cur:.2f} ({chg_pct:+.2f}%) >= |{threshold_pct:.2f}%|')
    else:
        print(f'OK MKT|usdkrw_alert.py USD/KRW {cur:.2f} ({chg_pct:+.2f}%) < |{threshold_pct:.2f}%|')

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f'ALERT MKT|usdkrw_alert.py|ERROR {type(e).__name__}: {e}')
