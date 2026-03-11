#!/usr/bin/env python3
"""
agilestory.blog 크롤러
- 체크포인트 기반 중단/재시작 지원
- 모든 글 수집 → raw HTML 저장 → cleaned 텍스트 추출 → 메타데이터 저장
"""

import json
import os
import re
import time
import hashlib
from pathlib import Path
from datetime import datetime
from urllib.parse import urljoin
import html

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("Installing required packages...")
    import subprocess
    subprocess.run(["pip", "install", "requests", "beautifulsoup4", "-q"])
    import requests
    from bs4 import BeautifulSoup

# 설정
BASE_URL = "https://agilestory.blog"
WORK_DIR = Path("/root/.openclaw/workspace/memory/second-brain/ac2/agilestory")
MANIFESTS_DIR = WORK_DIR / "manifests"
RAW_DIR = WORK_DIR / "raw"
CLEANED_DIR = WORK_DIR / "cleaned"
META_DIR = WORK_DIR / "meta"
REPORTS_DIR = WORK_DIR / "reports"

# 재시도 설정
MAX_RETRIES = 3
BASE_DELAY = 2  # 초
MAX_DELAY = 30

class CheckpointManager:
    """체크포인트 관리자"""
    
    def __init__(self):
        self.progress_file = MANIFESTS_DIR / "progress.json"
        self.discovered_file = MANIFESTS_DIR / "urls_discovered.jsonl"
        self.processed_file = MANIFESTS_DIR / "urls_processed.jsonl"
        self.failed_file = MANIFESTS_DIR / "urls_failed.jsonl"
        
    def load_progress(self):
        """진행 상황 로드"""
        if self.progress_file.exists():
            with open(self.progress_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {
            "started_at": None,
            "last_updated": None,
            "discovered_count": 0,
            "processed_count": 0,
            "success_count": 0,
            "failed_count": 0,
            "skipped_count": 0,
            "status": "not_started"
        }
    
    def save_progress(self, progress):
        """진행 상황 저장"""
        progress["last_updated"] = datetime.now().isoformat()
        with open(self.progress_file, 'w', encoding='utf-8') as f:
            json.dump(progress, f, ensure_ascii=False, indent=2)
    
    def load_processed_urls(self):
        """처리 완료된 URL 집합 로드"""
        processed = set()
        if self.processed_file.exists():
            with open(self.processed_file, 'r', encoding='utf-8') as f:
                for line in f:
                    if line.strip():
                        data = json.loads(line)
                        processed.add(data["url"])
        return processed
    
    def load_failed_urls(self):
        """실패한 URL 목록 로드 (재시도용)"""
        failed = []
        if self.failed_file.exists():
            with open(self.failed_file, 'r', encoding='utf-8') as f:
                for line in f:
                    if line.strip():
                        data = json.loads(line)
                        if data.get("retry_count", 0) < MAX_RETRIES:
                            failed.append(data)
        return failed
    
    def append_discovered(self, entries):
        """발견된 URL 추가"""
        with open(self.discovered_file, 'a', encoding='utf-8') as f:
            for entry in entries:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    
    def append_processed(self, entry):
        """처리 완료된 URL 추가"""
        with open(self.processed_file, 'a', encoding='utf-8') as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    
    def append_failed(self, entry):
        """실패한 URL 추가"""
        with open(self.failed_file, 'a', encoding='utf-8') as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    
    def update_failed_retry(self, url, retry_count):
        """실패 URL 재시도 횟수 업데이트"""
        lines = []
        if self.failed_file.exists():
            with open(self.failed_file, 'r', encoding='utf-8') as f:
                for line in f:
                    if line.strip():
                        data = json.loads(line)
                        if data["url"] == url:
                            data["retry_count"] = retry_count
                            data["last_retry"] = datetime.now().isoformat()
                        lines.append(json.dumps(data, ensure_ascii=False))
        
        with open(self.failed_file, 'w', encoding='utf-8') as f:
            for line in lines:
                f.write(line + "\n")


class Crawler:
    """agilestory.blog 크롤러"""
    
    def __init__(self):
        self.checkpoint = CheckpointManager()
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (compatible; AC2Crawler/1.0; +https://ac2.kr)'
        })
        
    def discover_urls(self):
        """홈페이지에서 모든 글 URL 발견"""
        print("📡 글 URL 발견 중...")
        
        try:
            response = self.session.get(BASE_URL, timeout=30)
            response.raise_for_status()
        except Exception as e:
            print(f"❌ 홈페이지 접근 실패: {e}")
            return []
        
        soup = BeautifulSoup(response.text, 'html.parser')
        articles = soup.find_all('article')
        
        discovered = []
        for article in articles:
            link = article.find('a')
            if link and link.get('href'):
                href = link.get('href')
                # 상대 경로를 절대 경로로 변환
                full_url = urljoin(BASE_URL, href)
                
                # 날짜 추출
                time_elem = article.find('time')
                date_str = ""
                if time_elem and time_elem.get('datetime'):
                    date_str = time_elem.get('datetime')
                elif time_elem:
                    date_str = time_elem.get_text(strip=True)
                
                # 제목 추출
                title = link.get_text(strip=True)
                
                # ID 추출 (URL에서 숫자 부분)
                match = re.search(r'/(\d+)$', href)
                post_id = match.group(1) if match else None
                
                discovered.append({
                    "url": full_url,
                    "post_id": post_id,
                    "title": title,
                    "date": date_str,
                    "discovered_at": datetime.now().isoformat()
                })
        
        print(f"✅ {len(discovered)}개 글 발견")
        return discovered
    
    def fetch_article(self, url, retry_count=0):
        """글 HTML 가져오기"""
        delay = min(BASE_DELAY * (2 ** retry_count), MAX_DELAY)
        time.sleep(delay)
        
        try:
            response = self.session.get(url, timeout=30)
            response.raise_for_status()
            return response.text
        except Exception as e:
            print(f"⚠️ 가져오기 실패 ({url}): {e}")
            return None
    
    def extract_content(self, html_text, url):
        """HTML에서 본문 추출"""
        soup = BeautifulSoup(html_text, 'html.parser')
        
        # 메타데이터 추출
        meta = {
            "url": url,
            "title": "",
            "date": "",
            "author": "",
            "tags": [],
            "extracted_at": datetime.now().isoformat()
        }
        
        # 제목 추출
        title_elem = soup.find('h1')
        if title_elem:
            meta["title"] = title_elem.get_text(strip=True)
        
        # 날짜 추출
        time_elem = soup.find('time')
        if time_elem:
            meta["date"] = time_elem.get('datetime', time_elem.get_text(strip=True))
        
        # 본문 추출 - main 태그 또는 article 태그에서
        content_area = soup.find('main') or soup.find('article') or soup.find('body')
        
        if not content_area:
            return "", meta
        
        # 불필요한 태그 제거
        for tag in content_area.find_all(['script', 'style', 'nav', 'header', 'footer', 'aside', 'form']):
            tag.decompose()
        
        # 텍스트 추출
        text_parts = []
        for elem in content_area.find_all(['p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'pre']):
            text = elem.get_text(separator=' ', strip=True)
            if text and len(text) > 10:  # 너무 짧은 텍스트 제외
                text_parts.append(text)
        
        cleaned_text = "\n\n".join(text_parts)
        
        # HTML 엔티티 정리
        cleaned_text = html.unescape(cleaned_text)
        
        # 연속 공백 정리
        cleaned_text = re.sub(r'\n{3,}', '\n\n', cleaned_text)
        cleaned_text = re.sub(r' {2,}', ' ', cleaned_text)
        
        return cleaned_text.strip(), meta
    
    def process_article(self, entry, retry_count=0):
        """단일 글 처리"""
        url = entry["url"]
        post_id = entry.get("post_id")
        
        print(f"📄 처리 중: {entry.get('title', url)[:50]}...")
        
        # HTML 가져오기
        html_content = self.fetch_article(url, retry_count)
        if not html_content:
            return False, "fetch_failed"
        
        # raw HTML 저장
        if post_id:
            raw_file = RAW_DIR / f"{post_id}.html"
        else:
            url_hash = hashlib.md5(url.encode()).hexdigest()[:8]
            raw_file = RAW_DIR / f"{url_hash}.html"
        
        with open(raw_file, 'w', encoding='utf-8') as f:
            f.write(html_content)
        
        # 본문 추출
        cleaned_text, meta = self.extract_content(html_content, url)
        
        # 메타데이터에 추가 정보
        meta["post_id"] = post_id
        meta["raw_file"] = str(raw_file.name)
        
        if not cleaned_text:
            print(f"⚠️ 본문 추출 실패: {url}")
            meta["extraction_status"] = "empty"
        else:
            meta["extraction_status"] = "success"
            meta["text_length"] = len(cleaned_text)
            
            # cleaned 텍스트 저장
            if post_id:
                cleaned_file = CLEANED_DIR / f"{post_id}.txt"
            else:
                cleaned_file = CLEANED_DIR / f"{url_hash}.txt"
            
            with open(cleaned_file, 'w', encoding='utf-8') as f:
                f.write(cleaned_text)
            
            meta["cleaned_file"] = str(cleaned_file.name)
        
        # 메타데이터 저장
        if post_id:
            meta_file = META_DIR / f"{post_id}.json"
        else:
            meta_file = META_DIR / f"{url_hash}.json"
        
        with open(meta_file, 'w', encoding='utf-8') as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)
        
        return True, "success"
    
    def run(self):
        """크롤러 실행"""
        # 디렉토리 확인
        for d in [MANIFESTS_DIR, RAW_DIR, CLEANED_DIR, META_DIR, REPORTS_DIR]:
            d.mkdir(parents=True, exist_ok=True)
        
        # 진행 상황 로드
        progress = self.checkpoint.load_progress()
        processed_urls = self.checkpoint.load_processed_urls()
        
        if progress["status"] == "completed":
            print("✅ 이미 완료된 작업입니다.")
            return
        
        # 시작 시간 기록
        if not progress["started_at"]:
            progress["started_at"] = datetime.now().isoformat()
        progress["status"] = "running"
        self.checkpoint.save_progress(progress)
        
        # URL 발견
        discovered = self.discover_urls()
        progress["discovered_count"] = len(discovered)
        self.checkpoint.save_progress(progress)
        
        # 발견된 URL 저장
        self.checkpoint.append_discovered(discovered)
        
        # 처리할 URL 필터링 (이미 처리된 것 제외)
        to_process = [e for e in discovered if e["url"] not in processed_urls]
        
        # 실패한 URL 재시도 큐
        failed_urls = self.checkpoint.load_failed_urls()
        for entry in failed_urls:
            if entry not in to_process:
                to_process.append(entry)
        
        total = len(to_process)
        print(f"📊 처리 대상: {total}개 (이미 처리됨: {len(processed_urls)}개)")
        
        if total == 0:
            print("✅ 처리할 새 글이 없습니다.")
            self.finalize(progress)
            return
        
        # 처리 시작
        start_time = time.time()
        success_count = progress["success_count"]
        failed_count = progress["failed_count"]
        
        for i, entry in enumerate(to_process, 1):
            url = entry["url"]
            retry_count = entry.get("retry_count", 0)
            
            success, status = self.process_article(entry, retry_count)
            
            if success:
                success_count += 1
                processed_entry = {
                    "url": url,
                    "post_id": entry.get("post_id"),
                    "title": entry.get("title"),
                    "status": status,
                    "processed_at": datetime.now().isoformat()
                }
                self.checkpoint.append_processed(processed_entry)
            else:
                failed_count += 1
                retry_count += 1
                failed_entry = {
                    "url": url,
                    "post_id": entry.get("post_id"),
                    "title": entry.get("title"),
                    "error": status,
                    "retry_count": retry_count,
                    "first_failed_at": datetime.now().isoformat()
                }
                self.checkpoint.append_failed(failed_entry)
            
            # 진행 상황 업데이트
            progress["success_count"] = success_count
            progress["failed_count"] = failed_count
            progress["processed_count"] = len(processed_urls) + i
            self.checkpoint.save_progress(progress)
            
            # 진행률 표시
            elapsed = time.time() - start_time
            rate = i / elapsed if elapsed > 0 else 0
            eta = (total - i) / rate if rate > 0 else 0
            
            print(f"📈 진행률: {i}/{total} ({i*100//total}%) | "
                  f"성공: {success_count} | 실패: {failed_count} | "
                  f"ETA: {int(eta//60)}분 {int(eta%60)}초")
        
        # 완료 처리
        self.finalize(progress)
    
    def finalize(self, progress):
        """완료 처리 및 검증 리포트 생성"""
        print("\n📋 검증 리포트 생성 중...")
        
        # 최종 상태
        progress["status"] = "completed"
        progress["completed_at"] = datetime.now().isoformat()
        self.checkpoint.save_progress(progress)
        
        # 발견된 URL 수 확인
        discovered_count = 0
        if self.checkpoint.discovered_file.exists():
            with open(self.checkpoint.discovered_file, 'r') as f:
                discovered_count = sum(1 for _ in f)
        
        # 처리된 URL 수 확인
        processed_count = 0
        success_count = 0
        if self.checkpoint.processed_file.exists():
            with open(self.checkpoint.processed_file, 'r') as f:
                for line in f:
                    if line.strip():
                        processed_count += 1
                        data = json.loads(line)
                        if data.get("status") == "success":
                            success_count += 1
        
        # 실패 URL 수 확인
        failed_count = 0
        final_failed = []
        if self.checkpoint.failed_file.exists():
            with open(self.checkpoint.failed_file, 'r') as f:
                for line in f:
                    if line.strip():
                        data = json.loads(line)
                        failed_count += 1
                        if data.get("retry_count", 0) >= MAX_RETRIES:
                            final_failed.append(data)
        
        # 검증 리포트
        coverage_report = {
            "generated_at": datetime.now().isoformat(),
            "discovered_urls": discovered_count,
            "processed_urls": processed_count,
            "success_count": success_count,
            "failed_count": failed_count,
            "final_failed_count": len(final_failed),
            "validation": {
                "discovered_equals_processed_plus_failed": discovered_count == processed_count + (failed_count - len(final_failed)),
                "all_processed": discovered_count == processed_count + len(final_failed)
            },
            "final_failed_urls": final_failed,
            "summary": {
                "coverage_percent": round(success_count / discovered_count * 100, 2) if discovered_count > 0 else 0,
                "raw_files": len(list(RAW_DIR.glob("*.html"))),
                "cleaned_files": len(list(CLEANED_DIR.glob("*.txt"))),
                "meta_files": len(list(META_DIR.glob("*.json")))
            }
        }
        
        with open(REPORTS_DIR / "coverage_report.json", 'w', encoding='utf-8') as f:
            json.dump(coverage_report, f, ensure_ascii=False, indent=2)
        
        # 완료 표시 파일
        ingest_done = {
            "completed_at": datetime.now().isoformat(),
            "status": "completed",
            "total_articles": discovered_count,
            "successful": success_count,
            "failed": len(final_failed),
            "coverage_percent": coverage_report["summary"]["coverage_percent"]
        }
        
        with open(REPORTS_DIR / "ingest_done.json", 'w', encoding='utf-8') as f:
            json.dump(ingest_done, f, ensure_ascii=False, indent=2)
        
        print(f"\n✅ 크롤링 완료!")
        print(f"📊 발견: {discovered_count}개")
        print(f"✅ 성공: {success_count}개")
        print(f"❌ 실패: {len(final_failed)}개")
        print(f"📈 커버리지: {coverage_report['summary']['coverage_percent']}%")
        print(f"📁 리포트: {REPORTS_DIR / 'coverage_report.json'}")


if __name__ == "__main__":
    crawler = Crawler()
    crawler.run()
