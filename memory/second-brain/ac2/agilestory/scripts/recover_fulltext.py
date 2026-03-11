#!/usr/bin/env python3
"""
AC2 Agilestory Full-text Recovery Script
Recovers article content from raw HTML files using multiple parsers.

Parser priority:
1. trafilatura
2. readability-lxml
3. BeautifulSoup selector fallback
4. Text density fallback
"""

import os
import sys
import json
import re
import time
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, Any, Tuple

# Parser imports
import trafilatura
from readability import Document
from bs4 import BeautifulSoup

# Base directory
BASE_DIR = Path(__file__).parent.parent
RAW_DIR = BASE_DIR / "raw"
CLEANED_DIR = BASE_DIR / "cleaned"
META_DIR = BASE_DIR / "meta"
MANIFESTS_DIR = BASE_DIR / "manifests"
REPORTS_DIR = BASE_DIR / "reports"

# Ensure directories exist
for d in [CLEANED_DIR, META_DIR, MANIFESTS_DIR, REPORTS_DIR]:
    d.mkdir(parents=True, exist_ok=True)

# Checkpoint files
PROGRESS_FILE = MANIFESTS_DIR / "recovery_progress.json"
PROCESSED_FILE = MANIFESTS_DIR / "recovery_processed.jsonl"
SNAPSHOT_FILE = REPORTS_DIR / "recovery_snapshot.json"
REPORT_FILE = REPORTS_DIR / "recovery_report.json"
DONE_FILE = REPORTS_DIR / "recovery_done.json"

# BeautifulSoup selectors to try (in order)
BS4_SELECTORS = [
    ("article", {}),
    (".post", {}),
    (".entry", {}),
    (".content", {}),
    ("#content", {}),
    (".tt_article_useless_p_margin", {}),
    (".article_view", {}),
    (".entry-content", {}),
    ("main", {}),
    (".prose", {}),
    ("[class*='post-content']", {}),
    ("[class*='article-content']", {}),
    (".post-content", {}),
]


def load_progress() -> Dict[str, Any]:
    """Load checkpoint progress."""
    if PROGRESS_FILE.exists():
        with open(PROGRESS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {
        "started_at": None,
        "last_processed": None,
        "processed_count": 0,
        "success_count": 0,
        "failed_count": 0,
        "method_stats": {},
        "failed_posts": []
    }


def save_progress(progress: Dict[str, Any]):
    """Save checkpoint progress."""
    with open(PROGRESS_FILE, "w", encoding="utf-8") as f:
        json.dump(progress, f, ensure_ascii=False, indent=2)


def append_processed(post_id: str, status: str, method: str, text_length: int):
    """Append to processed log."""
    with open(PROCESSED_FILE, "a", encoding="utf-8") as f:
        record = {
            "post_id": post_id,
            "status": status,
            "method": method,
            "text_length": text_length,
            "processed_at": datetime.now().isoformat()
        }
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


def update_snapshot(progress: Dict[str, Any], total: int, start_time: float):
    """Update progress snapshot."""
    elapsed = time.time() - start_time
    processed = progress["processed_count"]
    remaining = total - processed
    
    if processed > 0:
        avg_time = elapsed / processed
        eta_seconds = remaining * avg_time
    else:
        eta_seconds = 0
    
    snapshot = {
        "total": total,
        "processed": processed,
        "success": progress["success_count"],
        "failed": progress["failed_count"],
        "remaining": remaining,
        "elapsed_seconds": round(elapsed, 2),
        "eta_seconds": round(eta_seconds, 2),
        "eta_minutes": round(eta_seconds / 60, 2),
        "progress_percent": round((processed / total) * 100, 2),
        "method_stats": progress["method_stats"],
        "last_updated": datetime.now().isoformat()
    }
    
    with open(SNAPSHOT_FILE, "w", encoding="utf-8") as f:
        json.dump(snapshot, f, ensure_ascii=False, indent=2)


def clean_text(text: str) -> str:
    """Clean extracted text."""
    if not text:
        return ""
    
    # Normalize whitespace
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r' {2,}', ' ', text)
    
    # Remove leading/trailing whitespace per line
    lines = [line.strip() for line in text.split('\n')]
    text = '\n'.join(lines)
    
    # Remove empty lines at start/end
    text = text.strip()
    
    return text


def remove_duplicates(text: str) -> str:
    """Remove duplicate paragraphs."""
    if not text:
        return ""
    
    paragraphs = text.split('\n\n')
    seen = set()
    unique = []
    
    for p in paragraphs:
        p_normalized = p.strip().lower()
        if p_normalized and p_normalized not in seen:
            seen.add(p_normalized)
            unique.append(p)
    
    return '\n\n'.join(unique)


def extract_with_trafilatura(html: str) -> Tuple[Optional[str], str]:
    """Extract using trafilatura."""
    try:
        text = trafilatura.extract(html, include_comments=False, include_formatting=False)
        if text and len(text.strip()) > 50:
            return clean_text(text), "trafilatura"
    except Exception as e:
        pass
    return None, ""


