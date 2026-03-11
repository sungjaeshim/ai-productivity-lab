#!/usr/bin/env python3
"""
Metrics API Routes
Phase 4 Task T-015

Endpoints:
- GET /api/metrics          # 전체 메트릭
- GET /api/metrics/summary  # 메트릭 요약
"""

import logging
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List

from fastapi import APIRouter, Query
from pydantic import BaseModel

logger = logging.getLogger(__name__)
router = APIRouter()

# 데이터베이스 경로
from pathlib import Path
DB_PATH = Path.home() / ".openclaw" / "workspace" / "scripts" / "feedback" / "metrics.db"


class MetricSummary(BaseModel):
    """메트릭 요약 모델"""
    decisions: Dict[str, Any]
    tasks: Dict[str, Any]
    errors: Dict[str, Any]
    feedback: Dict[str, Any]
    timestamp: str


class MetricsResponse(BaseModel):
    """전체 메트릭 응답 모델"""
    summary: MetricSummary
    recent_decisions: List[Dict[str, Any]]
    recent_tasks: List[Dict[str, Any]]
    recent_errors: List[Dict[str, Any]]
    recent_feedback: List[Dict[str, Any]]


def _get_db_connection():
    """데이터베이스 연결 반환"""
    import sqlite3
    if not DB_PATH.exists():
        return None
    
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


