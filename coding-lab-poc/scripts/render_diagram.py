#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path
from xml.sax.saxutils import escape
import yaml


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--basename', required=True)
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--verbose', action='store_true')
    return parser.parse_args()


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
    out = output_dir / f'{args.basename}.diagram.drawio'

    try:
        data = read_yaml(input_path)
        title = str(((data.get('outputs') or {}).get('diagram') or {}).get('title', 'Workflow'))
        workflow = data.get('workflow', []) or []
        if not workflow:
            workflow = ['Start', 'Process', 'Finish']

        start_x = 40
        y = 120
        width = 140
        height = 60
        gap = 180

        cells = [
            '        <mxCell id="0"/>',
            '        <mxCell id="1" parent="0"/>'
        ]

        node_ids = []
        for i, step in enumerate(workflow, start=1):
            node_id = f'n{i}'
            node_ids.append(node_id)
            x = start_x + (i - 1) * gap
            cells.append(
                f'        <mxCell id="{node_id}" value="{escape(str(step))}" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">\n'
                f'          <mxGeometry x="{x}" y="{y}" width="{width}" height="{height}" as="geometry"/>\n'
                f'        </mxCell>'
            )

        for i in range(len(node_ids) - 1):
            cells.append(
                f'        <mxCell id="e{i+1}" edge="1" parent="1" source="{node_ids[i]}" target="{node_ids[i+1]}">\n'
                f'          <mxGeometry relative="1" as="geometry"/>\n'
                f'        </mxCell>'
            )

        xml = (
            '<mxfile host="app.diagrams.net">\n'
            f'  <diagram name="{escape(title)}">\n'
            '    <mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1">\n'
            '      <root>\n'
            + '\n'.join(cells) + '\n'
            '      </root>\n'
            '    </mxGraphModel>\n'
            '  </diagram>\n'
            '</mxfile>\n'
        )

        if not xml.strip():
            raise ValueError('generated diagram output is empty')

        safe_write(out, xml, args.force)
        print(f'[OK] wrote diagram: {out}')
        return 0
    except Exception as e:
        print(f'[ERROR] render_diagram failed: {e}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