def extract_with_readability(html: str) -> Tuple[Optional[str], str]:
    """Extract using readability-lxml."""
    try:
        doc = Document(html)
        text = doc.summary()
        # Parse the summary HTML to get text
        soup = BeautifulSoup(text, 'lxml')
        text = soup.get_text(separator='\n')
        text = clean_text(text)
        if text and len(text.strip()) > 50:
            return text, "readability-lxml"
    except Exception as e:
        pass
    return None, ""


def extract_with_bs4_selectors(html: str) -> Tuple[Optional[str], str]:
    """Extract using BeautifulSoup selectors."""
    try:
        soup = BeautifulSoup(html, 'lxml')
        
        # Remove unwanted elements
        for tag in soup(['script', 'style', 'nav', 'footer', 'header', 'aside']):
            tag.decompose()
        
        for selector, attrs in BS4_SELECTORS:
            try:
                elements = soup.select(selector)
                if elements:
                    # Get the largest element by text length
                    best = max(elements, key=lambda e: len(e.get_text()))
                    text = best.get_text(separator='\n')
                    text = clean_text(text)
                    if text and len(text.strip()) > 50:
                        return text, f"bs4:{selector}"
            except Exception:
                continue
    except Exception as e:
        pass
    return None, ""


def calculate_text_density(element) -> float:
    """Calculate text density of an element."""
    text = element.get_text()
    text_len = len(text.strip())
    
    # Get all tag names
    tags = [tag.name for tag in element.find_all(True)]
    tag_count = len(tags) if tags else 1
    
    # Text density = text length / tag count
    return text_len / tag_count if tag_count > 0 else 0


def extract_with_density_fallback(html: str) -> Tuple[Optional[str], str]:
    """Extract using text density fallback."""
    try:
        soup = BeautifulSoup(html, 'lxml')
        
        # Remove unwanted elements
        for tag in soup(['script', 'style', 'nav', 'footer', 'header', 'aside', 'noscript']):
            tag.decompose()
        
        # Find all container elements
        candidates = soup.find_all(['div', 'section', 'article', 'main'])
        
        if not candidates:
            # Fallback to body
            body = soup.find('body')
            if body:
                text = body.get_text(separator='\n')
                text = clean_text(text)
                if text and len(text.strip()) > 50:
                    return text, "density:body"
            return None, ""
        
        # Calculate density for each candidate
        scored = []
        for elem in candidates:
            density = calculate_text_density(elem)
            text_len = len(elem.get_text().strip())
            # Score combines density and absolute length
            score = density + (text_len / 1000)
            scored.append((elem, score, text_len))
        
        # Sort by score
        scored.sort(key=lambda x: x[1], reverse=True)
        
        # Get the best candidate
        best_elem, best_score, best_len = scored[0]
        
        if best_len > 50:
            text = best_elem.get_text(separator='\n')
            text = clean_text(text)
            if text and len(text.strip()) > 50:
                return text, "density:fallback"
    except Exception as e:
        pass
    return None, ""


def extract_content(html: str) -> Tuple[Optional[str], str]:
    """Try all extraction methods in order."""
    # 1. Try trafilatura
    text, method = extract_with_trafilatura(html)
    if text:
        return text, method
    
    # 2. Try readability-lxml
    text, method = extract_with_readability(html)
    if text:
        return text, method
    
    # 3. Try BeautifulSoup selectors
    text, method = extract_with_bs4_selectors(html)
    if text:
        return text, method
    
    # 4. Try density fallback
    text, method = extract_with_density_fallback(html)
    if text:
        return text, method
    
    return None, ""


