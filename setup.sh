#!/usr/bin/env bash
# Prepares a Vercel Sandbox (vercel/sandbox/universal image, Ubuntu 26.04) to run agent-browser.
set -euo pipefail

sudo npm install -g agent-browser
# Downloads Chrome for Testing and the Linux libraries it needs.
agent-browser install --with-deps
