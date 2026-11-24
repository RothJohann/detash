# Backend Detash

Socle backend invariant GENAPP (S004):
- FastAPI;
- endpoint `/health`;
- endpoints runtime appgen-graph (`/graphs/runtime/*`) via noyau partagé `src/shared/backend/graph_runtime`;
- endpoints OTA minimaux (`/version`, `/ota/version`, `/download/latest.apk`);
- configuration de base via variables d'environnement.

## Lancer localement

Cas template dans ce dépôt:

```bash
cd src/genapp-template/backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8100 --reload
```

Cas GENAPP générée (ex: `/mnt/c/Dev/genapps/defi-hero`):

```bash
cd /mnt/c/Dev/genapps/<slug>/backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8110 --reload
```

Bootstrap automatisé depuis APPGEN:

```bash
cd /mnt/c/Dev/appgen
./scripts/dev/bootstrap-generated-genapp.sh --target /mnt/c/Dev/genapps/<slug> --backend-port 8110
```

## Variables d'environnement

- `GENAPP_NAME` (défaut: `Detash`)
- `GENAPP_VERSION` (défaut: `0.1.0`)
- `GENAPP_DATABASE_URL` (défaut: `postgresql://localhost:5432/genapp`)
- `GENAPP_OTA_VERSION_FILE` (optionnel, défaut `backend/version.json`)
- `GENAPP_OTA_RELEASES_DIR` (optionnel, défaut `backend/releases`)
