# ns8-tsa — GMP operation notes

Status: draft for review. These notes help an operator run the TSA module in a
regulated (GMP / 21 CFR Part 11) context. They are **not** a conformity
statement and **not** a validation deliverable: whether this system is validated
and released is decided by the operator's quality unit on the basis of their own
URS, risk analysis and tests. See the module `README.md`
("[Security and compliance](../README.md#security-and-compliance)") for the
authoritative description of what the timestamp server does and does not record.

## 1. What this module is, in regulatory terms

- It packages the sigstore `timestamp-server` (RFC 3161 Timestamp Authority)
  under a **self-signed, long-lived** signing chain generated and held on the
  node, or an externally uploaded timestamping certificate.
- It is **not** a qualified electronic timestamp service under eIDAS and is
  **not** on any EU trusted list (README *Terms of use and eIDAS disclaimer*).
- The authoritative, tamper-evident record of a timestamp is the **RFC 3161
  token itself** — it carries the serial number, `genTime`, the message imprint
  and the policy OID, and is held by the **requesting application**. The server
  keeps **no issuance journal**; the node journal is an operational log, not an
  audit trail of issuance. Part 11 / ALCOA+ record-keeping duties for the
  timestamped records therefore lie with the requesting application.

## 2. Token profile (verified on timestamp-server v2.2.0)

Issued with the module's default unit (no policy flags overridden):

| Field | Value | Note |
|---|---|---|
| Policy OID | `1.3.6.1.4.1.57264.2` | Observed on timestamp-server v2.2.0 when the policy flags are not overridden; the module passes neither `--default-policy-oid` nor `--accepted-policy-oids` (confirmed in the unit), so the server's default applies. Confirm per the command below. |
| Hash in `messageImprint` | as requested by the client (e.g. SHA-256) | the TSA echoes the client's digest; it does not re-hash the data. |
| `genTime` | node system clock, UTC | see §3. |
| Accuracy | 1 second | Observed on v2.2.0 (`Accuracy: 0x01 seconds` in the token). Confirm per the command below. |
| Serial number | random, per token | |
| Signing certificate | included in the response (`--include-chain-in-response=true`) | the verifier still needs to trust the Root CA. |

> Verify the policy OID and accuracy on a live instance with:
> `openssl ts -reply -in response.tsr -text` → fields *Policy OID* and *Accuracy*.
> If your evidence policy requires a specific policy OID, record this value in
> the URS; changing it would require overriding the server flags and is out of
> scope here.

## 3. Time source and accuracy (ALCOA+ "accurate" / "contemporaneous")

- `genTime` is taken from the **node system clock**, disciplined by the node's
  NTP client (chrony on a Rocky node, systemd-timesyncd on Debian). Time
  accuracy is therefore a direct quality attribute of every token. It is a
  data-integrity expectation (ALCOA+ "accurate" and "contemporaneous"; PIC/S
  PI 041-1), not a specific Annex 11 clause; protecting the clock from arbitrary
  change by users is a security control in the sense of Annex 11 §12. On an NS8 node the
  system clock is managed by the platform, not by application users.
- The server also runs its own NTP monitoring at start-up (it logs
  `ntp monitoring starting`); this is an internal sanity check and is not an
  audit record.
- The **Self test** (Certificate page) reports whether the OS considers the
  clock synchronised (`timedatectl`) and the offset reported by the NTP client
  (`chronyc`), warning above a 1-second deviation. The offset is advisory (a
  node may run more than one NTP client); the OS synchronisation flag is the
  authoritative signal. Record the self-test result as evidence of clock control
  at a frequency your risk analysis defines (the test is manual; keep the
  schedule and its records outside the module).

## 4. Signing certificate: lifetimes, rotation, archive

- The generated chain is an EC P-384 two-level hierarchy:
  **Root CA ≈ 30 years (10950 days)**, **leaf/signer ≈ 25 years (9125 days)**.
  The leaf carries the critical `timeStamping` extended key usage required by
  RFC 3161. `openssl x509 -enddate -noout -in tsa-chain.pem` reads only the
  **leaf** (first certificate) end date; for the Root CA end date use the
  Certificate page or extract the last certificate (see §5).
