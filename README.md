# repo-standard

Guldstandard-mallrepo för alla blixten85-repon. Innehåller alla filer,
workflows och konfigurationsmallar som varje repo ska ha. Kopiera det som
behövs till ett nytt repo istället för att bygga från grunden varje gång.

## Innehåll

| Fil/mapp | Syfte |
|---|---|
| `LICENSE` | MIT |
| `SECURITY.md` | Standard säkerhetspolicy |
| `AGENTS.md` / `CLAUDE.md` | AI-agent-instruktioner — **fyll i platshållarna** (`<repo-name>`, konventioner) innan användning |
| `.coderabbit.yaml` | Aktiverar CodeRabbits auto-review |
| `.github/renovate.json` | Dependency-uppdateringar. **`schedule`-fältet MÅSTE sättas till ett unikt tidsfönster** — se "CodeRabbit rate-limit & schemaläggning" nedan |
| `.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/*` | Standardmallar |
| `.github/labeler.yml`, `.github/FUNDING.yml` | Auto-labeling, sponsorlänkar |
| `.github/workflows/*.yml` | 10 standard-workflows (se nedan) |
| `branch-ruleset-template.json` + `apply-ruleset.sh` | Branch-skydd för `main` |

## Standard-workflows (`.github/workflows/`)

- `auto-commit.yml`, `auto-label.yml`, `auto-merge.yml`, `auto-rebase.yml`,
  `auto-release.yml`, `ci-autofix.yml`, `security-alerts-sync.yml` — kärnautomation
- `codeql.yml` — CodeQL-analys (gratis för publika repon; överväg om repot
  har injektionskänsliga ytor)
- `coderabbit-rewake.yml` — triggar om CodeRabbit-granskning på PR:er som
  fastnat pga rate limit (CodeRabbit är en required status check, så en
  missad granskning blockerar merge permanent annars)
- `claude-assign-trigger.yml` — `ask-claude`-label-baserad Claude-trigger
  (körs på `pull_request_target`, säkert eftersom den aldrig checkar ut/kör
  fork-kod — bara postar en fast kommentarsträng)

Utöver dessa: lägg till projektspecifika CI-workflows (bygg/test) och
referera deras jobbnamn i `required_status_checks` när du applicerar
branch-rulesetet.

## CodeRabbit rate-limit & schemaläggning

CodeRabbits granskningskvot är **5 granskningar/timme, kontogemensamt för
hela blixten85-organisationen** (Pro-plan) — inte per repo, inte
konfigurerbar via API (bekräftat 2026-07-11, se
[docs.coderabbit.ai/reference/configuration](https://docs.coderabbit.ai/reference/configuration)).
Flera repons Renovate-scheman som fyrar samtidigt kan därför lätt
överskrida kvoten, vilket lämnar PR:er permanent blockerade (CodeRabbit är
en required status check som aldrig återupptas av sig själv).

**Lösning:** varje repos `renovate.json`-`schedule` MÅSTE vara ett smalt
(≤30 min) tidsfönster som inte krockar med något annat repos fönster.
Nuvarande utrullning (2026-07-11, alla inom 22:00–08:00 svensk tid för att
inte krocka med aktiva arbetstimmar 08:00–22:00):

| Repo | Fönster |
|---|---|
| bastion | var dag 23:00–23:30 |
| scraper | var dag 01:00–01:30 |
| pastebinit | söndag 22:00–22:30 |
| routines-relay | måndag 00:00–00:30 |
| product-describer | tisdag 03:00–03:30 |
| plex_clear_watchlist | onsdag 04:00–04:30 |
| docker-idempotent-update | torsdag 05:00–05:30 |
| filtered-movies | fredag 06:00–06:30 |
| politiker-kontakter | lördag 02:00–02:30 |
| product-describer-cloudflare | lördag 07:00–07:30 |
| politiker-webapp | söndag 05:00–05:30 |

**Nytt repo:** välj ett ledigt fönster (minst 1 timmes marginal till
närmaste granne) och uppdatera tabellen ovan i denna README när du lägger
till repot.

## Snabbstart för ett nytt repo

1. Kopiera alla filer från detta repo till det nya (utom denna README och
   `branch-ruleset-template.json`/`apply-ruleset.sh` om du inte vill ha
   dem kvar i målrepot).
2. Fyll i platshållarna i `AGENTS.md`/`CLAUDE.md`.
3. Sätt ett unikt `schedule`-fönster i `.github/renovate.json` (se tabellen
   ovan) — uppdatera BÅDE toppnivå-`schedule` och `lockFileMaintenance.schedule`.
4. Kör `./apply-ruleset.sh <repo-namn>` själv (inte via agent — branch-
   protection-ändringar är avsiktligt blockerade för agenter här).
5. Lägg till repo-specifika CI-jobbnamn i det applicerade rulesetets
   `required_status_checks` manuellt via `gh api --method PUT
   repos/blixten85/<repo>/rulesets/<id>`.
6. Installera CodeRabbit GitHub App på repot om det inte redan är
   org-brett installerat.
