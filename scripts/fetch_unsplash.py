#!/usr/bin/env python3
"""Unsplash 이미지 검색 스크립트 - 블로그 글에 자동 이미지 삽입용"""

import sys
import json
import urllib.request
import urllib.parse
import os

UNSPLASH_KEY = os.environ.get('UNSPLASH_ACCESS_KEY', '9BhmO8-OZoRSAqx5yG0-cPh2ULxiOsB1XShYcTaa808')

def search_photo(query: str, orientation: str = "landscape") -> dict | None:
    """Unsplash에서 이미지 검색, 첫 번째 결과 반환"""
    params = urllib.parse.urlencode({
        'query': query,
        'per_page': 1,
        'orientation': orientation,
    })
    url = f"https://api.unsplash.com/search/photos?{params}"
    req = urllib.request.Request(url, headers={
        'Authorization': f'Client-ID {UNSPLASH_KEY}'
    })
    
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
            if data.get('results'):
                img = data['results'][0]
                return {
                    'url': img['urls']['regular'],  # 1080px
                    'small': img['urls']['small'],   # 400px
                    'author': img['user']['name'],
                    'author_url': img['user']['links']['html'],
                    'unsplash_url': img['links']['html'],
                    'alt': img.get('alt_description', query),
                    'download_url': img['links']['download_location'],
                }
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
    return None


def trigger_download(download_url: str):
    """Unsplash 이용약관: 다운로드 트리거 필수"""
    req = urllib.request.Request(download_url, headers={
        'Authorization': f'Client-ID {UNSPLASH_KEY}'
    })
    try:
        urllib.request.urlopen(req)
    except:
        pass


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: fetch_unsplash.py <search query>")
        sys.exit(1)
    
    query = ' '.join(sys.argv[1:])
    result = search_photo(query)
    
    if result:
        trigger_download(result['download_url'])
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("No results found", file=sys.stderr)
        sys.exit(1)
