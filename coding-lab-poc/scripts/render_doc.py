#!/usr/bin/env python3
import argparse
import html
import sys
from pathlib import Path
import yaml


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--tmp-dir', default='tmp')
    parser.add_argument('--basename', required=True)
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--verbose', action='store_true')
    return parser.parse_args()


def md_list(items):
    return '\n'.join(f'- {item}' for item in items) if items else '- (none)'


def html_list(items):
    if not items:
        return '<li>(none)</li>'
    return ''.join(f'<li>{html.escape(str(item))}</li>' for item in items)


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
    tmp_dir = Path(args.tmp_dir)
    out_md = output_dir / f'{args.basename}.report.md'
    out_html = tmp_dir / f'{args.basename}.report.html'

    try:
        data = read_yaml(input_path)

        project_name = data.get('project_name', 'Untitled Project')
        subtitle = data.get('subtitle', '')
        audience = data.get('audience', 'general')
        purpose = data.get('purpose', '')
        core_activities = data.get('core_activities', []) or []
        workflow = data.get('workflow', []) or []
        example_projects = data.get('example_projects', []) or []
        keywords = data.get('keywords', []) or []
        docs_title = (((data.get('outputs') or {}).get('docs') or {}).get('title')) or 'Project Document'

        md = f'''# {docs_title}\n\n## 프로젝트\n{project_name}\n\n## 서브타이틀\n{subtitle}\n\n## 대상 독자\n{audience}\n\n## 개요\n{purpose}\n\n## 핵심 키워드\n{md_list(keywords)}\n\n## 핵심 활동\n{md_list(core_activities)}\n\n## 운영 흐름\n{md_list(workflow)}\n\n## 대표 실험\n{md_list(example_projects)}\n\n## 다음 단계\n- 문서/다이어그램/시각물 패키지로 확장\n- 출력 포맷 품질 개선\n- 재사용 가능한 입력 템플릿 정교화\n'''

        html_doc = f'''<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <title>{html.escape(str(docs_title))}</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 40px; line-height: 1.7; color: #111827; }}
    h1 {{ font-size: 32px; margin-bottom: 6px; }}
    h2 {{ color: #1f2937; margin-top: 28px; }}
    .subtitle {{ color: #475569; font-size: 18px; margin-bottom: 20px; }}
    .meta {{ color: #0f766e; font-weight: 600; margin-bottom: 20px; }}
    ul {{ margin-left: 20px; }}
  </style>
</head>
<body>
  <h1>{html.escape(str(docs_title))}</h1>
  <div class="subtitle">{html.escape(str(project_name))} — {html.escape(str(subtitle))}</div>
  <div class="meta">audience: {html.escape(str(audience))}</div>

  <h2>개요</h2>
  <p>{html.escape(str(purpose))}</p>

  <h2>핵심 키워드</h2>
  <ul>{html_list(keywords)}</ul>

  <h2>핵심 활동</h2>
  <ul>{html_list(core_activities)}</ul>

  <h2>운영 흐름</h2>
  <ul>{html_list(workflow)}</ul>

  <h2>대표 실험</h2>
  <ul>{html_list(example_projects)}</ul>

  <h2>다음 단계</h2>
  <ul>
    <li>문서/다이어그램/시각물 패키지로 확장</li>
    <li>출력 포맷 품질 개선</li>
    <li>재사용 가능한 입력 템플릿 정교화</li>
  </ul>
</body>
</html>
'''

        if not md.strip() or not html_doc.strip():
            raise ValueError('generated document output is empty')

        safe_write(out_md, md, args.force)
        safe_write(out_html, html_doc, args.force)
        print(f'[OK] wrote doc: {out_md}')
        print(f'[OK] wrote html: {out_html}')
        return 0
    except Exception as e:
        print(f'[ERROR] render_doc failed: {e}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
