#!/bin/bash

#
# Copyright (C) 2026 tebbi
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Post-deploy smoke test for the ns8-tsa module.
#
# Run it in the module user context so that podman, systemctl --user and the
# module environment are available, e.g. on the node:
#
#     runagent -m tsa1 bash /path/to/smoke-test.sh tsa.example.org
#
# Argument: the public FQDN of the TSA (for the Traefik/HTTPS end-to-end check).

set -u

FQDN="${1:-}"
PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

STATE="${HOME}/.config/state"
CHAIN="${STATE}/certs/tsa-chain.pem"
TCP_PORT="$(grep -E '^TCP_PORT=' "${STATE}/environment" 2>/dev/null | cut -d= -f2)"
TCP_PORT="${TCP_PORT:-3000}"
LOCAL="http://127.0.0.1:${TCP_PORT}"

echo "== ns8-tsa smoke test (port ${TCP_PORT}, chain ${CHAIN}) =="

# 1) container running, not restart-looping
echo "[1] container state"
state="$(podman inspect -f '{{.State.Status}}' tsa 2>/dev/null)"
restarts="$(podman inspect -f '{{.RestartCount}}' tsa 2>/dev/null)"
if [ "${state}" = "running" ]; then ok "container running"; else bad "container not running (state='${state}')"; fi
if [ "${restarts:-0}" -le 2 ] 2>/dev/null; then ok "restart count low (${restarts})"; else bad "container restart-looping (${restarts})"; fi

# 2) /ping
echo "[2] /ping"
if curl -fsS --max-time 10 "${LOCAL}/ping" >/dev/null 2>&1; then ok "/ping answered"; else bad "/ping did not answer"; fi

# 3) timestamp query -> Granted (+ verify)
echo "[3] timestamp query and verify"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
echo "ns8-tsa smoke $(date -u +%s)" > "${TMP}/data"
if openssl ts -query -data "${TMP}/data" -sha256 -cert -out "${TMP}/req.tsq" >/dev/null 2>&1; then
    ok "built RFC 3161 request"
else
    bad "openssl ts -query failed"
fi
http_code="$(curl -s -o "${TMP}/resp.tsr" -w '%{http_code}' \
    -H 'Content-Type: application/timestamp-query' \
    --data-binary "@${TMP}/req.tsq" "${LOCAL}/api/v1/timestamp")"
if [ "${http_code}" = "200" ]; then ok "timestamp endpoint HTTP 200"; else bad "timestamp endpoint HTTP ${http_code}"; fi
if openssl ts -reply -in "${TMP}/resp.tsr" -text 2>/dev/null | grep -q "Granted"; then
    ok "Status: Granted"
else
    bad "token not Granted"
fi
if openssl ts -verify -data "${TMP}/data" -in "${TMP}/resp.tsr" -CAfile "${CHAIN}" 2>/dev/null | grep -q "OK"; then
    ok "openssl ts -verify OK against local chain"
else
    bad "openssl ts -verify failed"
fi

# 4) certchain endpoint
echo "[4] certchain endpoint"
if curl -fsS --max-time 10 "${LOCAL}/api/v1/timestamp/certchain" 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
    ok "certchain endpoint returns the chain"
else
    bad "certchain endpoint did not return a certificate"
fi

# 5) Traefik / HTTPS end-to-end
echo "[5] Traefik route https://${FQDN:-<fqdn>}/api/v1/timestamp"
if [ -n "${FQDN}" ]; then
    rc="$(curl -sk -o "${TMP}/resp2.tsr" -w '%{http_code}' \
        -H 'Content-Type: application/timestamp-query' \
        --data-binary "@${TMP}/req.tsq" "https://${FQDN}/api/v1/timestamp")"
    if [ "${rc}" = "200" ] && openssl ts -reply -in "${TMP}/resp2.tsr" -text 2>/dev/null | grep -q "Granted"; then
        ok "public HTTPS endpoint issued a token"
    else
        bad "public HTTPS endpoint failed (HTTP ${rc})"
    fi
else
    echo "  SKIP: no FQDN argument given"
fi

echo "== result: ${PASS} passed, ${FAIL} failed =="
[ "${FAIL}" -eq 0 ]
