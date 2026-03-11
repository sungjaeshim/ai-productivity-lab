#!/usr/bin/env python3
"""
피드백 대시보드 서버
SQLite DB에서 데이터를 조회하여 API 제공
"""

import json
import sqlite3
from datetime import datetime, timedelta
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import parse_qs, urlparse
import logging

# 설정
DB_PATH = Path(__file__).parent.parent / 'metrics.db'
STATIC_DIR = Path(__file__).parent / 'static'
PORT = 8765

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class DashboardHandler(SimpleHTTPRequestHandler):
    """대시보드 HTTP 핸들러"""
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)
    
    def get_db_connection(self):
        """DB 연결 반환"""
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        return conn
    
    def do_GET(self):
        """GET 요청 처리"""
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        
        # API 라우팅
        if path.startswith('/api/'):
            self.handle_api(path[4:], query)
        else:
            # 정적 파일 서빙
            super().do_GET()
    
    def handle_api(self, endpoint, query):
        """API 엔드포인트 처리"""
        try:
            if endpoint == 'summary':
                data = self.get_summary()
            elif endpoint == 'timeseries':
                days = int(query.get('days', [7])[0])
                data = self.get_timeseries(days)
            elif endpoint == 'decision-types':
                data = self.get_decision_types()
            elif endpoint == 'priority':
                limit = int(query.get('limit', [10])[0])
                data = self.get_priority_queue(limit)
            elif endpoint == 'decisions/recent':
                limit = int(query.get('limit', [10])[0])
                data = self.get_recent_decisions(limit)
            elif endpoint == 'experiments':
                data = self.get_experiments()
            elif endpoint == 'health':
                data = {'status': 'ok', 'timestamp': datetime.now().isoformat()}
            else:
                self.send_error(404, 'Not Found')
                return
            
            self.send_json_response(data)
            
        except Exception as e:
            logger.error(f"API Error ({endpoint}): {e}")
            self.send_error(500, str(e))
    
    def send_json_response(self, data):
        """JSON 응답 전송"""
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, default=str).encode())
    
    def get_summary(self):
        """대시보드 요약 데이터"""
        conn = self.get_db_connection()
        cursor = conn.cursor()
        
        # 전체 통계
        cursor.execute("""
            SELECT COUNT(*) as total FROM decisions
        """)
        total_decisions = cursor.fetchone()['total']
        
        # 성공한 의사결정 (outcome이 'success')
        cursor.execute("""
            SELECT COUNT(*) as count FROM decisions
            WHERE outcome = 'success'
        """)
        success_count = cursor.fetchone()['count']
        
        success_rate = (success_count / total_decisions * 100) if total_decisions > 0 else 0
        
        # 에러 통계
        cursor.execute("""
            SELECT COUNT(*) as total FROM errors
        """)
        total_errors = cursor.fetchone()['total']
        
        cursor.execute("""
            SELECT COUNT(*) as total FROM tasks
        """)
        total_tasks = cursor.fetchone()['total']
        
        error_rate = (total_errors / total_tasks * 100) if total_tasks > 0 else 0
        
        # 평균 작업 시간 (완료된 작업 기준)
        cursor.execute("""
            SELECT AVG(
                (julianday(completed_at) - julianday(started_at)) * 86400000
            ) as avg_time
            FROM tasks
            WHERE completed_at IS NOT NULL AND started_at IS NOT NULL
        """)
        row = cursor.fetchone()
        avg_response_time = row['avg_time'] if row and row['avg_time'] else 0
        
        # 일별 변화율 (어제 vs 오늘)
        today = datetime.now().date()
        yesterday = today - timedelta(days=1)
        
        cursor.execute("""
            SELECT COUNT(*) as count FROM decisions
            WHERE date(created_at) = ?
        """, (str(today),))
        today_decisions = cursor.fetchone()['count']
        
        cursor.execute("""
            SELECT COUNT(*) as count FROM decisions
            WHERE date(created_at) = ?
        """, (str(yesterday),))
        yesterday_decisions = cursor.fetchone()['count']
        
        decisions_change = 0
        if yesterday_decisions > 0:
            decisions_change = ((today_decisions - yesterday_decisions) / yesterday_decisions) * 100
        
        conn.close()
        
        return {
            'totalDecisions': total_decisions,
            'successRate': success_rate,
            'avgResponseTime': avg_response_time,
            'errorRate': error_rate,
            'changes': {
                'decisions': decisions_change,
                'success': 0,
                'response': 0,
                'errors': 0
            }
        }
    
    def get_timeseries(self, days=7):
        """시계열 데이터"""
        conn = self.get_db_connection()
        cursor = conn.cursor()
        
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=days)
        
        # 일별 의사결정 수
        cursor.execute("""
            SELECT date(created_at) as date, COUNT(*) as count
            FROM decisions
            WHERE date(created_at) >= ?
            GROUP BY date(created_at)
            ORDER BY date
        """, (str(start_date),))
        
        decisions_by_date = {row['date']: row['count'] for row in cursor.fetchall()}
        
        # 일별 성공 수
        cursor.execute("""
            SELECT date(created_at) as date, COUNT(*) as count
            FROM decisions
            WHERE date(created_at) >= ? AND outcome = 'success'
            GROUP BY date(created_at)
            ORDER BY date
        """, (str(start_date),))
        
        success_by_date = {row['date']: row['count'] for row in cursor.fetchall()}
        
        # 일별 에러 수
        cursor.execute("""
            SELECT date(created_at) as date, COUNT(*) as count
            FROM errors
            WHERE date(created_at) >= ?
            GROUP BY date(created_at)
            ORDER BY date
        """, (str(start_date),))
        
        errors_by_date = {row['date']: row['count'] for row in cursor.fetchall()}
        
        conn.close()
        
        # 결과 생성
        result = []
        current = start_date
        while current <= end_date:
            date_str = str(current)
            result.append({
                'date': current.strftime('%m/%d'),
                'decisions': decisions_by_date.get(date_str, 0),
                'successes': success_by_date.get(date_str, 0),
                'errors': errors_by_date.get(date_str, 0)
            })
            current += timedelta(days=1)
        
        return result
    
    def get_decision_types(self):
        """의사결정 유형 분포"""
        conn = self.get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT decision_type as type, COUNT(*) as count
            FROM decisions
            WHERE decision_type IS NOT NULL
            GROUP BY decision_type
            ORDER BY count DESC
        """)
        
        types = [dict(row) for row in cursor.fetchall()]
        conn.close()
        
        return {'types': types}
    
    def get_priority_queue(self, limit=10):
        """우선순위 큐"""
        conn = self.get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT id, item_type, title, priority_score, status, created_at
            FROM priority_items
            ORDER BY priority_score DESC
            LIMIT ?
        """, (limit,))
        
        items = [dict(row) for row in cursor.fetchall()]
        conn.close()
        
        return {'items': items}
    
    def get_recent_decisions(self, limit=10):
        """최근 의사결정"""
        conn = self.get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT id, decision_type, outcome, confidence, created_at
            FROM decisions
            ORDER BY created_at DESC
            LIMIT ?
        """, (limit,))
        
        items = [dict(row) for row in cursor.fetchall()]
        conn.close()
        
        return {'items': items}
    
    def get_experiments(self):
        """진행 중인 실험"""
        conn = self.get_db_connection()
        cursor = conn.cursor()
        
        # ab_testing 테이블 확인 후 쿼리
        try:
            cursor.execute("""
                SELECT experiment_id, name, status, 
                       (samples_collected * 100.0 / NULLIF(sample_size, 0)) as progress
                FROM experiments
                WHERE status IN ('running', 'pending')
                ORDER BY created_at DESC
            """)
            experiments = [dict(row) for row in cursor.fetchall()]
        except sqlite3.OperationalError:
            experiments = []
        
        conn.close()
        
        return {'experiments': experiments}
    
    def log_message(self, format, *args):
        """로그 메시지 포맷"""
        if '/api/' in args[0]:
            logger.info(f"{self.address_string()} - {args[0]}")


def run_server():
    """서버 실행"""
    server = HTTPServer(('0.0.0.0', PORT), DashboardHandler)
    logger.info(f"Dashboard server running at http://localhost:{PORT}")
    logger.info(f"Database: {DB_PATH}")
    logger.info(f"Static files: {STATIC_DIR}")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Server stopped")
        server.shutdown()


if __name__ == '__main__':
    run_server()
