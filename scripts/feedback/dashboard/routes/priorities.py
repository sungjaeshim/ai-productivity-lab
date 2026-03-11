#!/usr/bin/env python3
"""
Priorities API Routes
Phase 4 Task T-015

Endpoints:
- GET /api/priorities  # 우선순위 큐
"""

import logging
from typing import Optional, List, Dict, Any

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

logger = logging.getLogger(__name__)
router = APIRouter()


class PriorityItemResponse(BaseModel):
    """우선순위 아이템 응답 모델"""
    id: str
    item_type: str
    title: str
    impact: float
    frequency: float
    effort: float
    priority_score: float
    status: str
    created_at: Optional[str]


class PriorityQueueResponse(BaseModel):
    """우선순위 큐 응답"""
    items: List[PriorityItemResponse]
    total_pending: int
    avg_score: float


def _get_priority_engine():
    """PriorityEngine 인스턴스 반환"""
    try:
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path.home() / ".openclaw" / "workspace"))
        from scripts.feedback import PriorityEngine
        return PriorityEngine()
    except ImportError as e:
        logger.warning(f"PriorityEngine not available: {e}")
        return None


async def get_priorities_internal(limit: int = 20) -> List[Dict[str, Any]]:
    """
    우선순위 큐 조회 (다른 모듈에서 사용)
    
    Args:
        limit: 최대 항목 수
    
    Returns:
        우선순위 아이템 리스트
    """
    engine = _get_priority_engine()
    
    if not engine:
        return []
    
    try:
        items = engine.get_priority_queue(limit=limit, status="pending")
        return [item.to_dict() for item in items]
    except Exception as e:
        logger.error(f"Failed to get priorities: {e}")
        return []
    finally:
        engine.close()


@router.get("", response_model=PriorityQueueResponse)
async def get_priority_queue(
    limit: int = Query(20, ge=1, le=100, description="결과 제한"),
    status: Optional[str] = Query(None, description="상태 필터 (pending, in_progress, improved, all)")
):
    """
    우선순위 큐 조회
    
    Args:
        limit: 최대 결과 수
        status: 상태 필터 (기본: pending)
    
    Returns:
        PriorityQueueResponse: 우선순위 큐
    """
    engine = _get_priority_engine()
    
    if not engine:
        return PriorityQueueResponse(
            items=[],
            total_pending=0,
            avg_score=0.0
        )
    
    try:
        # 기본적으로 pending만 조회
        filter_status = status if status else "pending"
        if filter_status == "all":
            filter_status = None
        
        items = engine.get_priority_queue(limit=limit, status=filter_status)
        
        # 통계 조회
        stats = engine.get_stats()
        
        return PriorityQueueResponse(
            items=[PriorityItemResponse(**item.to_dict()) for item in items],
            total_pending=stats.get("pending", 0),
            avg_score=round(stats.get("average_pending_score", 0), 2)
        )
        
    except Exception as e:
        logger.error(f"Failed to get priority queue: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        engine.close()


@router.get("/stats")
async def get_priority_stats():
    """
    우선순위 통계
    
    Returns:
        우선순위 통계 요약
    """
    engine = _get_priority_engine()
    
    if not engine:
        return {
            "total_items": 0,
            "pending": 0,
            "improved": 0,
            "average_pending_score": 0,
            "improvement_rate": 0
        }
    
    try:
        stats = engine.get_stats()
        return stats
        
    except Exception as e:
        logger.error(f"Failed to get priority stats: {e}")
        return {"error": str(e)}
    finally:
        engine.close()


@router.get("/report/weekly")
async def get_weekly_report():
    """
    주간 우선순위 리포트
    
    Returns:
        주간 리포트 데이터
    """
    engine = _get_priority_engine()
    
    if not engine:
        return {"error": "PriorityEngine not available"}
    
    try:
        report = engine.get_weekly_report()
        return report
        
    except Exception as e:
        logger.error(f"Failed to get weekly report: {e}")
        return {"error": str(e)}
    finally:
        engine.close()


@router.get("/velocity")
async def get_improvement_velocity(
    days: int = Query(30, ge=7, le=90, description="분석 기간 (일)")
):
    """
    개선 속도 분석 (Ralph Loop 연동)
    
    Args:
        days: 분석 기간
    
    Returns:
        개선 속도 분석 데이터
    """
    engine = _get_priority_engine()
    
    if not engine:
        return {"error": "PriorityEngine not available"}
    
    try:
        velocity = engine.get_improvement_velocity(days=days)
        return velocity
        
    except Exception as e:
        logger.error(f"Failed to get improvement velocity: {e}")
        return {"error": str(e)}
    finally:
        engine.close()


@router.get("/ralph")
async def get_ralph_loop_data():
    """
    Ralph Loop 연동용 데이터
    
    Returns:
        Ralph Loop에서 사용할 데이터
    """
    engine = _get_priority_engine()
    
    if not engine:
        return {"ready_for_ralph": False, "error": "PriorityEngine not available"}
    
    try:
        data = engine.get_ralph_loop_data()
        return data
        
    except Exception as e:
        logger.error(f"Failed to get Ralph Loop data: {e}")
        return {"ready_for_ralph": False, "error": str(e)}
    finally:
        engine.close()


@router.get("/{item_id}")
async def get_priority_item(item_id: str):
    """
    특정 우선순위 아이템 조회
    
    Args:
        item_id: 아이템 ID
    
    Returns:
        우선순위 아이템 상세
    """
    engine = _get_priority_engine()
    
    if not engine:
        raise HTTPException(status_code=503, detail="PriorityEngine not available")
    
    try:
        item = engine.get_item(item_id)
        
        if not item:
            raise HTTPException(status_code=404, detail=f"Item not found: {item_id}")
        
        return item.to_dict()
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get priority item: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        engine.close()
