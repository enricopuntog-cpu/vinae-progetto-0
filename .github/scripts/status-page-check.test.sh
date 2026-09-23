#!/usr/bin/env bash
# Negative tests for status-page-check.mjs: the real site must pass and every
# mutation that would break independence, safety or state semantics must fail.
set -euo pipefail

check=".github/scripts/status-page-check.mjs"
site="status-page/site"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0
failures=0

node "$check" "$site" >/dev/null || { echo "FAIL: sito reale rifiutato"; exit 1; }
pass=$((pass + 1))

# Each case: name, then a sed expression applied to index.html (or a shell action).
expect_reject() {
  local name="$1" action="$2" case_dir="$tmp/$1"
  cp -R "$site" "$case_dir"
  (cd "$case_dir" && eval "$action")
  if node "$check" "$case_dir" >/dev/null 2>&1; then
    echo "FAIL: $name accettato"
    failures=$((failures + 1))
  else
    pass=$((pass + 1))
  fi
}

expect_reject script        "sed -i 's|</main>|<script>x()</script></main>|' index.html"
expect_reject stylesheet    "sed -i 's|</head>|<link rel=stylesheet href=https://cdn.example/x.css></head>|' index.html"
expect_reject css-url       "sed -i 's|body {|body { background: url(https://x.example/a.png);|' index.html"
expect_reject image         "sed -i 's|</main>|<img src=/a.png></main>|' index.html"
expect_reject bad-state     "sed -i 's|data-state=\"operativo\" aria|data-state=\"down\" aria|' index.html"
expect_reject label-mismatch "sed -i 's|data-state=\"operativo\" aria|data-state=\"risolto\" aria|' index.html"
expect_reject no-timezone   "sed -i 's|2026-09-23T18:00:00+02:00|2026-09-23 18:00|' index.html"
expect_reject two-states    "sed -i 's|<h2>Aggiornamenti|<section class=\"status\" data-state=\"operativo\"><span class=\"label\">Operativo</span></section><h2>Aggiornamenti|' index.html"
expect_reject foreign-link  "sed -i 's|https://vineawineclub.com/|https://evil.example/|' index.html"
expect_reject supabase      "sed -i 's|</main>|<!-- https://abc.supabase.co --></main>|' index.html"
expect_reject jwt           "sed -i 's|</main>|<!-- eyJhbGciOiJIUzI1NiJ9 --></main>|' index.html"
expect_reject no-csp        "sed -i '/Content-Security-Policy/d' _headers"
expect_reject csp-script    "sed -i \"s|style-src 'unsafe-inline'|style-src 'unsafe-inline'; script-src 'self'|\" _headers"
expect_reject extra-file    "echo x > app.js"
expect_reject missing-404   "rm 404.html"

echo "status-page-check tests: $pass passed, $failures failed"
[ "$failures" -eq 0 ]
