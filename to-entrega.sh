#!/usr/bin/env bash
# Jumps straight to checkout step 2 ("Confirmá la entrega") with the cart already
# stored server-side, then locks the page down with guard.js.
# Usage: ./to-entrega.sh [crit]   crit: 1 = Reemplazar, 3 = No reemplazar (default)
set -euo pipefail
OUT="${OUT:-/vercel/out}"
CRIT="${1:-3}"
DIR="$(cd "$(dirname "$0")" && pwd)"

ab() { agent-browser --session lr "$@"; }

# Navigations are blocked between steps; lift the block only to open the step itself.
ab network unroute '*' >/dev/null 2>&1 || true
ab open "https://www.lareinaonline.com.ar/Revision.asp?TM=Pedido&Crit=$CRIT" >/dev/null
# The step body is loaded by XHR after the page shell; wait for it before reading or capturing.
ab wait --text 'Resumen' >/dev/null
ab network route '*' --abort --resource-type document >/dev/null

ab eval "window.__allow = []; 'ok'" >/dev/null
ab eval -b "$(base64 < "$DIR/guard.js" | tr -d '\n')" >/dev/null

ab get url
ab screenshot "$OUT/03-entrega.png" >/dev/null
ab eval "document.body.innerText.match(/Productos[\\s\\S]{0,120}Total[^\\n]*\\n?[^\\n]*/)?.[0]"
