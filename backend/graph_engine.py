"""GENAPP compatibility layer for local shared graph runtime engine."""

import sys
from pathlib import Path

try:
    from shared.backend.graph_runtime.engine import (  # noqa: F401
        GraphEngine,
        GraphRuntimeError,
        GraphState,
        GraphValidationError,
    )
except ModuleNotFoundError:  # pragma: no cover - support uvicorn main:app from backend
    project_root = Path(__file__).resolve().parents[1]
    if str(project_root) not in sys.path:
        sys.path.insert(0, str(project_root))
    from shared.backend.graph_runtime.engine import (  # noqa: F401
        GraphEngine,
        GraphRuntimeError,
        GraphState,
        GraphValidationError,
    )

__all__ = [
    "GraphEngine",
    "GraphRuntimeError",
    "GraphState",
    "GraphValidationError",
]
