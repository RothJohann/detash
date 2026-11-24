"""FastAPI endpoints for appgen-graph runtime execution.

Module partagé APPGEN/GENAPP pour éviter les divergences de contrat API.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from .engine import GraphEngine, GraphRuntimeError, GraphValidationError


def create_runtime_router(
    *,
    prefix: str = "/graphs/runtime",
    tags: list[str] | None = None,
) -> APIRouter:
    """Build a runtime router with a configurable prefix/tags.

    Le contrat HTTP reste identique pour APPGEN et les GENAPP.
    """
    effective_tags = tags if tags is not None else ["appgen-graph-runtime"]
    router = APIRouter(prefix=prefix, tags=effective_tags)

    @router.post("/validate")
    def validate_graph(payload: GraphValidateRequest) -> dict[str, Any]:
        """Validate a graph definition without starting a runtime session."""
        try:
            engine = GraphEngine(payload.graph)
        except GraphValidationError as exc:
            raise _handle_runtime_exception(exc) from exc

        return {"ok": True, "graph_id": engine.graph_id, "nodes_count": len(engine.nodes)}

    @router.post("/start")
    def start_graph(payload: GraphStartRequest) -> dict[str, Any]:
        """Start or resume a graph runtime."""
        try:
            engine = GraphEngine(payload.graph)
            state = engine.start(payload.state)
            return _runtime_payload(engine, state)
        except (GraphValidationError, GraphRuntimeError) as exc:
            raise _handle_runtime_exception(exc) from exc

    @router.post("/answer")
    def answer_graph(payload: GraphAnswerRequest) -> dict[str, Any]:
        """Submit an answer and progress to the next interactive node."""
        try:
            engine = GraphEngine(payload.graph)
            state = engine.load_state(payload.state)
            state = engine.answer(state, payload.value)
            return _runtime_payload(engine, state)
        except (GraphValidationError, GraphRuntimeError) as exc:
            raise _handle_runtime_exception(exc) from exc

    return router


class GraphValidateRequest(BaseModel):
    graph: dict[str, Any] = Field(..., description="Graph definition to validate.")


class GraphStartRequest(BaseModel):
    graph: dict[str, Any] = Field(..., description="Graph definition to execute.")
    state: dict[str, Any] | None = Field(
        default=None,
        description="Optional serialized state to resume execution.",
    )


class GraphAnswerRequest(BaseModel):
    graph: dict[str, Any] = Field(..., description="Graph definition to execute.")
    state: dict[str, Any] = Field(..., description="Serialized state to continue.")
    value: Any | None = Field(
        default=None,
        description="Answer payload for the current interactive node.",
    )


def _handle_runtime_exception(exc: Exception) -> HTTPException:
    return HTTPException(status_code=400, detail=str(exc))


def _runtime_payload(engine: GraphEngine, state: Any) -> dict[str, Any]:
    return {
        "graph_id": engine.graph_id,
        "is_finished": state.is_finished,
        "state": engine.snapshot(state),
        "current_node": engine.current_node(state),
    }


router = create_runtime_router()
