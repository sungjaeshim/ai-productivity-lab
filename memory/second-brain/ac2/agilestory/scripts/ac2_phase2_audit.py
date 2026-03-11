#!/usr/bin/env python3
"""
AC2 Phase 2: Codex Audit / Tag Quality / Search Test
Performs quality checks on extracted content and metadata.

Phase 2 Tasks:
1. Codex Audit - Text quality verification
2. Tag Quality - Metadata tag validation
3. Search Test - Keyword search functionality test
"""

import os
import sys
import json
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Tuple
from collections import Counter, defaultdict

# Base directories
BASE_DIR = Path(__file__).parent.parent
RAW_DIR = BASE_DIR / "raw"
CLEANED_DIR = BASE_DIR / "cleaned"
META_DIR = BASE_DIR / "meta"
REPORTS_DIR = BASE_DIR / "reports"
MANIFESTS_DIR = BASE_DIR / "manifests"

# Ensure reports directory exists
REPORTS_DIR.mkdir(parents=True, exist_ok=True)

# Output files
AUDIT_REPORT = REPORTS_DIR / "phase2_audit_report.json"
TAG_REPORT = REPORTS_DIR / "phase2_tag_report.json"
SEARCH_REPORT = REPORTS_DIR / "phase2_search_report.json"
SUMMARY_REPORT = REPORTS_DIR / "phase2_summary.md"

# Quality thresholds
MIN_TEXT_LENGTH = 100  # Minimum characters for valid content
MAX_TEXT_LENGTH = 100000  # Maximum expected characters
MIN_TAG_COUNT = 1  # Minimum tags expected per post
MAX_DUPLICATE_RATIO = 0.3  # Max ratio of duplicate content


def load_meta_files() -> List[Dict[str, Any]]:
    """Load all metadata files."""
    meta_files = list(META_DIR.glob("*.json"))
    metas = []
    for mf in meta_files:
        try:
            with open(mf, "r", encoding="utf-8") as f:
                meta = json.load(f)
                meta["_file"] = str(mf)
                metas.append(meta)
        except Exception as e:
            print(f"Error loading {mf}: {e}")
    return metas


def load_cleaned_files() -> Dict[str, str]:
    """Load all cleaned markdown files."""
    cleaned = {}
    for cf in CLEANED_DIR.glob("*.md"):
        try:
            with open(cf, "r", encoding="utf-8") as f:
                cleaned[cf.stem] = f.read()
        except Exception as e:
            print(f"Error loading {cf}: {e}")
    return cleaned


# ============================================================================
# Task 1: Codex Audit - Text Quality Verification
# ============================================================================

