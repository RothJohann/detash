"""GENAPP runtime API endpoints based on local shared appgen-graph core."""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from shared.backend.graph_runtime.api import create_runtime_router
except ModuleNotFoundError:  # pragma: no cover - support uvicorn main:app from backend
    project_root = Path(__file__).resolve().parents[1]
    if str(project_root) not in sys.path:
        sys.path.insert(0, str(project_root))
    from shared.backend.graph_runtime.api import create_runtime_router


router = create_runtime_router(prefix="/graphs/runtime", tags=["genapp-graph-runtime"])
