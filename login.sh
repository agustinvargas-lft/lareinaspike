#!/usr/bin/env bash
# Logs into La Reina Online and saves the session to $OUT/state.json.
# Usage: LR_USER=... LR_PASS=... ./login.sh
set -euo pipefail
: "${LR_USER:?LR_USER is required}" "${LR_PASS:?LR_PASS is required}"
# agent-browser resolves relative paths from its daemon's cwd, so OUT must be absolute.
OUT="${OUT:-/vercel/out}"

ab() { agent-browser --session lr "$@"; }
mkdir -p "$OUT"

ab open https://www.lareinaonline.com.ar/IniciarSesion.asp >/dev/null

# Safety net: the spike must NEVER place a real order. Abort any request whose URL
# looks like an order confirmation. Patterns are case-sensitive, hence the variants.
# This blacklist is only a backstop: the site uses names like TicketVal/Revision/Resumen,
# so guard.js (allowlist) is what actually protects the checkout.
# ProcesandoPedido.asp is the real order-creation endpoint (form fPedido, POST),
# discovered in run 2; none of the guessed patterns matched it.
for p in '*ProcesandoPedido*' '*onfirm*' '*ONFIRM*' '*inaliz*' '*INALIZ*' '*errarPedido*' \
         '*erminarPedido*' '*nviarPedido*' '*rabarPedido*' '*ealizarPedido*' '*agar*' '*AGAR*'; do
  ab network route "$p" --abort >/dev/null
done

ab fill '#Alias' "$LR_USER" >/dev/null
ab fill '#Clave' "$LR_PASS" >/dev/null
ab click '#formlogin input.bottomIS'
sleep 4

# After login the site lands on login.asp with a RetiroOEnvio.asp modal (delivery method).
ab get url
ab screenshot "$OUT/01-login.png" >/dev/null
ab state save "$OUT/state.json" >/dev/null
