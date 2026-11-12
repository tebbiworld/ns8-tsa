# ns8-tsa — GMP operation notes

Status: draft for review. These notes help an operator run the TSA module in a
regulated (GMP / 21 CFR Part 11) context. They are **not** a conformity
statement and **not** a validation deliverable: whether this system is validated
and released is decided by the operator's quality unit on the basis of their own
URS, risk analysis and tests. See the module `README.md`
("[Security and compliance](../README.md#security-and-compliance)") for the
authoritative description of what the timestamp server does and does not record.

## 1. What this module is, in regulatory terms

- It packages the sigstore `timestamp-server` as an **RFC 3161 Timestamp
  Authority** under a **self-signed, long-lived** signing chain generated and
  held on the node (or an externally uploaded timestamping certificate).
- It is **not** a qualified electronic timestamp service under eIDAS and is
  **not** on any EU trusted list (see the README *Terms of use and eIDAS
  disclaimer*). It is a self-run authority for the operator's own evidentiary
  needs.
- The authoritative, tamper-evident record of an issued timestamp is the
  **RFC 3161 token itself**, which carries the serial number, `genTime` and the
  message imprint, and is held by the **requesting application**. The timestamp
  server keeps **no issuance journal**; the node journal is an operational log,
  not an audit trail of issuance (it is not attributable per token, it rotates,
  and it is not tamper-evident). Part 11 / ALCOA+ record-keeping duties for the
  timestamped records therefore lie with the requesting application, not with
  this module.

## 2. Data-integrity controls this module version adds

These three controls support, but do not by themselves establish, data
integrity for the timestamps a GMP application relies on.

### 2.1 Time accuracy (ALCOA+ "contemporaneous"; Annex 11 §12, data-integrity)

- The `genTime` in every token is taken from the **node system clock**. Its
  accuracy is therefore a direct quality attribute of every timestamp.
- The node clock must be disciplined by NTP (chrony/systemd-timesyncd) and, per
  the data-integrity expectation, protected from arbitrary change by users.
  On an NS8 node the system clock is managed by the platform, not by application
  users.
- The **Self test** (Certificate page) now reports whether the OS considers the
  clock synchronised and the offset reported by the local NTP client, and warns
  above a 1-second deviation. Record the self-test result as evidence of clock
  control at a frequency your risk analysis defines (the test is manual; keep
  any schedule and its records outside the module).

### 2.2 Signing-certificate lifecycle

- Tokens can only be issued and verified while the signing chain is valid. The
  Self test warns 30 days before the leaf or Root CA expires.
- **Rotation replaces the chain**; tokens issued before a rotation stay
  verifiable only against the archived chain (kept under
  `cert-archive/<timestamp>/`), and clients must trust the new Root CA. Treat a
  rotation as a change under change control and preserve the archived chains for
  as long as any token signed by them must remain verifiable.
- ⚠️ **Production signing certificate:** do not renew, replace or otherwise touch
  a production signing certificate as part of routine work. Any change to it is a
  deliberate, planned, controlled action by the operator.

### 2.3 Access restriction (Annex 11 §12, security)

- RFC 3161 is anonymous by design; the service is public by default. The
  optional **client IP allowlist** lets the operator limit which networks may
  request timestamps, as a network-layer control. It does not authenticate
  individual users and is not a substitute for securing the requesting
  application. Document in the URS whether access restriction is required and,
  if so, the approved source ranges.

## 3. Operator checklist (suggested, adapt to your SOPs)

- [ ] URS records the intended use, whether access restriction is required, and
      the retention period for tokens and archived certificate chains.
- [ ] Node clock is NTP-disciplined; self test shows "synchronised" and a small
      offset; result recorded at the defined interval.
- [ ] Certificate expiry monitored (self test); rotation planned before expiry
      under change control.
- [ ] Backups of the module (which include the signing key, its password and the
      archived chains) go to a confidential destination; restore tested.
- [ ] The requesting GMP application stores and protects the tokens as the
      primary records (ALCOA+), and verifies them against the trusted Root CA.

## 4. Open points / placeholders

- ❰ Self-test execution frequency and recording method ❱ — define in an SOP.
- ❰ Retention period for issued tokens and archived certificate chains ❱.
- ❰ Approved client source ranges, if access restriction is used ❱.
