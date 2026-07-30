# Åtkomststandard — tokens, appar, secrets och variabler

Gäller alla `blixten85/*`-repon och Cloudflare-kontot. Skriven 2026-07-27 efter
en genomgång där 74 poster i `~/.claude/credentials.env` visade sig vara 12
faktiska hemligheter, resten konfiguration eller kvarlevor från avslutade
tjänster.

Syftet är inte maximal säkerhet. Syftet är att **ingen ska behöva minnas vad
något gör** — varken människan eller agenten. Varje credential ska kunna
förklara sig själv genom sitt namn och sin beskrivning.

## Regel 1 — Inbyggd `GITHUB_TOKEN` först

Använd `${{ secrets.GITHUB_TOKEN }}` i varje workflow där det räcker. Deklarera
minsta möjliga `permissions:`-block i jobbet.

Det finns **exakt ett** legitimt skäl att välja bort den: pushar och PR:ar
gjorda med `GITHUB_TOKEN` triggar aldrig andra workflows. Behöver en
workflow-skapad PR köra required checks eller auto-merge måste något annat
användas. Alla andra skäl är bekvämlighet.

## Regel 2 — GitHub App före PAT

Behövs mer än `GITHUB_TOKEN`, använd appen **`denied.se CI`** (app-id `4403122`)
via `actions/create-github-app-token`. Den präglar en token per körning som dör
efter en timme.

```yaml
- name: Prägla apptoken
  id: app-token
  uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
  with:
    app-id: ${{ vars.CI_APP_ID }}
    private-key: ${{ secrets.CI_APP_PRIVATE_KEY }}
```

Appen installeras **bara** på de repon som faktiskt behöver den, aldrig "All
repositories". Committa som appen, inte som `github-actions[bot]` — den senare
är exakt den identitet som inte kan trigga nedströms workflows, så namnet vore
missvisande i historiken.

En PAT får bara användas när appen bevisligen inte räcker. Skriv då **varför**
i tokenens beskrivning.

## Regel 3 — Hemlighet eller variabel?

Kan värdet publiceras utan skada är det **ingen hemlighet**. Lägg det som
repository *variable*, inte secret.

| Variabel (`vars.`) | Secret (`secrets.`) |
|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | `CLOUDFLARE_API_TOKEN` |
| `D1_DATABASE_ID` | `CI_APP_PRIVATE_KEY` |
| `CI_APP_ID` | `TMDB_API_KEY` |
| Publika OAuth-klient-ID:n | OAuth-klienthemligheter |
| Mottagaradresser, sökvägar, loggnivåer | Lösenord, API-nycklar, privatnycklar |

Skälet är inte ideologiskt: en fil full av "hemligheter" som mest innehåller
konto-ID:n gör att man slutar läsa den. Signalen dränks i brus.

## Regel 4 — Namnet ska säga vad den gör

Ett credential heter det den **används till**, inte var den råkade skapas.

* Fel: `politiker-webapp -- security-alerts-sync` på en token vars workflow
  numera använder `github.token`, och som i själva verket används av en Worker
  för att skapa issues.
* Rätt: `politiker-webapp -- feedback-issues (Worker, Issues: Write)`

Cloudflare-tokens och GitHub-PAT:ar har båda ett beskrivningsfält. Fyll i det.
Ange vem som konsumerar tokenen och varför den behöver just de rättigheterna.

## Regel 5 — Minsta omfång, verifierat

Sätt bara de behörigheter som faktiskt anropas. **Verifiera efteråt** genom att
köra ett riktigt anrop — behörighetslistor är lätta att kryssa fel i, och
felmeddelandet vid saknad behörighet är ofta identiskt med det vid ogiltig
nyckel.

Fallgropar som redan kostat tid:

* Cloudflares behörighetsmeny har **`Account API Gateway Read`** direkt bredvid
  **`Account API Tokens Read`**. Fel val ger ingen varning, bara en tyst död
  automatisering.
* Cloudflares behörighetsändringar propagerar först efter **30–90 sekunder**.
  Ett test direkt efter en ändring ljuger.
* Fine-grained PAT:ar kan **inte** ges åtkomst till Checks-API:et. Det finns
  ingen kryssruta — annoteringar på check runs kräver en classic-token.

## Regel 6 — Lagra på destinationen, inte på disk

