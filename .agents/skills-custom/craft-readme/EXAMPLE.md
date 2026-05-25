# Example README

A fully-filled README in the target style. Use this as a reference for tone, length, and section formatting.

````markdown
# Invoice Sync Service

> Serwis synchronizujący faktury z systemu ERP do hurtowni danych.

## Po co to istnieje

Dział finansów potrzebuje faktur z ERP w hurtowni do raportowania.
Serwis pobiera je cyklicznie, normalizuje i ładuje do BigQuery.
Używany przez zespół analityki i miesięczne raporty zarządcze.

## Status

🟢 Działa — produkcyjnie od 2025-Q3.

## Wymagania wstępne

- Docker + Docker Compose
- `uv` (tylko jeśli uruchamiasz poza kontenerem)
- Dostęp do VPN firmowego (połączenie z ERP)

## Szybki start

```bash
# 1. Sklonuj
git clone git@github.com:firma/invoice-sync.git && cd invoice-sync

# 2. Skonfiguruj środowisko (wartości i "skąd wziąć" są w komentarzach pliku)
cp .env.example .env
$EDITOR .env

# 3. Uruchom
docker compose up --build
```

## Weryfikacja że działa

- Health: `curl http://localhost:8000/health` → oczekiwane `{"status":"ok"}`
- Smoke test: `docker compose exec app pytest tests/smoke`
- Logi startu: `docker compose logs -f app` → szukaj `Sync scheduler started`

## Konfiguracja

Wszystkie zmienne środowiskowe + opis i „skąd wziąć wartość" → `.env.example`.
Skopiuj go do `.env` i wypełnij. Nie commituj `.env`.

## Częste komendy

```bash
docker compose exec app pytest                  # testy
docker compose exec app ruff check .            # lint
docker compose exec app pyright                 # typy
docker compose exec app bash                    # shell w kontenerze
docker compose exec app alembic upgrade head    # migracje DB
```

## Architektura

Scheduler odpytuje ERP co godzinę, normalizuje dane i ładuje do BigQuery.
Usługi (docker-compose): `app` (serwis), `db` (Postgres — stan synchronizacji).
Szczegóły → [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Troubleshooting

- **Port 8000 zajęty** → zmień mapowanie w `docker-compose.override.yml`.
- **`Missing env var ERP_API_KEY`** → uzupełnij `.env` wg `.env.example`.
- **`connection refused` do ERP** → sprawdź, czy VPN jest aktywny.
- **Migracje nieaktualne** → `docker compose exec app alembic upgrade head`.

## Kontakt / owner

Owner: zespół Data Platform — kanał Slack `#data-platform`.
Pytania i awarie → tam.

## Linki

- **Dokumentacja** — [`docs/`](docs/) · [`ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **Google Drive** — folder projektu: `https://drive.google.com/drive/folders/abc123`
- **Slack** — `#invoice-sync` (dyskusja) · `#data-platform-alerts` (incydenty)
- **Jira** — projekt INV: `https://firma.atlassian.net/jira/software/projects/INV/board`
- **Środowiska** — staging `https://invoice-sync.staging.firma.io` · prod `https://invoice-sync.firma.io`
- **Monitoring** — `https://grafana.firma.io/d/invoice-sync`
````

## How a TODO placeholder looks in-file

When the user skips a question, leave a comment exactly like this — visible in source, invisible in rendered Markdown:

```markdown
## Kontakt / owner

<!-- TODO: ustal ownera i kanał Slack -->
```

## Post-write TODO summary (printed to chat, not to file)

```
README.md zapisany. Pozostały do uzupełnienia:
  - Owner / kontakt (sekcja "Kontakt / owner")
  - Link do monitoringu (sekcja "Linki")
  - Healthcheck URL (sekcja "Weryfikacja że działa")
```
