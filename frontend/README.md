# Frontend Detash

Socle frontend invariant GENAPP (S004):
- Flutter (mobile first);
- navigation minimale `Accueil` / `Workflow` / `Admin`;
- exécution workflow via package partagé `appgen_graph_runtime`;
- section OTA dans `Admin` (rafraîchir version + télécharger l'APK OTA publié);
- graphe local d'exemple (`assets/graphs/genapp-template-onboarding-v0.json`).

## Lancer localement

Cas template dans ce dépôt:

```bash
cd src/genapp-template/frontend
flutter pub get
flutter run
```

Cas GENAPP générée (WSL):

```bash
cd /mnt/c/Dev/genapps/<slug>/frontend
flutter pub get
flutter run --dart-define=APPGEN_BACKEND_URL=http://<IP_PC_OU_TAILSCALE>:8110
```

Cas GENAPP générée (PowerShell):

```powershell
cd C:\Dev\genapps\<slug>\frontend
flutter pub get
flutter run --dart-define=APPGEN_BACKEND_URL=http://<IP_PC_OU_TAILSCALE>:8110
```
