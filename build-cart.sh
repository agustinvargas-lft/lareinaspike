#!/usr/bin/env bash
# Picks the pickup branch and fills the cart. Cart and branch live in the ASP session
# cookie, NOT in the account: they must be rebuilt in every new browser session.
# Usage: ./build-cart.sh <branch-address-text> <EAN>[xQTY] ...
#   ./build-cart.sh 'Oroño y Saavedra' 7790895000782 7790895005794x8
set -euo pipefail
OUT="${OUT:-/vercel/out}"
BRANCH="$1"; shift

ab() { agent-browser --session lr "$@"; }

ab open https://www.lareinaonline.com.ar/RetiroOEnvio.asp >/dev/null
ab find text 'Retiro por Sucursal' click >/dev/null
sleep 1
ab find text "$BRANCH" click >/dev/null
sleep 1
ab find role button click --name 'Aplicar' >/dev/null
sleep 2

# PCompra(EAN) is the site's own "Agregar" handler; it only exists on product listings.
ab open https://www.lareinaonline.com.ar/productosnl.asp >/dev/null
sleep 2
for item in "$@"; do
  ean="${item%%x*}"; qty=1
  [[ "$item" == *x* ]] && qty="${item##*x}"
  for _ in $(seq "$qty"); do
    ab eval "PCompra('$ean'); 'ok'" >/dev/null
    sleep 2  # be gentle: each add triggers ~8 requests
  done
done

# The site reloads the page after cart changes; reopen to read a settled total.
ab open https://www.lareinaonline.com.ar/productosnl.asp >/dev/null
sleep 2
ab screenshot "$OUT/02-carrito.png" >/dev/null
ab eval "JSON.stringify({sucursal: document.body.innerText.match(/Suc [^\\n]+/)?.[0], total: document.body.innerText.match(/Total\\s*\\n?[^\\n]*/)?.[0], productos: document.body.innerText.match(/[0-9]+\\s*Productos/)?.[0]})"
