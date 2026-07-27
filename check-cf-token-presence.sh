#!/usr/bin/env bash
# Närvaro-kontroll för kontots Cloudflare-tokens, till den årliga genomgången
# i ACCESS-STANDARD.md. Kollar ENDAST att rätt secret-NAMN finns på rätt
# plats — värden går aldrig att läsa tillbaka (secrets är skriv-bara), så
# detta kan inte bekräfta att värdet stämmer, bara att platsen inte tappats.
#
# Förutsätter: `gh` inloggad, `wrangler` inloggad (OAuth räcker, samma som
# interaktiv användning). Uppdatera TOKENS-arrayen om en token döps om,
# flyttas eller en ny konsument tillkommer — den här filen är inte
# källan-till-sanning (det är ACCESS-STANDARD.md), bara en kontroll mot den.
set -euo pipefail

# format: "beskrivning|typ(gh/wrangler)|plats|secret-namn"
TOKENS=(
  "politiker-webapp -- deploy|gh|blixten85/politiker-webapp|CLOUDFLARE_API_TOKEN"
  "politiker-webapp -- deploy|gh|blixten85/product-describer-cloudflare|CLOUDFLARE_API_TOKEN"
  "politiker-webapp -- deploy|gh|blixten85/klarsprak|CLOUDFLARE_API_TOKEN"
  "politiker-webapp -- deploy|gh|blixten85/politiker-kontakter|CLOUDFLARE_API_TOKEN"
  "politiker-webapp -- readonly|wrangler|ops-hub|POLITIKER_WEBAPP_READONLY_TOKEN"
  "admin -- manage-tokens|wrangler|cf-token-rotator|CF_ADMIN_TOKEN"
  "politiker-webapp-healthcheck|wrangler|politiker-webapp-healthcheck|POLITIKER_WEBAPP_HEALTHCHECK_TOKEN"
)

fail=0
printf "%-28s %-10s %-32s %-32s %s\n" "TOKEN" "TYP" "PLATS" "SECRET" "STATUS"

for row in "${TOKENS[@]}"; do
  IFS='|' read -r desc kind place secret <<< "$row"
  if [ "$kind" = "gh" ]; then
    if gh secret list --repo "$place" 2>/dev/null | awk '{print $1}' | grep -qx "$secret"; then
      status="OK"
    else
      status="SAKNAS"
      fail=1
    fi
  else
    if npx wrangler secret list --name "$place" 2>/dev/null | grep -q "\"name\": \"$secret\""; then
      status="OK"
    else
      status="SAKNAS"
      fail=1
    fi
  fi
  printf "%-28s %-10s %-32s %-32s %s\n" "$desc" "$kind" "$place" "$secret" "$status"
done

if [ "$fail" -eq 1 ]; then
  echo
  echo "En eller flera secrets saknas på förväntad plats — se ACCESS-STANDARD.md" >&2
  exit 1
fi

echo
echo "Alla secrets finns på förväntad plats. Kom ihåg: detta bekräftar" \
     "NÄRVARO, inte att värdet är korrekt eller matchar rätt Cloudflare-token."
