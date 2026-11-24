"""Shared appgen-graph runtime for APPGEN and GENAPP backends."""

from .engine import (
    GraphEngine,
    GraphRuntimeError,
    GraphState,
    GraphValidationError,
)

try:  # pragma: no cover - optional when fastapi is not installed in local env
    from .api import create_runtime_router, router
except ModuleNotFoundError:  # pragma: no cover
    create_runtime_router = None
    router = None

__all__ = [
    "create_runtime_router",
    "router",
    "GraphEngine",
    "GraphRuntimeError",
    "GraphState",
    "GraphValidationError",
]