En token som är satt där den ska användas (Worker-secret, repo-secret) behöver
ingen kopia lokalt. Prägla, sätt, radera den lokala kopian.

Undantaget är credentials som en människa eller agent återanvänder
interaktivt. De hör hemma i `~/.claude/credentials.env` (`chmod 600`), och
ingen annanstans.

Konfiguration som inte är hemlig ligger i `~/.claude/config.env`.

`chmod 600` städar **inte** bakåt: kopior som redan tagits behåller sitt gamla
läge, och värdet finns kvar på disk även efter att raden raderats. En nyckel är
död först när den återkallats hos leverantören.

## Regel 7 — Utgång med påminnelse, inte automatisk förlängning

Sätt **365 dagars** utgång, synkroniserat, så den årliga genomgången blir ett
tillfälle i stället för utspridda småärenden.

Automatisk förlängning är förbjuden. En process som tyst håller nycklar vid liv
år efter år är ingen säkerhetsåtgärd — den ser till att ingen någonsin omprövar
om nyckeln fortfarande behövs.

Bevakningen sköts av:

* **Cloudflare:** Workern `cf-token-rotator` (cron `17 3 * * *`) mailar
  root@denied.se dagligen tills en människa förlängt eller raderat tokenen.
  Ingen kvittering behövs — mailet upphör när utgången ligger utanför tröskeln.
* **GitHub:** `~/.claude-admin/token-watch.py` (cron 06:30) varnar på
  30/14/7/3/1 dagar kvar. GitHub har **inget API för att förlänga en PAT** —
  det går bara i webbgränssnittet.

## Regel 8 — Inget IP-filter på tokens som används från molnet

Cloudflare Workers och GitHub Actions har inga stabila utgående IP-adresser.
Ett IP-filter där ger `Authentication error`, identiskt med felet vid ogiltig
token, och timmar av felsökning åt fel håll.

Filtret är befogat först när en token bara används från en fast adress.

## Regel 9 — Inget "utifall att"

Lägg inte till en behörighet för något som kanske behövs. Kontrollera först om
funktionen ens är påslagen.

Exempel: `Code quality` såg ut att höra hemma i säkerhetssvepet, men API:et
svarar `404` på samtliga repon — funktionen är inte aktiverad. Behörigheten
hade gett åtkomst till ingenting och blivit ännu en post ingen minns syftet
med.

## Cloudflare-tokens på kontot (uppdaterad karta, 2026-07-30)

Kontot har **5 riktiga Cloudflare Account API-tokens** efter dagens ändring
(tidigare 4, se historik nedan). Full genomgång av alla 12 Workers gjord via
`workers_list` + `wrangler secret list` per Worker, och alla 15
`blixten85/*`-repons Actions secrets/vars via `gh secret list`/`gh variable list`.

