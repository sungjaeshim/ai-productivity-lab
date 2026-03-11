#!/usr/bin/env python3
"""
WebSocket Handler for Real-time Updates
Phase 4 Task T-015

Manages WebSocket connections and broadcasts updates.
"""

import asyncio
import json
import logging
from datetime import datetime
from typing import Set, Dict, Any, Optional
from fastapi import WebSocket

logger = logging.getLogger(__name__)


class WebSocketManager:
    """
    WebSocket 연결 관리자
    
    기능:
    - 연결/해제 관리
    - 브로드캐스트
    - 구독 필터링
    """
    
    def __init__(self):
        self.active_connections: Set[WebSocket] = set()
        self.subscriptions: Dict[WebSocket, Set[str]] = {}
    
    async def connect(self, websocket: WebSocket):
        """새 WebSocket 연결 수락"""
        await websocket.accept()
        self.active_connections.add(websocket)
        self.subscriptions[websocket] = set()
        logger.info(f"WebSocket connected: {len(self.active_connections)} total")
        
        # 연결 시 초기 데이터 전송
        try:
            initial_data = await self._get_initial_data()
            await websocket.send_json({
                "type": "connected",
                "timestamp": datetime.now().isoformat(),
                "data": initial_data
            })
        except Exception as e:
            logger.error(f"Failed to send initial data: {e}")
    
    def disconnect(self, websocket: WebSocket):
        """WebSocket 연결 해제"""
        self.active_connections.discard(websocket)
        self.subscriptions.pop(websocket, None)
        logger.info(f"WebSocket disconnected: {len(self.active_connections)} total")
    
    def connection_count(self) -> int:
        """활성 연결 수 반환"""
        return len(self.active_connections)
    
    async def handle_message(self, websocket: WebSocket, data: Dict[str, Any]):
        """
        클라이언트 메시지 처리
        
        지원 메시지 타입:
        - subscribe: 특정 채널 구독
        - unsubscribe: 구독 해제
        - ping: 연결 유지
        """
        msg_type = data.get("type", "unknown")
        
        if msg_type == "subscribe":
            channels = data.get("channels", [])
            for channel in channels:
                self.subscriptions[websocket].add(channel)
            await websocket.send_json({
                "type": "subscribed",
                "channels": list(self.subscriptions[websocket])
            })
            logger.debug(f"Client subscribed to: {channels}")
        
        elif msg_type == "unsubscribe":
            channels = data.get("channels", [])
            for channel in channels:
                self.subscriptions[websocket].discard(channel)
            await websocket.send_json({
                "type": "unsubscribed",
                "channels": list(self.subscriptions[websocket])
            })
        
        elif msg_type == "ping":
            await websocket.send_json({"type": "pong", "timestamp": datetime.now().isoformat()})
    
    async def broadcast(self, message: Dict[str, Any], channel: Optional[str] = None):
        """
        모든 연결된 클라이언트에 브로드캐스트
        
        Args:
            message: 전송할 메시지
            channel: 특정 채널 구독자에게만 전송 (None이면 전체)
        """
        if not self.active_connections:
            return
        
        message["timestamp"] = datetime.now().isoformat()
        disconnected = set()
        
        for websocket in self.active_connections:
            try:
                # 채널 필터링
                if channel and channel not in self.subscriptions.get(websocket, set()):
                    continue
                
                await websocket.send_json(message)
            except Exception as e:
                logger.warning(f"Failed to send to client: {e}")
                disconnected.add(websocket)
        
        # 끊어진 연결 정리
        for ws in disconnected:
            self.disconnect(ws)
    
    async def broadcast_metrics_update(self):
        """메트릭 업데이트 브로드캐스트"""
        try:
            from .routes.metrics import get_metrics_summary
            summary = await get_metrics_summary()
            
            await self.broadcast({
                "type": "metrics_update",
                "data": summary
            }, channel="metrics")
        except Exception as e:
            logger.error(f"Failed to broadcast metrics: {e}")
    
    async def broadcast_experiment_update(self, experiment_id: str, event: str):
        """실험 상태 변경 브로드캐스트"""
        await self.broadcast({
            "type": "experiment_update",
            "experiment_id": experiment_id,
            "event": event
        }, channel="experiments")
    
    async def broadcast_priority_update(self):
        """우선순위 변경 브로드캐스트"""
        try:
            from .routes.priorities import get_priorities_internal
            priorities = await get_priorities_internal(limit=10)
            
            await self.broadcast({
                "type": "priority_update",
                "data": priorities
            }, channel="priorities")
        except Exception as e:
            logger.error(f"Failed to broadcast priorities: {e}")
    
    async def _get_initial_data(self) -> Dict[str, Any]:
        """연결 시 전송할 초기 데이터"""
        try:
            # 지연 import로 순환 참조 방지
            from .routes.metrics import get_metrics_summary
            from .routes.priorities import get_priorities_internal
            
            return {
                "metrics": await get_metrics_summary(),
                "top_priorities": await get_priorities_internal(limit=5)
            }
        except Exception as e:
            logger.error(f"Failed to get initial data: {e}")
            return {}


# 전역 인스턴스 (server.py에서 사용)
_manager: Optional[WebSocketManager] = None


def get_manager() -> WebSocketManager:
    """WebSocket 매니저 싱글톤 반환"""
    global _manager
    if _manager is None:
        _manager = WebSocketManager()
    return _manager
