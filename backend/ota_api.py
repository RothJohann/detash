"""Endpoints OTA minimaux pour une GENAPP générée."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse

router = APIRouter(tags=["ota"])

_DEFAULT_VERSION = {
    "versionCode": 1,
    "versionName": "0.1.0",
    "apkUrl": "/download/latest.apk",
}


def _backend_dir() -> Path:
    return Path(__file__).resolve().parent


def _version_file() -> Path:
    raw = os.getenv("GENAPP_OTA_VERSION_FILE", "").strip()
    if raw:
        return Path(raw)
    return _backend_dir() / "version.json"


def _releases_dir() -> Path:
    raw = os.getenv("GENAPP_OTA_RELEASES_DIR", "").strip()
    if raw:
        return Path(raw)
    return _backend_dir() / "releases"


def _safe_filename_token(raw: str, *, fallback: str) -> str:
    token = re.sub(r"[^A-Za-z0-9._-]+", "-", str(raw or "").strip())
    token = re.sub(r"-{2,}", "-", token).strip("._-")
    return token or fallback


def _infer_genapp_slug() -> str:
    env_slug = str(os.getenv("GENAPP_SLUG", "")).strip()
    if env_slug:
        return _safe_filename_token(env_slug, fallback="genapp")

    manifest_path = _backend_dir().parent / ".genapp-template.json"
    if manifest_path.exists():
        try:
            parsed = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
            if isinstance(parsed, dict):
                manifest_slug = str(parsed.get("slug", "")).strip()
                if manifest_slug:
                    return _safe_filename_token(manifest_slug, fallback="genapp")
        except Exception:
            pass

    return _safe_filename_token(_backend_dir().parent.name, fallback="genapp")


def _load_version_payload() -> dict[str, Any]:
    version_file = _version_file()
    if not version_file.exists():
        return dict(_DEFAULT_VERSION)
    try:
        parsed = json.loads(version_file.read_text(encoding="utf-8-sig"))
    except Exception as exc:  # pragma: no cover - dépend des fichiers terrain
        raise HTTPException(
            status_code=500,
            detail=f"Fichier version OTA illisible: {version_file} ({exc})",
        ) from exc
    if not isinstance(parsed, dict):
        raise HTTPException(
            status_code=500,
            detail=f"Fichier version OTA invalide: {version_file}",
        )
    return {
        "versionCode": int(parsed.get("versionCode", _DEFAULT_VERSION["versionCode"])),
        "versionName": str(parsed.get("versionName", _DEFAULT_VERSION["versionName"])),
        "apkUrl": str(parsed.get("apkUrl", _DEFAULT_VERSION["apkUrl"])),
    }


def _apk_download_filename(version_payload: dict[str, Any]) -> str:
    slug = _infer_genapp_slug()
    version_name = _safe_filename_token(
        str(version_payload.get("versionName", _DEFAULT_VERSION["versionName"])),
        fallback=str(_DEFAULT_VERSION["versionName"]),
    )
    try:
        version_code = int(
            version_payload.get("versionCode", _DEFAULT_VERSION["versionCode"])
        )
    except (TypeError, ValueError):
        version_code = int(_DEFAULT_VERSION["versionCode"])
    return f"{slug}-v{version_name}-b{version_code}.apk"


def _absolutize_apk_url(apk_url: str, request: Request) -> str:
    if apk_url.startswith("http://") or apk_url.startswith("https://"):
        return apk_url
    base = str(request.base_url).rstrip("/")
    if apk_url.startswith("/"):
        return f"{base}{apk_url}"
    return f"{base}/{apk_url.lstrip('/')}"


@router.get("/version")
@router.get("/ota/version")
def ota_version(request: Request) -> dict[str, Any]:
    payload = _load_version_payload()
    payload["apkUrl"] = _absolutize_apk_url(str(payload["apkUrl"]), request)
    return payload


@router.api_route("/download/latest.apk", methods=["GET", "HEAD"])
def download_latest_apk() -> FileResponse:
    releases_dir = _releases_dir()
    apk_path = releases_dir / "latest.apk"
    if not apk_path.exists():
        raise HTTPException(status_code=404, detail="APK OTA introuvable.")
    version_payload = _load_version_payload()
    return FileResponse(
        apk_path,
        media_type="application/vnd.android.package-archive",
        filename=_apk_download_filename(version_payload),
    )
