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

## Cloudflare-tokens på kontot (verifierad karta, 2026-07-27, rättad 2026-07-27 kväll)

Kontot har **4 riktiga Cloudflare Account API-tokens**, inte de "40 nycklar"
det kändes som efter en förmiddags förvirring — problemet var att samma token
hade olika namn i olika repon, och att två Workers oberoende av varandra
byggt samma funktion. Räkningen är dubbelkontrollerad direkt mot dashboardens
"Showing X of X" — lita på den räkningen, inte på en tidigare dokumenterad
lista. Se [[project-cloudflare-account-tokens-map]] för hela historien,
inklusive en femte token som visade sig vara en föräldralös kvarleva och
raderades samma kväll.

| Cloudflare-namn | Behörighet | Secret-namn | Konsument |
|---|---|---|---|
| `politiker-webapp -- deploy` | Full write (Workers/D1/KV/R2/DNS) | `CLOUDFLARE_API_TOKEN` | GitHub Actions: politiker-webapp, product-describer-cloudflare, klarsprak, politiker-kontakter (wrangler härleder kontot ur tokenet — `CLOUDFLARE_ACCOUNT_ID` krävs inte) |
| `politiker-webapp -- readonly` | D1/Workers Scripts/Access Read + Zone Read (denied.se) | `POLITIKER_WEBAPP_READONLY_TOKEN` | Worker `ops-hub` (var-5-min-hälsokontroll för politiker.denied.se) |
| `admin -- manage-tokens` | Account API Tokens Write | `CF_ADMIN_TOKEN` | Worker `cf-token-rotator` (product-describer-cloudflare/token-rotator) — **enda** konsument sedan ops-hubs egen dubblettkopia togs bort 2026-07-27. Förnyelsen (`0 3 * * *`) förlänger bara `expires_on` — värdet ändras aldrig, så inget behöver flyttas mellan platser vid en normal förnyelse |
| `politiker-webapp-healthcheck` | Workers Scripts + Access Read | `POLITIKER_WEBAPP_HEALTHCHECK_TOKEN` | Worker `politiker-webapp-healthcheck` (daglig 05:00 UTC-sammanfattning) |

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

## Årlig genomgång

När utgångsmailet kommer, gå igenom hela listan i ett svep:

1. Används den fortfarande? Leta efter den faktiska konsumenten, inte namnet.
2. Kan den ersättas av `GITHUB_TOKEN` eller appen?
3. Är omfånget fortfarande minsta möjliga?
4. Stämmer namn och beskrivning med vad den gör i dag?
5. Finns någon lokal kopia som kan tas bort?

Radera hellre än att förlänga. Behövs den igen tar det två minuter att prägla
en ny — och då vet du åtminstone varför den finns.