| Cloudflare-namn | Behörighet | Secret-namn | Konsument | +1/−1 vs gruppen |
|---|---|---|---|---|
| `politiker-webapp -- deploy` | Full write (Workers Scripts, Workers Routes, D1, KV, R2, Queues, DNS, Cache Purge) | `CLOUDFLARE_API_TOKEN` | GitHub Actions **deploy**-jobb i tre repon, delad grupp: `politiker-webapp` (4 Workers: app/campaign/sender/healthcheck — routes+D1+KV+R2+Queues), `product-describer-cloudflare` (3 Workers: app/engine/processor — samma behovsprofil), `klarsprak` (1 Worker — bara D1, ingen route/KV/R2/Queues) | `klarsprak` är **−1**: behöver bara Workers Scripts:Edit + D1:Edit, inget annat. Delar ändå tokenet för enkelhetens skull (litet konto, en ägare) |
| `politiker-webapp -- readonly` | D1 Read, Workers Scripts Read, Access Read, Zone Read (denied.se) | `POLITIKER_WEBAPP_READONLY_TOKEN` (Worker `ops-hub`) / `CLOUDFLARE_API_TOKEN_POLITIKER` (GitHub Actions-secret, repo `politiker-kontakter`) | **Två konsumenter, samma tokenvärde**: Worker `ops-hub` (var-5-min-hälsokontroll) OCH `export-politiker.yml`→`export_d1.py` (läser bara `politicians`-tabellen, skriver aldrig) | `export_d1.py` är **−1**: behöver bara D1 Read, inte Workers Scripts/Access/Zone Read. Delar ändå för enkelhetens skull |
| `admin -- manage-tokens` | Account API Tokens Write | `CF_ADMIN_TOKEN` | Worker `cf-token-rotator` (product-describer-cloudflare/token-rotator) — **enda** konsument. Förnyelsen (`0 3 * * *`) förlänger bara `expires_on` — värdet ändras aldrig |
| `politiker-webapp-healthcheck` | Workers Scripts Read + Access Read | `POLITIKER_WEBAPP_HEALTHCHECK_TOKEN` | Worker `politiker-webapp-healthcheck` (daglig 05:00 UTC-sammanfattning) — enda konsument |
| **NYTT 2026-07-30:** `politiker-webapp -- d1-write` | D1 Write (kontobrett, ingen databas-specifik scoping finns i Cloudflares behörighetsmodell) | `CLOUDFLARE_API_TOKEN_POLITIKER` — **endast lokalt** i `~/.claude/credentials.env` på mp100, ALDRIG i GitHub Actions | `politiker-webapp/infra/bounce-processor.py` (systemd-timer, markerar döda adresser) + hela `politiker-kontakter/scraper`+`verify`-pipelinen som delar `scraper/d1.py` (`sync_to_d1.py`, `verify_emails.py`, `backfill_riksdagen_role.py`, `backfill_kommun_role_party.py`, `sync_party_from_val.py`, `fetch_riksdagen_members.py`, `fetch_eu_meps.py`) — alla skriver till samma D1-databas (`politiker_webapp`) och letade redan efter exakt detta env-namn (fallback till det gamla breda `CLOUDFLARE_API_TOKEN` innan detta skapades) |

**⚠️ Namnkollision att hålla koll på:** miljövariabeln `CLOUDFLARE_API_TOKEN_POLITIKER`
pekar på **två olika faktiska tokens** beroende på var den läses:
- Lokalt (`~/.claude/credentials.env`, mp100-cron/systemd) → **d1-write**-tokenet ovan.
- I GitHub Actions (`politiker-kontakter`-repots secret) → **readonly**-tokenet.

Detta fungerar (rätt behörighet på rätt plats) men är en fälla för framtida
läsning — samma namn, olika värde, olika kontext. Om `d1.py`-konsumenter någon
gång flyttas in i CI måste secreten sättas om till d1-write-värdet där, annars
misslyckas skrivningarna tyst med `code 7500`.

**Historik:** Fram till 2026-07-27 fanns bara 4 tokens (`politiker-kontakter`
delade det fulla deploy-tokenet för sin `export-politiker.yml`, trots att den
jobbet bara läser). Bytt 2026-07-30 till `politiker-webapp -- readonly`
(redan existerande, rätt scope) för det jobbet, och ett nytt snävt
`d1-write`-token skapades för de skript som faktiskt behöver skriva
(`bounce-processor.py` hade dessförinnan varit trasig sedan 2026-07-27 pga
saknad `GMAIL_EMAIL`/`GMAIL_PASSWORD` och sedan saknad `CLOUDFLARE_API_TOKEN_POLITIKER`
— båda lösta samma dag).

**`mp100-server`-token gick inte att verifiera** — en tidigare karta påstod
att ett femte token med DNS/Tunnel/Access-behörighet fanns för mp100:s
cloudflared-tunnel. Sökning på "mp100" i Account API Tokens gav **inga
träffar**, och mp100 saknar helt `cloudflared` (ingen binär, ingen
systemd-tjänst, ingen config) — tunneln existerar sannolikt inte längre, om
den någonsin gjorde. Ta bort denna rad helt om ingen motbevisar det inom en
rimlig tid.

**`crowdsec-decisions-sync-worker`s `CF_API_TOKEN`** är ett medvetet undantag
från Regel 4: namnet är hårdkodat i CrowdSecs egen officiella prebyggda bundle
(`crowdsecurity/cs-cloudflare-worker-bouncer`, vendored binär i
`cs-cloudflare-worker-bouncer-install`). Ett namnbyte skulle brytas vid varje
uppdatering från uppströms — lämnas orört.