- Tokens can be issued and verified only while the chain is valid; the self test
  warns 30 days before the leaf or Root CA expires.
- **Rotation replaces the chain.** The previous chain is archived under the
  module state at `cert-archive/<timestamp>/`. Tokens issued **before** a
  rotation stay verifiable **only against the archived chain**, and clients must
  trust the new Root CA for new tokens. Therefore:
  - treat a rotation as a planned change under change control;
  - **retain every archived chain** for at least as long as any token signed by
    it must remain verifiable (archived chains are part of the module backup —
    `state/cert-archive` in `etc/state-include.conf`);
  - ⚠️ **do not renew, replace or otherwise touch a production signing
    certificate as routine work** — any change to it is a deliberate, planned,
    controlled action by the operator.
- The Root CA private key is not needed at runtime (the server signs only with
  the leaf key); a true offline root is achieved by generating the root offline
  and uploading a leaf chain via the Certificate page.

## 5. Verifying a token (operator procedure)

To verify an RFC 3161 token (`response.tsr`) for a data file:

```bash
# 1) obtain the TSA signing chain once and confirm its ROOT CA fingerprint
#    out-of-band. The chain is leaf-first, so the Root CA is the LAST
#    certificate (the second of the module's two-certificate chain) --
#    `openssl x509` alone would read the leaf, so extract the last cert:
curl -s https://<fqdn>/api/v1/timestamp/certchain -o tsa-chain.pem
awk 'BEGIN{RS="-----END CERTIFICATE-----\n"} $0 ~ /BEGIN CERTIFICATE/ {last=$0} END{print last "-----END CERTIFICATE-----"}' tsa-chain.pem \
  | openssl x509 -noout -subject -fingerprint -sha256
#    -> compare this Root CA SHA-256 fingerprint to the value recorded out-of-band

# 2) verify the token against the data and the chain
openssl ts -verify -data mydocument.pdf -in response.tsr -CAfile tsa-chain.pem
#    -> "Verification: OK"

# 3) read what the token asserts (time, policy, serial, hash)
openssl ts -reply -in response.tsr -text
```

- Verification establishes that the data existed at `genTime` and was signed by
  this TSA; it does **not** assert eIDAS-qualified status.
- For a token issued **before a rotation**, use the matching **archived** chain
  from `cert-archive/<timestamp>/` as `-CAfile`.
- The verifying party must trust the Root CA; distribute and pin its SHA-256
  fingerprint through a controlled channel, not only via the endpoint.

## 6. Access control (current state)

- RFC 3161 is anonymous by design and, by the operator's standing decision of
  2026-10-04, the endpoint is **public without restriction** and only observed.
  No authentication is enforced in this version.
- An **optional, default-off** authentication gate (HTTP Basic Auth against
  LDAP) is being evaluated separately; it is not part of this version. If
  introduced, it would be off by default so existing public usage is unaffected
  unless an operator explicitly enables it. Document in the URS whether access
  restriction is required.

## 7. Operator checklist (suggested, adapt to your SOPs)

- [ ] URS records the intended use, the required token policy OID (if any) and
      the retention period for tokens and archived certificate chains.
- [ ] Node clock is NTP-disciplined; self test shows "synchronised" with a small
      offset; result recorded at the defined interval.
- [ ] Certificate expiry monitored (self test); rotation planned before expiry
      under change control; archived chains retained and backed up.
- [ ] Token verification procedure (§5) tested and documented; Root CA
      fingerprint distributed through a controlled channel.
- [ ] Backups of the module (which include the signing key, its password and the
      archived chains) go to a confidential destination; restore tested.
- [ ] The requesting GMP application stores and protects the tokens as the
      primary records (ALCOA+).

## 8. Open points / placeholders

- ❰ Self-test execution frequency and recording method ❱ — define in an SOP.
- ❰ Retention period for issued tokens and archived certificate chains ❱.
- ❰ Whether a specific token policy OID is required by the evidence policy ❱.