def load_meta(post_id: str) -> Dict[str, Any]:
    """Load metadata for a post."""
    meta_file = META_DIR / f"{post_id}.json"
    if meta_file.exists():
        with open(meta_file, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_meta(post_id: str, meta: Dict[str, Any]):
    """Save metadata for a post."""
    meta_file = META_DIR / f"{post_id}.json"
    with open(meta_file, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)


def save_cleaned_markdown(post_id: str, meta: Dict[str, Any], content: str):
    """Save cleaned content as markdown."""
    md_file = CLEANED_DIR / f"{post_id}.md"
    
    # Build markdown content
    lines = []
    lines.append(f"# {meta.get('title', 'Untitled')}")
    lines.append("")
    lines.append(f"**원문URL:** {meta.get('url', '')}")
    lines.append(f"**날짜:** {meta.get('date', '')}")
    
    tags = meta.get('tags', [])
    if tags:
        lines.append(f"**태그:** {', '.join(tags)}")
    
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append(content)
    
    with open(md_file, "w", encoding="utf-8") as f:
        f.write('\n'.join(lines))


def get_processed_ids() -> set:
    """Get set of already processed post IDs."""
    processed = set()
    if PROCESSED_FILE.exists():
        with open(PROCESSED_FILE, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    record = json.loads(line.strip())
                    processed.add(record["post_id"])
                except:
                    pass
    return processed


def get_all_raw_files() -> list:
    """Get all raw HTML files."""
    files = list(RAW_DIR.glob("*.html"))
    return sorted(files, key=lambda x: x.stem)


def main():
    print("=" * 60)
    print("AC2 Agilestory Full-text Recovery")
    print("=" * 60)
    
    # Get all files
    all_files = get_all_raw_files()
    total = len(all_files)
    
    print(f"\nTotal raw HTML files: {total}")
    
    # Load progress
    progress = load_progress()
    processed_ids = get_processed_ids()
    
    print(f"Already processed: {len(processed_ids)}")
    
    # Start timer
    start_time = time.time()
    
    if progress["started_at"] is None:
        progress["started_at"] = datetime.now().isoformat()
    
    # Process files
    files_to_process = [f for f in all_files if f.stem not in processed_ids]
    print(f"Files to process: {len(files_to_process)}\n")
    
    # Initialize method stats if not present
    if not progress.get("method_stats"):
        progress["method_stats"] = {}
    
    for method in ["trafilatura", "readability-lxml", "bs4_selector", "density_fallback", "failed"]:
        if method not in progress["method_stats"]:
            progress["method_stats"][method] = 0
    
    for i, raw_file in enumerate(files_to_process):
        post_id = raw_file.stem
        
        # Read HTML
        try:
            with open(raw_file, "r", encoding="utf-8") as f:
                html = f.read()
        except Exception as e:
            print(f"[ERROR] Cannot read {post_id}: {e}")
            continue
        
        # Load existing meta
        meta = load_meta(post_id)
        
        # Extract content
        content, method = extract_content(html)
        
        if content:
            # Clean up
            content = remove_duplicates(content)
            text_length = len(content)
            
            # Save cleaned markdown
            save_cleaned_markdown(post_id, meta, content)
            
            # Update meta
            meta["recovery_method"] = method
            meta["text_length"] = text_length
            meta["recovered"] = True
            meta["cleaned_file"] = f"{post_id}.md"
            meta["recovered_at"] = datetime.now().isoformat()
            save_meta(post_id, meta)
            
            # Update progress
            progress["success_count"] += 1
            
            # Method stats
            if method.startswith("bs4:"):
                progress["method_stats"]["bs4_selector"] += 1
            elif method.startswith("density:"):
                progress["method_stats"]["density_fallback"] += 1
            else:
                if method in progress["method_stats"]:
                    progress["method_stats"][method] += 1
            
            append_processed(post_id, "success", method, text_length)
            
            print(f"[{i+1}/{len(files_to_process)}] ✓ {post_id} ({method}, {text_length} chars)")
        else:
            # Failed
            meta["recovery_method"] = None
            meta["text_length"] = 0
            meta["recovered"] = False
            meta["recovery_failed_at"] = datetime.now().isoformat()
            save_meta(post_id, meta)
            
            progress["failed_count"] += 1
            progress["method_stats"]["failed"] += 1
            progress["failed_posts"].append(post_id)
            
            append_processed(post_id, "failed", "none", 0)
            
            print(f"[{i+1}/{len(files_to_process)}] ✗ {post_id} (FAILED)")
        
        progress["processed_count"] += 1
        progress["last_processed"] = post_id
        
        # Save progress every 10 files
        if (i + 1) % 10 == 0:
            save_progress(progress)
            update_snapshot(progress, total, start_time)
    
    # Final save
    save_progress(progress)
    update_snapshot(progress, total, start_time)
    
    # Generate final report
    elapsed = time.time() - start_time
    
    report = {
        "total_files": total,
        "processed": progress["processed_count"],
        "success": progress["success_count"],
        "failed": progress["failed_count"],
        "success_rate": round((progress["success_count"] / total) * 100, 2) if total > 0 else 0,
        "method_stats": progress["method_stats"],
        "failed_posts": progress["failed_posts"],
        "elapsed_seconds": round(elapsed, 2),
        "elapsed_minutes": round(elapsed / 60, 2),
        "completed_at": datetime.now().isoformat()
    }
    
    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    
    # Create done marker
    done = {
        "status": "completed",
        "completed_at": datetime.now().isoformat(),
        "total": total,
        "success": progress["success_count"],
        "failed": progress["failed_count"]
    }
    
    with open(DONE_FILE, "w", encoding="utf-8") as f:
        json.dump(done, f, ensure_ascii=False, indent=2)
    
    # Print summary
    print("\n" + "=" * 60)
    print("RECOVERY COMPLETE")
    print("=" * 60)
    print(f"Total files: {total}")
    print(f"Successfully recovered: {progress['success_count']}")
    print(f"Failed: {progress['failed_count']}")
    print(f"Success rate: {report['success_rate']}%")
    print(f"Time elapsed: {report['elapsed_minutes']:.2f} minutes")
    print("\nMethod breakdown:")
    for method, count in progress["method_stats"].items():
        print(f"  {method}: {count}")
    
    if progress["failed_posts"]:
        print(f"\nFailed posts: {progress['failed_posts'][:10]}{'...' if len(progress['failed_posts']) > 10 else ''}")
    
    print(f"\nReports saved to:")
    print(f"  - {REPORT_FILE}")
    print(f"  - {DONE_FILE}")


if __name__ == "__main__":
    main()
