#!/usr/bin/env python3
import argparse
import json
import math
from pathlib import Path

CANVAS_W = 1600
CANVAS_H = 1000
CENTER_X = 620
CENTER_Y = 500
FONT = "Pretendard, Apple SD Gothic Neo, Noto Sans CJK KR, Noto Sans KR, Malgun Gothic, Arial, sans-serif"

CORE_COLORS = {
    "의미": "#4F46E5",
    "편향": "#DC2626",
    "적응": "#059669",
    "인센티브": "#D97706",
    "신뢰": "#0284C7",
    "권력": "#7C3AED",
    "경로의존성": "#0F766E",
    "피드백": "#65A30D",
    "프레이밍": "#DB2777",
    "불확실성": "#6B7280",
}

RADIAL_ORDER = [
    "의미", "프레이밍", "편향", "불확실성", "신뢰",
    "권력", "인센티브", "피드백", "적응", "경로의존성",
]

NETWORK_POSITIONS = {
    "의미": (360, 220),
    "프레이밍": (590, 190),
    "편향": (810, 250),
    "적응": (300, 590),
    "피드백": (470, 770),
    "경로의존성": (640, 620),
    "인센티브": (1060, 650),
    "권력": (1230, 470),
    "신뢰": (1000, 300),
    "불확실성": (820, 840),
}


def hex_to_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


def rgb_to_hex(rgb):
    return '#%02x%02x%02x' % rgb


def lighten(hex_color, factor=0.35):
    r, g, b = hex_to_rgb(hex_color)
    nr = int(r + (255 - r) * factor)
    ng = int(g + (255 - g) * factor)
    nb = int(b + (255 - b) * factor)
    return rgb_to_hex((nr, ng, nb))


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--input', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--layout', choices=['radial', 'network'], default='radial')
    return p.parse_args()


def esc(text):
    return (
        str(text)
        .replace('&', '&amp;')
        .replace('<', '&lt;')
        .replace('>', '&gt;')
        .replace('"', '&quot;')
    )


def text(x, y, content, size=18, fill='#111827', weight=400, anchor='middle'):
    return f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" fill="{fill}" font-weight="{weight}" text-anchor="{anchor}">{esc(content)}</text>'


def line(x1, y1, x2, y2, stroke='#CBD5E1', width=2, opacity=1.0, dash=''):
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ''
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" stroke-width="{width}" opacity="{opacity}"{dash_attr}/>'


def circle(cx, cy, r, fill, stroke='white', stroke_width=2, opacity=1.0):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{stroke_width}" opacity="{opacity}"/>'


def rounded_rect(x, y, w, h, fill, stroke='none', stroke_width=0, rx=16, opacity=1.0):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{stroke_width}" opacity="{opacity}"/>'


def card(x, y, w, h, title_text, body_lines):
    parts = [
        rounded_rect(x, y, w, h, '#FFFFFF', '#E5E7EB', 1, 18),
        text(x + 20, y + 34, title_text, 22, '#111827', 700, 'start'),
    ]
    yy = y + 66
    for ln in body_lines:
        parts.append(text(x + 20, yy, ln, 17, '#475569', 400, 'start'))
        yy += 28
    return '\n'.join(parts)


