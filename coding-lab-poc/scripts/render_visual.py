#!/usr/bin/env python3
import argparse
import html
import sys
from pathlib import Path
import yaml


CANVAS_W = 1200
CANVAS_H = 630
PANEL_X = 70
PANEL_Y = 70
PANEL_W = 1060
PANEL_H = 490
TEXT_X = 120
RIGHT_SAFE_X = 860
BADGE_MAX_X = 840
FONT_STACK = "Pretendard, Apple SD Gothic Neo, Noto Sans CJK KR, Noto Sans KR, Malgun Gothic, Arial, sans-serif"


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--basename', required=True)
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--verbose', action='store_true')
    return parser.parse_args()


def compact(text: str) -> str:
    return ' '.join(str(text).split())


def truncate(text: str, limit: int = 72) -> str:
    text = compact(text)
    return text if len(text) <= limit else text[: limit - 1] + '…'


def visual_len(text: str) -> int:
    text = str(text)
    width = 0.0
    for ch in text:
        code = ord(ch)
        if ch.isspace():
            width += 0.45
        elif code >= 0x1F300:
            width += 2.0
        elif code >= 0x2E80:
            width += 1.8
        elif ch.isupper():
            width += 1.05
        else:
            width += 0.95
    return int(round(width))


def wrap_text(text: str, limit: int):
    words = compact(text).split()
    if not words:
        return []
    lines = []
    current = words[0]
    for word in words[1:]:
        candidate = f'{current} {word}'
        if visual_len(candidate) <= limit:
            current = candidate
        else:
            lines.append(current)
            current = word
    lines.append(current)
    return lines


def svg_text(x, y, text, size=24, fill='#000', weight='400'):
    return f'<text x="{x}" y="{y}" fill="{fill}" font-size="{size}" font-family="{FONT_STACK}" font-weight="{weight}">{html.escape(text)}</text>'


def svg_text_lines(x, y, lines, size=24, fill='#000', weight='400', line_gap=1.35):
    if not lines:
        return []
    blocks = []
    step = int(size * line_gap)
    for idx, line in enumerate(lines):
        blocks.append(svg_text(x, y + idx * step, line, size, fill, weight))
    return blocks


def badge(x, y, label, fill, text_fill='#fff'):
    label = truncate(compact(label), 18)
    w = max(92, visual_len(label) * 12 + 28)
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="36" rx="18" fill="{fill}" opacity="0.95"/>'
        f'<text x="{x + 16}" y="{y + 24}" fill="{text_fill}" font-size="18" font-family="{FONT_STACK}" font-weight="600">{html.escape(label)}</text>',
        w,
    )


def read_yaml(path: Path):
    if not path.exists():
        raise FileNotFoundError(f'input file not found: {path}')
    raw = path.read_text(encoding='utf-8').strip()
    if not raw:
        raise ValueError(f'input file is empty: {path}')
    return yaml.safe_load(raw) or {}


def safe_write(path: Path, content: str, force: bool):
    if path.exists() and not force:
        raise FileExistsError(f'output already exists: {path}')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8')


def main():
    args = parse_args()
    input_path = Path(args.input)
    output_dir = Path(args.output_dir)
    out_svg = output_dir / f'{args.basename}.visual.svg'

    try:
        data = read_yaml(input_path)
        project_name = compact(data.get('project_name', 'Untitled Project'))
        subtitle = compact(data.get('subtitle', ''))
        purpose = compact(data.get('purpose', ''))
        audience = compact(data.get('audience', 'general'))
        keywords = (data.get('keywords', []) or [])[:6]
        style = data.get('style', {}) or {}
        visual = compact(style.get('visual', 'minimal-tech'))
        theme = compact(style.get('theme', 'dark-on-light'))

        if theme == 'dark-on-light':
            bg = '#f5f7fb'
            panel = '#111827'
            title = '#ffffff'
            subtitle_color = '#cbd5e1'
            body = '#94a3b8'
            meta = '#93c5fd'
            badge_fill = '#2563eb'
        else:
            bg = '#0b1020'
            panel = '#f8fafc'
            title = '#111827'
            subtitle_color = '#334155'
            body = '#475569'
            meta = '#0f766e'
            badge_fill = '#7c3aed'

        title_lines = wrap_text(project_name, 28)[:2]
        subtitle_lines = wrap_text(subtitle, 38)[:2]
        purpose_lines = wrap_text(purpose, 54)[:3]

        title_y = 170
        title_step = 66
        subtitle_y = title_y + max(len(title_lines), 1) * title_step + 6
        subtitle_step = 38
        purpose_y = subtitle_y + (len(subtitle_lines) * subtitle_step if subtitle_lines else 0) + 34
        purpose_step = 32
        badge_y = purpose_y + (len(purpose_lines) * purpose_step if purpose_lines else 0) + 34

        parts = []
        parts.append(f'<svg width="{CANVAS_W}" height="{CANVAS_H}" viewBox="0 0 {CANVAS_W} {CANVAS_H}" xmlns="http://www.w3.org/2000/svg">')
        parts.append(f'<rect width="{CANVAS_W}" height="{CANVAS_H}" fill="{bg}"/>')
        parts.append(f'<rect x="{PANEL_X}" y="{PANEL_Y}" width="{PANEL_W}" height="{PANEL_H}" rx="28" fill="{panel}"/>')
        parts.extend(svg_text_lines(TEXT_X, title_y, title_lines, 56, title, '700', 1.18))
        if subtitle_lines:
            parts.extend(svg_text_lines(TEXT_X, subtitle_y, subtitle_lines, 28, subtitle_color, '500', 1.3))
        if purpose_lines:
            parts.extend(svg_text_lines(TEXT_X, purpose_y, purpose_lines, 24, body, '400', 1.35))

        bx = TEXT_X
        by = badge_y
        row_h = 48
        for raw_label in keywords:
            label = compact(raw_label)
            badge_svg, width = badge(bx, by, label, badge_fill)
            if bx + width > BADGE_MAX_X:
                bx = TEXT_X
                by += row_h
                badge_svg, width = badge(bx, by, label, badge_fill)
            parts.append(badge_svg)
            bx += width + 14

        meta_y = min(by + 80, 500)
        parts.append(svg_text(TEXT_X, meta_y, f'audience: {truncate(audience, 40)}', 20, meta, '600'))
        parts.append(svg_text(TEXT_X, meta_y + 32, f'style: {truncate(visual, 32)}', 20, meta, '600'))

        parts.append('<circle cx="980" cy="180" r="56" fill="#22c55e"/>')
        parts.append('<circle cx="1040" cy="250" r="28" fill="#3b82f6"/>')
        parts.append('<circle cx="920" cy="270" r="20" fill="#f59e0b"/>')
        parts.append('</svg>')

        svg = '\n'.join(parts) + '\n'
        if not svg.strip():
            raise ValueError('generated visual output is empty')

        safe_write(out_svg, svg, args.force)
        if out_svg.stat().st_size == 0:
            raise ValueError('visual file size is zero')
        print(f'[OK] wrote visual: {out_svg}')
        return 0
    except Exception as e:
        print(f'[ERROR] render_visual failed: {e}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
