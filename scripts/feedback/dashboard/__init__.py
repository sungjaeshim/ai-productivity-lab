"""
Feedback Dashboard Server
Phase 4 Task T-015

FastAPI-based dashboard for metrics, experiments, and priorities.
"""

# Lazy imports to avoid circular dependencies
def create_app():
    """Create FastAPI app (lazy import)"""
    from .server import create_app as _create_app
    return _create_app()

def run_server(port=18791, host="0.0.0.0"):
    """Run dashboard server (lazy import)"""
    from .server import run_server as _run_server
    return _run_server(port=port, host=host)

def WebSocketManager():
    """Get WebSocketManager class (lazy import)"""
    from .ws_handler import WebSocketManager as _WebSocketManager
    return _WebSocketManager

__all__ = ['create_app', 'run_server', 'WebSocketManager']