**`politiker-webapp-app`s `CF_ANALYTICS_TOKEN` + `CF_ACCOUNT_ID`** var döda
(Regel 9 i praktiken): funktionen som skapade dem 2026-06-27 (Cloudflare
GraphQL Analytics för besöksstatistik) skrevs senare om till en egen
D1-baserad lösning (`visits`-tabellen) utan att någon tog bort secreten.
Borttagna 2026-07-27. Det bakomliggande CF-tokenet kan fortfarande finnas
kvar i dashboarden som en föräldralös post — kolla API Tokens-listan efter
något som inte matchar tabellen ovan och radera det där.

## GitHub-appar och PAT:ar på kontot (kartlagd 2026-07-30)

Genomgång av alla 15 `blixten85/*`-repons Actions secrets/vars, `politiker-webapp`s
Worker-secrets (`GITHUB_FEEDBACK_TOKEN`) och `ops-hub`s Worker-secret (`GITHUB_TOKEN`).

| Namn | Typ | Behörighet | Konsument | +1/−1 vs gruppen |
|---|---|---|---|---|
| `denied.se CI` | GitHub App (app-id `4403122`, `CI_APP_PRIVATE_KEY`) | Contents: Write, Pull requests: Write (installerad per-repo, inte org-brett) | `politiker-kontakter` + `filtered-movies` — workflower som öppnar PR:er och behöver required checks/auto-merge trigga (se Regel 2) | Samma installation, samma behov i båda repona — ingen delta |
| `ops-hub -- automerge` | PAT (klassisk eller fine-grained, org-scope) | Pull requests: Write, Contents: Read — **org-brett**, alla `blixten85/*`-repon | Worker `ops-hub` (armar GitHub-native auto-merge på PR:er över hela orgen) | **+1 vs App-modellen**: kan inte vara en per-repo-installerad App eftersom den medvetet är org-bred (se `AUTOMERGE_PR_ACTIONS`/`env.GITHUB_ORG`-kontrollen i koden) — enda motiverade undantaget från Regel 2:s "aldrig 'All repositories'" |
| `politiker-webapp -- feedback-issues` | PAT (fine-grained, ett repo) | Issues: Write på `blixten85/politiker-webapp` | Worker `politiker-webapp-app` + `politiker-webapp-campaign` (delar samma secret `GITHUB_FEEDBACK_TOKEN`, samma syfte: skapar issues från användarfeedback) | Ingen delta — identiskt behov i båda Workers |
| `GITHUB_TOKEN`/`GITHUB_TOKEN_CLASSIC` (lokalt, `~/.claude/credentials.env`) | PAT | Bred (används av lokal `gh`-CLI-autentisering på mp100, inte av något repo/Worker) | Interaktiv `gh`-användning i terminalen | Utanför scope för denna genomgång (ingen CI/Worker-konsument) — se [[project-token-expiry-watch]] för utgångsdatum |

**`GH_PAT`-secreten är redan borta överallt.** Ingen workflow refererar
längre till `secrets.GH_PAT` — alla PR-skapande workflower migrerade till
`create-github-app-token` (senast `politiker-kontakter/export-politiker.yml`,
2026-07-30) — och verifierat med `gh secret list` över alla 15 repon att ingen
har en kvarglömd `GH_PAT`-rad.

## Årlig genomgång

När utgångsmailet kommer, gå igenom hela listan i ett svep:

1. Används den fortfarande? Leta efter den faktiska konsumenten, inte namnet.
2. Kan den ersättas av `GITHUB_TOKEN` eller appen?
3. Är omfånget fortfarande minsta möjliga?
4. Stämmer namn och beskrivning med vad den gör i dag?
5. Finns någon lokal kopia som kan tas bort?

Radera hellre än att förlänga. Behövs den igen tar det två minuter att prägla
en ny — och då vet du åtminstone varför den finns.

## Kända undantag utan kodifierad konfiguration

`crowdsec-cloudflare-worker-bouncer` och `crowdsec-decisions-sync-worker` har
Logs+Traces påslagna som **manuella dashboard-toggles**, inte i en
`wrangler.jsonc` — installer-appen som deployade dem
(`cs-cloudflare-worker-bouncer-install`) är arkiverad (2026-07-26, publikt
exponerad tokeninmatning). Ingen kod sätter observability vid en eventuell
framtida ominstallation. Kolla vid varje årlig genomgång att Logs+Traces
fortfarande är påslagna på båda — annars måste det göras för hand igen.
