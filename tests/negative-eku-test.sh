#!/bin/bash

#
# Copyright (C) 2026 tebbi
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Negative test: uploading a certificate WITHOUT the critical timeStamping EKU
# must be rejected by the upload-certificate action (RFC 3161 requires it, and
# the sigstore server refuses to start without it).
#
# Run on the node with the module instance id as argument, e.g.:
#
#     bash /path/to/negative-eku-test.sh tsa1
#
# It builds a self-signed serverAuth-only leaf and feeds it to the module's
# upload-certificate action through api-cli, expecting a validation failure.

set -u

MODULE_ID="${1:-}"
if [ -z "${MODULE_ID}" ]; then
    echo "usage: $0 <module-id>" >&2
    exit 2
fi

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
cd "${TMP}"

# A self-signed leaf with the WRONG extended key usage (serverAuth, no timeStamping).
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-384 -nodes \
    -keyout key.pem -out chain.pem -days 365 \
    -subj "/CN=not-a-tsa.example.org" \
    -addext "extendedKeyUsage=critical,serverAuth" >/dev/null 2>&1

# Build the JSON payload {chain, key, passphrase}.
python3 - "${TMP}/chain.pem" "${TMP}/key.pem" > payload.json <<'PY'
import json, sys
chain = open(sys.argv[1]).read()
key = open(sys.argv[2]).read()
print(json.dumps({"chain": chain, "key": key, "passphrase": ""}))
PY

echo "== negative EKU test against module '${MODULE_ID}' =="
set +e
out="$(api-cli run module/${MODULE_ID}/upload-certificate --data "$(cat payload.json)" 2>&1)"
rc=$?
set -e 2>/dev/null

echo "${out}" | sed 's/^/  /'
if [ "${rc}" -ne 0 ] || echo "${out}" | grep -qi "missing_timestamping_eku\|validation"; then
    echo "  PASS: upload without timeStamping EKU was rejected"
    exit 0
else
    echo "  FAIL: upload without timeStamping EKU was NOT rejected"
    exit 1
fi