def load_data(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def get_core_map(data):
    nodes = {item['name']: item['children'] for item in data['core_nodes']}
    links = data['links']
    return nodes, links


def radial_positions(core_names):
    n = len(core_names)
    positions = {}
    radius = 300
    start_deg = -90
    for i, name in enumerate(core_names):
        ang = math.radians(start_deg + (360 / n) * i)
        x = CENTER_X + radius * math.cos(ang)
        y = CENTER_Y + radius * math.sin(ang)
        positions[name] = (x, y, ang)
    return positions


def child_positions_radial(cx, cy, ang, count=3):
    offsets = [-0.34, 0, 0.34]
    out = []
    r = 125
    for off in offsets[:count]:
        a = ang + off
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def child_positions_network(cx, cy, idx, count=3):
    presets = [
        [(-90, -70), (0, -110), (90, -70)],
        [(-110, 0), (0, 90), (110, 0)],
        [(-90, 70), (0, 110), (90, 70)],
        [(-110, -20), (0, -95), (110, -20)],
    ]
    pts = presets[idx % len(presets)][:count]
    return [(cx + dx, cy + dy) for dx, dy in pts]


def render_radial(data):
    nodes, links = get_core_map(data)
    positions = radial_positions(RADIAL_ORDER)
    parts = []
    parts.append(f'<svg width="{CANVAS_W}" height="{CANVAS_H}" viewBox="0 0 {CANVAS_W} {CANVAS_H}" xmlns="http://www.w3.org/2000/svg">')
    parts.append('<rect width="100%" height="100%" fill="#F8FAFC"/>')
    parts.append(rounded_rect(30, 30, 1540, 940, '#FDFDFD', '#E5E7EB', 1, 28))
    parts.append(text(80, 90, data['title'], 34, '#0F172A', 800, 'start'))
    parts.append(text(80, 128, '단어 하나를 고르면 개념·중요성·삶의 예시·연결 단어·다음 질문으로 확장되는 탐색형 지도', 18, '#475569', 400, 'start'))

    for a, b in links:
        x1, y1, _ = positions[a]
        x2, y2, _ = positions[b]
        parts.append(line(x1, y1, x2, y2, '#CBD5E1', 3, 0.9))

    parts.append(circle(CENTER_X, CENTER_Y, 92, '#EEF2FF', '#C7D2FE', 2))
    parts.append(text(CENTER_X, CENTER_Y - 8, '인간 삶', 26, '#312E81', 800))
    parts.append(text(CENTER_X, CENTER_Y + 24, '핵심 원리 지도', 22, '#4338CA', 700))

    for name in RADIAL_ORDER:
        x, y, ang = positions[name]
        color = CORE_COLORS.get(name, '#334155')
        child_pts = child_positions_radial(x, y, ang, len(nodes[name]))
        for (cx, cy), child in zip(child_pts, nodes[name]):
            parts.append(line(x, y, cx, cy, lighten(color, 0.45), 2, 0.9))
            parts.append(circle(cx, cy, 34, lighten(color, 0.55), '#FFFFFF', 2))
            parts.append(text(cx, cy + 6, child, 16, '#0F172A', 600))
        parts.append(circle(x, y, 52, color, '#FFFFFF', 4))
        parts.append(text(x, y + 7, name, 22, '#FFFFFF', 800))

    parts.append(card(1110, 120, 390, 250, '탐색 방식', [
        '1. 지도에서 눈에 걸리는 단어를 고른다',
        '2. 그 단어를 AI에게 그대로 던진다',
        '3. AI가 뜻·중요성·예시·연결 개념을 확장한다',
        '4. 연결선 따라 다음 사고 점프로 이동한다',
    ]))
    parts.append(card(1110, 400, 390, 300, '예시 질문', [
        '“경로의존성?”',
        '“도덕적 해이가 왜 생겨?”',
        '“프레이밍이 의미를 어떻게 바꿔?”',
        '“불확실성과 신뢰는 왜 연결돼?”',
        '“이걸 인간관계 예시로 설명해줘”',
    ]))
    parts.append('</svg>')
    return '\n'.join(parts) + '\n'


def render_network(data):
    nodes, links = get_core_map(data)
    parts = []
    parts.append(f'<svg width="{CANVAS_W}" height="{CANVAS_H}" viewBox="0 0 {CANVAS_W} {CANVAS_H}" xmlns="http://www.w3.org/2000/svg">')
    parts.append('<rect width="100%" height="100%" fill="#F8FAFC"/>')
    parts.append(rounded_rect(30, 30, 1540, 940, '#FFFFFF', '#E5E7EB', 1, 28))
    parts.append(text(80, 90, data['title'] + ' — 군집 네트워크형', 34, '#0F172A', 800, 'start'))
    parts.append(text(80, 128, '개념 덩어리 사이를 사고 점프하듯 탐색하는 버전', 18, '#475569', 400, 'start'))

    for a, b in links:
        x1, y1 = NETWORK_POSITIONS[a]
        x2, y2 = NETWORK_POSITIONS[b]
        parts.append(line(x1, y1, x2, y2, '#94A3B8', 4, 0.95))

    for idx, (name, children) in enumerate(nodes.items()):
        x, y = NETWORK_POSITIONS[name]
        color = CORE_COLORS.get(name, '#334155')
        child_pts = child_positions_network(x, y, idx, len(children))
        for (cx, cy), child in zip(child_pts, children):
            parts.append(line(x, y, cx, cy, lighten(color, 0.45), 2, 0.9, '6 6'))
            parts.append(rounded_rect(cx - 46, cy - 22, 92, 44, lighten(color, 0.58), '#FFFFFF', 2, 18))
            parts.append(text(cx, cy + 6, child, 15, '#0F172A', 600))
        parts.append(rounded_rect(x - 62, y - 34, 124, 68, color, '#FFFFFF', 3, 24))
        parts.append(text(x, y + 8, name, 22, '#FFFFFF', 800))

    parts.append(card(80, 760, 560, 150, '탐색 포인트', [
        '인지/해석: 의미 · 프레이밍 · 편향',
        '적응/시간: 적응 · 피드백 · 경로의존성',
        '사회/구조: 신뢰 · 권력 · 인센티브',
        '판단/리스크: 불확실성',
    ]))
    parts.append(card(980, 100, 500, 180, '이 버전이 좋은 이유', [
        '한 단어에서 다른 단어로 넘어가는 연결성이 잘 보인다',
        '사용자가 “왜 이 둘이 이어지지?”라는 질문을 만들기 쉽다',
        '탐색형 인터페이스와 잘 맞는다',
    ]))
    parts.append('</svg>')
    return '\n'.join(parts) + '\n'


def main():
    args = parse_args()
    data = load_data(args.input)
    svg = render_radial(data) if args.layout == 'radial' else render_network(data)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(svg, encoding='utf-8')
    print(f'[OK] wrote {out}')


if __name__ == '__main__':
    main()
