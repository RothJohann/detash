"""Runtime configuration for GENAPP backend template."""

from __future__ import annotations

import os


APP_NAME = os.getenv("GENAPP_NAME", "Detash")
APP_VERSION = os.getenv("GENAPP_VERSION", "0.1.0")
DATABASE_URL = os.getenv("GENAPP_DATABASE_URL", "postgresql://localhost:5432/genapp")
