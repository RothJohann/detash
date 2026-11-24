"""FastAPI backend template for generated GENAPP projects."""

from __future__ import annotations

from fastapi import FastAPI

try:  # pragma: no cover - allows `uvicorn main:app` from backend directory
    from .config import APP_NAME, APP_VERSION, DATABASE_URL
except ImportError:  # pragma: no cover
    from config import APP_NAME, APP_VERSION, DATABASE_URL

try:  # pragma: no cover - allows `uvicorn main:app` from backend directory
    from .runtime_api import router as runtime_router
except ImportError:  # pragma: no cover
    from runtime_api import router as runtime_router
try:  # pragma: no cover - allows `uvicorn main:app` from backend directory
    from .ota_api import router as ota_router
except ImportError:  # pragma: no cover
    from ota_api import router as ota_router


app = FastAPI(
    title=f"{APP_NAME} Backend API",
    version=APP_VERSION,
    description="Backend template shared by GENAPP instances (S004).",
)


@app.get("/health")
def health() -> dict[str, str]:
    """Healthcheck endpoint."""
    return {"status": "ok"}


@app.get("/config")
def read_config() -> dict[str, str]:
    """Expose effective template config (safe, no secret values)."""
    return {
        "app_name": APP_NAME,
        "app_version": APP_VERSION,
        "database_url": DATABASE_URL,
    }


app.include_router(runtime_router)
app.include_router(ota_router)