def codex_audit(cleaned_files: Dict[str, str]) -> Dict[str, Any]:
    """
    Perform text quality audit.
    Checks:
    - Empty files
    - Too short content
    - Too long content (potential error)
    - Encoding issues
    - Duplicate content ratio
    """
    print("\n" + "=" * 60)
    print("TASK 1: Codex Audit - Text Quality Verification")
    print("=" * 60)
    
    results = {
        "total_files": len(cleaned_files),
        "empty_files": [],
        "too_short": [],
        "too_long": [],
        "encoding_issues": [],
        "high_duplicate_ratio": [],
        "quality_scores": {},
        "stats": {
            "total_chars": 0,
            "avg_chars": 0,
            "median_chars": 0,
            "min_chars": float('inf'),
            "max_chars": 0
        }
    }
    
    lengths = []
    
    for post_id, content in cleaned_files.items():
        text_len = len(content.strip())
        lengths.append(text_len)
        
        # Check empty
        if text_len == 0:
            results["empty_files"].append(post_id)
            continue
        
        # Check too short
        if text_len < MIN_TEXT_LENGTH:
            results["too_short"].append({
                "post_id": post_id,
                "length": text_len
            })
        
        # Check too long
        if text_len > MAX_TEXT_LENGTH:
            results["too_long"].append({
                "post_id": post_id,
                "length": text_len
            })
        
        # Check encoding issues (replacement character)
        if '\ufffd' in content:
            results["encoding_issues"].append(post_id)
        
        # Calculate duplicate ratio
        paragraphs = [p.strip() for p in content.split('\n\n') if p.strip()]
        if paragraphs:
            unique = set(p.lower() for p in paragraphs)
            dup_ratio = 1 - (len(unique) / len(paragraphs))
            if dup_ratio > MAX_DUPLICATE_RATIO:
                results["high_duplicate_ratio"].append({
                    "post_id": post_id,
                    "ratio": round(dup_ratio, 2)
                })
        
        # Calculate quality score (0-100)
        score = 100
        if text_len < MIN_TEXT_LENGTH:
            score -= 30
        if '\ufffd' in content:
            score -= 20
        if post_id in [d["post_id"] for d in results["high_duplicate_ratio"]]:
            score -= 10
        
        results["quality_scores"][post_id] = max(0, score)
    
    # Calculate stats
    if lengths:
        results["stats"]["total_chars"] = sum(lengths)
        results["stats"]["avg_chars"] = round(sum(lengths) / len(lengths), 2)
        results["stats"]["median_chars"] = sorted(lengths)[len(lengths) // 2]
        results["stats"]["min_chars"] = min(lengths)
        results["stats"]["max_chars"] = max(lengths)
    
    # Print summary
    print(f"Total files: {results['total_files']}")
    print(f"Empty files: {len(results['empty_files'])}")
    print(f"Too short (<{MIN_TEXT_LENGTH} chars): {len(results['too_short'])}")
    print(f"Too long (>{MAX_TEXT_LENGTH} chars): {len(results['too_long'])}")
    print(f"Encoding issues: {len(results['encoding_issues'])}")
    print(f"High duplicate ratio: {len(results['high_duplicate_ratio'])}")
    print(f"\nText length stats:")
    print(f"  Total chars: {results['stats']['total_chars']:,}")
    print(f"  Avg chars: {results['stats']['avg_chars']:,.2f}")
    print(f"  Median chars: {results['stats']['median_chars']:,}")
    print(f"  Min chars: {results['stats']['min_chars']:,}")
    print(f"  Max chars: {results['stats']['max_chars']:,}")
    
    return results


# ============================================================================
# Task 2: Tag Quality - Metadata Tag Validation
# ============================================================================

def tag_quality_audit(meta_files: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Perform metadata tag quality audit.
    Checks:
    - Missing tags
    - Empty tags
    - Tag frequency distribution
    - Tag format consistency
    """
    print("\n" + "=" * 60)
    print("TASK 2: Tag Quality - Metadata Tag Validation")
    print("=" * 60)
    
    results = {
        "total_posts": len(meta_files),
        "missing_tags": [],
        "empty_tags": [],
        "tag_frequency": Counter(),
        "tag_co_occurrence": defaultdict(int),
        "orphan_posts": [],  # Posts with no useful tags
        "stats": {
            "total_tags": 0,
            "unique_tags": 0,
            "avg_tags_per_post": 0,
            "posts_without_tags": 0
        }
    }
    
    all_tags = []
    
    for meta in meta_files:
        post_id = Path(meta.get("_file", "")).stem
        tags = meta.get("tags", [])
        
        if not tags:
            results["missing_tags"].append(post_id)
            results["orphan_posts"].append(post_id)
            continue
        
        # Filter empty tags
        valid_tags = [t for t in tags if t and t.strip()]
        
        if len(valid_tags) < len(tags):
            results["empty_tags"].append({
                "post_id": post_id,
                "empty_count": len(tags) - len(valid_tags)
            })
        
        if not valid_tags:
            results["orphan_posts"].append(post_id)
            continue
        
        # Normalize tags
        normalized = [t.strip().lower() for t in valid_tags]
        all_tags.extend(normalized)
        
        # Tag frequency
        results["tag_frequency"].update(normalized)
        
        # Tag co-occurrence
        for i, t1 in enumerate(normalized):
            for t2 in normalized[i+1:]:
                pair = tuple(sorted([t1, t2]))
                results["tag_co_occurrence"][pair] += 1
    
    # Calculate stats
    results["stats"]["total_tags"] = len(all_tags)
    results["stats"]["unique_tags"] = len(results["tag_frequency"])
    results["stats"]["posts_without_tags"] = len(results["orphan_posts"])
    if meta_files:
        results["stats"]["avg_tags_per_post"] = round(
            len(all_tags) / len(meta_files), 2
        )
    
    # Print summary
    print(f"Total posts: {results['total_posts']}")
    print(f"Posts without tags: {len(results['missing_tags'])}")
    print(f"Posts with empty tags: {len(results['empty_tags'])}")
    print(f"Orphan posts (no valid tags): {len(results['orphan_posts'])}")
    print(f"\nTag statistics:")
    print(f"  Total tags: {results['stats']['total_tags']:,}")
    print(f"  Unique tags: {results['stats']['unique_tags']:,}")
    print(f"  Avg tags per post: {results['stats']['avg_tags_per_post']}")
    
    # Top 20 tags
    print(f"\nTop 20 tags:")
    for tag, count in results["tag_frequency"].most_common(20):
        print(f"  {tag}: {count}")
    
    # Convert Counter/defaultdict to JSON-safe dicts
    results["tag_frequency"] = dict(results["tag_frequency"])
    results["tag_co_occurrence"] = {
        "|".join(pair): count for pair, count in results["tag_co_occurrence"].items()
    }
    
    return results


# ============================================================================
# Task 3: Search Test - Keyword Search Functionality
# ============================================================================

def search_test(cleaned_files: Dict[str, str], meta_files: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Test keyword search functionality.
    Tests:
    - Basic keyword search
    - Multi-keyword search
    - Tag-based search
    - Search result ranking
    """
    print("\n" + "=" * 60)
    print("TASK 3: Search Test - Keyword Search Functionality")
    print("=" * 60)
    
    # Build search index
    search_index = {}
    meta_by_id = {}
    
    for post_id, content in cleaned_files.items():
        search_index[post_id] = content.lower()
    
    for meta in meta_files:
        post_id = Path(meta.get("_file", "")).stem
        meta_by_id[post_id] = meta
    
    # Test queries
    test_queries = [
        "코칭",
        "애자일",
        "스크럼",
        "팀장",
        "개발자",
        "피드백",
        "코드리뷰",
        "TDD",
        "리팩토링",
        "협업"
    ]
    
    results = {
        "index_size": len(search_index),
        "test_queries": {},
        "search_performance": {},
        "issues": []
    }
    
    def simple_search(query: str, index: Dict[str, str]) -> List[Dict]:
        """Simple keyword search."""
        matches = []
        query_lower = query.lower()
        
        for post_id, content in index.items():
            if query_lower in content:
                count = content.count(query_lower)
                matches.append({
                    "post_id": post_id,
                    "count": count,
                    "relevance": count  # Simple relevance score
                })
        
        # Sort by relevance
        matches.sort(key=lambda x: x["relevance"], reverse=True)
        return matches
    
    print(f"Search index size: {results['index_size']} documents")
    print(f"\nTest queries:")
    
    for query in test_queries:
        import time
        start = time.time()
        matches = simple_search(query, search_index)
        elapsed = time.time() - start
        
        results["test_queries"][query] = {
            "match_count": len(matches),
            "top_results": matches[:5],
            "search_time_ms": round(elapsed * 1000, 2)
        }
        
        print(f"  '{query}': {len(matches)} matches ({elapsed*1000:.2f}ms)")
        
        # Check for issues
        if len(matches) == 0:
            results["issues"].append(f"No matches for query: {query}")
    
    # Test combined search
    print("\nCombined search tests:")
    combined_queries = [
        ("코칭", "피드백"),
        ("애자일", "팀"),
        ("개발", "품질")
    ]
    
    results["combined_queries"] = {}
    
    for q1, q2 in combined_queries:
        matches1 = set(m["post_id"] for m in simple_search(q1, search_index))
        matches2 = set(m["post_id"] for m in simple_search(q2, search_index))
        intersection = matches1 & matches2
        union = matches1 | matches2
        
        results["combined_queries"][f"{q1}+{q2}"] = {
            "q1_matches": len(matches1),
            "q2_matches": len(matches2),
            "intersection": len(intersection),
            "union": len(union)
        }
        
        print(f"  '{q1}' + '{q2}': {len(intersection)} common, {len(union)} total")
    
    # Summary stats
    avg_time = sum(
        q["search_time_ms"] for q in results["test_queries"].values()
    ) / len(results["test_queries"])
    
    results["search_performance"]["avg_search_time_ms"] = round(avg_time, 2)
    print(f"\nAverage search time: {avg_time:.2f}ms")
    
    return results


# ============================================================================
# Main Execution
# ============================================================================

def main():
    print("=" * 60)
    print("AC2 Phase 2: Codex Audit / Tag Quality / Search Test")
    print("=" * 60)
    print(f"Started at: {datetime.now().isoformat()}")
    
    # Load data
    print("\nLoading data...")
    cleaned_files = load_cleaned_files()
    meta_files = load_meta_files()
    
    print(f"Loaded {len(cleaned_files)} cleaned files")
    print(f"Loaded {len(meta_files)} metadata files")
    
    # Task 1: Codex Audit
    codex_results = codex_audit(cleaned_files)
    
    # Task 2: Tag Quality
    tag_results = tag_quality_audit(meta_files)
    
    # Task 3: Search Test
    search_results = search_test(cleaned_files, meta_files)
    
    # Save reports
    print("\n" + "=" * 60)
    print("Saving Reports")
    print("=" * 60)
    
    with open(AUDIT_REPORT, "w", encoding="utf-8") as f:
        json.dump(codex_results, f, ensure_ascii=False, indent=2)
    print(f"✓ Saved: {AUDIT_REPORT}")
    
    with open(TAG_REPORT, "w", encoding="utf-8") as f:
        json.dump(tag_results, f, ensure_ascii=False, indent=2)
    print(f"✓ Saved: {TAG_REPORT}")
    
    with open(SEARCH_REPORT, "w", encoding="utf-8") as f:
        json.dump(search_results, f, ensure_ascii=False, indent=2)
    print(f"✓ Saved: {SEARCH_REPORT}")
    
    # Generate summary markdown
    summary = f"""# AC2 Phase 2 Audit Summary

Generated: {datetime.now().isoformat()}

## Overview

- **Total Documents**: {codex_results['total_files']}
- **Total Metadata Files**: {tag_results['total_posts']}

## Task 1: Codex Audit Results

| Metric | Value |
|--------|-------|
| Empty Files | {len(codex_results['empty_files'])} |
| Too Short (<{MIN_TEXT_LENGTH} chars) | {len(codex_results['too_short'])} |
| Too Long (>{MAX_TEXT_LENGTH} chars) | {len(codex_results['too_long'])} |
| Encoding Issues | {len(codex_results['encoding_issues'])} |
| High Duplicate Ratio | {len(codex_results['high_duplicate_ratio'])} |

### Text Length Statistics

- Total Characters: {codex_results['stats']['total_chars']:,}
- Average: {codex_results['stats']['avg_chars']:,.2f}
- Median: {codex_results['stats']['median_chars']:,}
- Min: {codex_results['stats']['min_chars']:,}
- Max: {codex_results['stats']['max_chars']:,}

## Task 2: Tag Quality Results

| Metric | Value |
|--------|-------|
| Posts Without Tags | {len(tag_results['missing_tags'])} |
| Orphan Posts | {len(tag_results['orphan_posts'])} |
| Total Tags | {tag_results['stats']['total_tags']:,} |
| Unique Tags | {tag_results['stats']['unique_tags']:,} |
| Avg Tags/Post | {tag_results['stats']['avg_tags_per_post']} |

### Top 10 Tags

"""
    for tag, count in sorted(tag_results['tag_frequency'].items(), key=lambda x: -x[1])[:10]:
        summary += f"- {tag}: {count}\n"
    
    summary += f"""
## Task 3: Search Test Results

- **Index Size**: {search_results['index_size']} documents
- **Average Search Time**: {search_results['search_performance']['avg_search_time_ms']}ms

### Test Query Results

| Query | Matches | Time (ms) |
|-------|---------|-----------|
"""
    for query, data in search_results['test_queries'].items():
        summary += f"| {query} | {data['match_count']} | {data['search_time_ms']} |\n"
    
    summary += f"""
## Issues Found

"""
    if codex_results['empty_files']:
        summary += f"### Empty Files ({len(codex_results['empty_files'])})\n"
        for f in codex_results['empty_files'][:10]:
            summary += f"- {f}\n"
        if len(codex_results['empty_files']) > 10:
            summary += f"- ... and {len(codex_results['empty_files']) - 10} more\n"
    
    if search_results['issues']:
        summary += f"### Search Issues\n"
        for issue in search_results['issues']:
            summary += f"- {issue}\n"
    
    with open(SUMMARY_REPORT, "w", encoding="utf-8") as f:
        f.write(summary)
    print(f"✓ Saved: {SUMMARY_REPORT}")
    
    # Final summary
    print("\n" + "=" * 60)
    print("PHASE 2 AUDIT COMPLETE")
    print("=" * 60)
    print(f"Completed at: {datetime.now().isoformat()}")
    print(f"\nReports saved to:")
    print(f"  - {AUDIT_REPORT}")
    print(f"  - {TAG_REPORT}")
    print(f"  - {SEARCH_REPORT}")
    print(f"  - {SUMMARY_REPORT}")


if __name__ == "__main__":
    main()
