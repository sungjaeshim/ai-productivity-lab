#!/usr/bin/env python3
"""
Experiments API Routes
Phase 4 Task T-015

Endpoints:
- GET /api/experiments      # 실험 목록
- GET /api/experiments/:id  # 특정 실험
"""

import logging
from typing import Optional, List, Dict, Any

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

logger = logging.getLogger(__name__)
router = APIRouter()


class ExperimentResponse(BaseModel):
    """실험 응답 모델"""
    id: str
    name: str
    hypothesis: Optional[str]
    status: str
    start_date: Optional[str]
    end_date: Optional[str]
    winner: Optional[str]
    confidence: Optional[float]
    created_at: Optional[str]


class ExperimentListResponse(BaseModel):
    """실험 목록 응답"""
    experiments: List[ExperimentResponse]
    total: int
    running: int
    completed: int


def _get_experiment_manager():
    """ExperimentManager 인스턴스 반환"""
    try:
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path.home() / ".openclaw" / "workspace"))
        from scripts.feedback.ab_testing import ExperimentManager
        return ExperimentManager()
    except ImportError as e:
        logger.warning(f"ExperimentManager not available: {e}")
        return None


@router.get("", response_model=ExperimentListResponse)
async def list_experiments(
    status: Optional[str] = Query(None, description="상태 필터 (running, paused, completed, cancelled)"),
    limit: int = Query(50, ge=1, le=200, description="결과 제한")
):
    """
    실험 목록 조회
    
    Args:
        status: 상태 필터 (선택)
        limit: 최대 결과 수
    
    Returns:
        ExperimentListResponse: 실험 목록
    """
    manager = _get_experiment_manager()
    
    if not manager:
        return ExperimentListResponse(
            experiments=[],
            total=0,
            running=0,
            completed=0
        )
    
    try:
        experiments = manager.list_experiments(status=status, limit=limit)
        
        # 상태별 카운트
        all_experiments = manager.list_experiments(limit=1000)
        running_count = sum(1 for e in all_experiments if e.get("status") == "running")
        completed_count = sum(1 for e in all_experiments if e.get("status") == "completed")
        
        return ExperimentListResponse(
            experiments=[ExperimentResponse(**exp) for exp in experiments],
            total=len(all_experiments),
            running=running_count,
            completed=completed_count
        )
        
    except Exception as e:
        logger.error(f"Failed to list experiments: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{experiment_id}", response_model=Dict[str, Any])
async def get_experiment(experiment_id: str):
    """
    특정 실험 상세 조회
    
    Args:
        experiment_id: 실험 ID
    
    Returns:
        실험 상세 정보
    """
    manager = _get_experiment_manager()
    
    if not manager:
        raise HTTPException(status_code=503, detail="ExperimentManager not available")
    
    try:
        experiment = manager.get_experiment(experiment_id)
        
        if not experiment:
            raise HTTPException(status_code=404, detail=f"Experiment not found: {experiment_id}")
        
        return experiment
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get experiment: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{experiment_id}/results")
async def get_experiment_results(experiment_id: str):
    """
    실험 결과 조회
    
    Args:
        experiment_id: 실험 ID
    
    Returns:
        실험 결과 데이터
    """
    manager = _get_experiment_manager()
    
    if not manager:
        raise HTTPException(status_code=503, detail="ExperimentManager not available")
    
    try:
        experiment = manager.get_experiment(experiment_id)
        
        if not experiment:
            raise HTTPException(status_code=404, detail=f"Experiment not found: {experiment_id}")
        
        # 결과 집계 (ResultAggregator 사용)
        try:
            from scripts.feedback.ab_testing import ResultAggregator
            
            aggregator = ResultAggregator()
            # 실제 결과 집계 로직은 ResultAggregator 구현에 따름
            results = {
                "experiment_id": experiment_id,
                "status": experiment.get("status"),
                "winner": experiment.get("winner"),
                "confidence": experiment.get("confidence"),
                "control": experiment.get("control", {}),
                "treatment": experiment.get("treatment", {})
            }
            
        except ImportError:
            results = {
                "experiment_id": experiment_id,
                "status": experiment.get("status"),
                "winner": experiment.get("winner"),
                "confidence": experiment.get("confidence")
            }
        
        return results
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get experiment results: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/stats/summary")
async def get_experiments_summary():
    """
    실험 요약 통계
    
    Returns:
        실험 통계 요약
    """
    manager = _get_experiment_manager()
    
    if not manager:
        return {
            "total": 0,
            "running": 0,
            "completed": 0,
            "success_rate": 0
        }
    
    try:
        all_experiments = manager.list_experiments(limit=1000)
        
        total = len(all_experiments)
        running = sum(1 for e in all_experiments if e.get("status") == "running")
        paused = sum(1 for e in all_experiments if e.get("status") == "paused")
        completed = sum(1 for e in all_experiments if e.get("status") == "completed")
        cancelled = sum(1 for e in all_experiments if e.get("status") == "cancelled")
        
        # 성공률 (treatment가 승리한 비율)
        treatment_wins = sum(
            1 for e in all_experiments 
            if e.get("status") == "completed" and e.get("winner") == "treatment"
        )
        success_rate = round(treatment_wins / completed * 100, 1) if completed > 0 else 0
        
        return {
            "total": total,
            "running": running,
            "paused": paused,
            "completed": completed,
            "cancelled": cancelled,
            "treatment_wins": treatment_wins,
            "success_rate": success_rate
        }
        
    except Exception as e:
        logger.error(f"Failed to get experiments summary: {e}")
        return {"error": str(e)}