async def get_metrics_summary() -> Dict[str, Any]:
    """
    메트릭 요약 조회 (다른 모듈에서도 사용)
    
    Returns:
        Dict: 메트릭 요약 데이터
    """
    conn = _get_db_connection()
    if not conn:
        return {
            "decisions": {"total": 0, "today": 0},
            "tasks": {"total": 0, "completed": 0, "pending": 0},
            "errors": {"total": 0, "unresolved": 0},
            "feedback": {"total": 0, "positive": 0, "negative": 0},
            "timestamp": datetime.now().isoformat()
        }
    
    try:
        cursor = conn.cursor()
        today = datetime.now().strftime("%Y-%m-%d")
        
        # Decisions 요약
        cursor.execute("SELECT COUNT(*) as count FROM decisions")
        decisions_total = cursor.fetchone()["count"]
        cursor.execute("SELECT COUNT(*) as count FROM decisions WHERE date(created_at) = ?", (today,))
        decisions_today = cursor.fetchone()["count"]
        
        # Tasks 요약
        cursor.execute("SELECT COUNT(*) as count FROM tasks")
        tasks_total = cursor.fetchone()["count"]
        cursor.execute("SELECT COUNT(*) as count FROM tasks WHERE status = 'completed'")
        tasks_completed = cursor.fetchone()["count"]
        cursor.execute("SELECT COUNT(*) as count FROM tasks WHERE status = 'pending'")
        tasks_pending = cursor.fetchone()["count"]
        
        # Errors 요약
        cursor.execute("SELECT COUNT(*) as count FROM errors")
        errors_total = cursor.fetchone()["count"]
        cursor.execute("SELECT COUNT(*) as count FROM errors WHERE resolved = 0")
        errors_unresolved = cursor.fetchone()["count"]
        
        # Feedback 요약
        cursor.execute("SELECT COUNT(*) as count FROM feedback")
        feedback_total = cursor.fetchone()["count"]
        cursor.execute("SELECT COUNT(*) as count FROM feedback WHERE sentiment > 0.5")
        feedback_positive = cursor.fetchone()["count"]
        cursor.execute("SELECT COUNT(*) as count FROM feedback WHERE sentiment < -0.5")
        feedback_negative = cursor.fetchone()["count"]
        
        return {
            "decisions": {
                "total": decisions_total,
                "today": decisions_today
            },
            "tasks": {
                "total": tasks_total,
                "completed": tasks_completed,
                "pending": tasks_pending,
                "completion_rate": round(tasks_completed / tasks_total * 100, 1) if tasks_total > 0 else 0
            },
            "errors": {
                "total": errors_total,
                "unresolved": errors_unresolved,
                "resolution_rate": round((errors_total - errors_unresolved) / errors_total * 100, 1) if errors_total > 0 else 0
            },
            "feedback": {
                "total": feedback_total,
                "positive": feedback_positive,
                "negative": feedback_negative,
                "neutral": feedback_total - feedback_positive - feedback_negative,
                "positive_rate": round(feedback_positive / feedback_total * 100, 1) if feedback_total > 0 else 0
            },
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Failed to get metrics summary: {e}")
        return {
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }
    finally:
        conn.close()


@router.get("/summary", response_model=MetricSummary)
async def get_summary():
    """
    메트릭 요약
    
    Returns:
        MetricSummary: 각 카테고리별 요약 통계
    """
    summary = await get_metrics_summary()
    return MetricSummary(**summary)


@router.get("", response_model=MetricsResponse)
async def get_full_metrics(
    days: int = Query(7, ge=1, le=30, description="조회할 기간 (일)")
):
    """
    전체 메트릭 조회
    
    Args:
        days: 조회할 기간 (기본 7일)
    
    Returns:
        MetricsResponse: 요약 + 최근 데이터
    """
    conn = _get_db_connection()
    
    summary = await get_metrics_summary()
    
    if not conn:
        return MetricsResponse(
            summary=MetricSummary(**summary),
            recent_decisions=[],
            recent_tasks=[],
            recent_errors=[],
            recent_feedback=[]
        )
    
    try:
        cursor = conn.cursor()
        since_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
        
        # 최근 Decisions
        cursor.execute("""
            SELECT id, session_id, decision_type, outcome, created_at
            FROM decisions
            WHERE date(created_at) >= ?
            ORDER BY created_at DESC
            LIMIT 20
        """, (since_date,))
        recent_decisions = [dict(row) for row in cursor.fetchall()]
        
        # 최근 Tasks
        cursor.execute("""
            SELECT id, title, status, task_type, created_at, completed_at
            FROM tasks
            WHERE date(created_at) >= ?
            ORDER BY created_at DESC
            LIMIT 20
        """, (since_date,))
        recent_tasks = [dict(row) for row in cursor.fetchall()]
        
        # 최근 Errors
        cursor.execute("""
            SELECT id, error_type, error_category, severity, message, resolved, created_at
            FROM errors
            WHERE date(created_at) >= ?
            ORDER BY created_at DESC
            LIMIT 20
        """, (since_date,))
        recent_errors = [dict(row) for row in cursor.fetchall()]
        
        # 최근 Feedback
        cursor.execute("""
            SELECT id, feedback_type, sentiment, content, addressed, created_at
            FROM feedback
            WHERE date(created_at) >= ?
            ORDER BY created_at DESC
            LIMIT 20
        """, (since_date,))
        recent_feedback = [dict(row) for row in cursor.fetchall()]
        
        return MetricsResponse(
            summary=MetricSummary(**summary),
            recent_decisions=recent_decisions,
            recent_tasks=recent_tasks,
            recent_errors=recent_errors,
            recent_feedback=recent_feedback
        )
        
    except Exception as e:
        logger.error(f"Failed to get full metrics: {e}")
        return MetricsResponse(
            summary=MetricSummary(**summary),
            recent_decisions=[],
            recent_tasks=[],
            recent_errors=[],
            recent_feedback=[]
        )
    finally:
        conn.close()


@router.get("/trend")
async def get_metrics_trend(
    days: int = Query(7, ge=1, le=30, description="조회할 기간 (일)")
):
    """
    메트릭 트렌드 조회 (일별)
    
    Args:
        days: 조회할 기간
    
    Returns:
        일별 메트릭 트렌드
    """
    conn = _get_db_connection()
    if not conn:
        return {"trend": [], "error": "Database not found"}
    
    try:
        cursor = conn.cursor()
        since_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
        
        # 일별 통계
        cursor.execute("""
            SELECT 
                date(created_at) as date,
                'decision' as type,
                COUNT(*) as count
            FROM decisions
            WHERE date(created_at) >= ?
            GROUP BY date(created_at)
            
            UNION ALL
            
            SELECT 
                date(created_at) as date,
                'task' as type,
                COUNT(*) as count
            FROM tasks
            WHERE date(created_at) >= ?
            GROUP BY date(created_at)
            
            UNION ALL
            
            SELECT 
                date(created_at) as date,
                'error' as type,
                COUNT(*) as count
            FROM errors
            WHERE date(created_at) >= ?
            GROUP BY date(created_at)
            
            ORDER BY date DESC, type
        """, (since_date, since_date, since_date))
        
        # 날짜별로 그룹화
        trend_data = {}
        for row in cursor.fetchall():
            date = row["date"]
            if date not in trend_data:
                trend_data[date] = {"date": date, "decisions": 0, "tasks": 0, "errors": 0}
            
            if row["type"] == "decision":
                trend_data[date]["decisions"] = row["count"]
            elif row["type"] == "task":
                trend_data[date]["tasks"] = row["count"]
            elif row["type"] == "error":
                trend_data[date]["errors"] = row["count"]
        
        return {
            "trend": list(trend_data.values()),
            "period_days": days
        }
        
    except Exception as e:
        logger.error(f"Failed to get trend: {e}")
        return {"trend": [], "error": str(e)}
    finally:
        conn.close()
