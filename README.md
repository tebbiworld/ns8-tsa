# ns8-tsa

A [NethServer 8](https://github.com/NethServer/ns8-core) module that packages an
**RFC 3161 Timestamp Authority (TSA)** based on the
[sigstore timestamp-server](https://github.com/sigstore/timestamp-authority).
It lets you issue and verify trusted timestamp tokens for documents and
signatures (e.g. from LibreSign, JSignPdf or `openssl ts`).

The module runs the distroless `ghcr.io/sigstore/timestamp-server` image as a
single rootless container (UID 65532), bound to `127.0.0.1` and published to the
outside through the node's Traefik reverse proxy on a host name of your choice.

## Installation

Install from the command line of a NethServer 8 node:

```
add-module ghcr.io/tebbiworld/tsa:latest 1
```

The trailing `1` requests a single instance. After installation open the module
UI in the cluster administration interface and configure it.

## Configuration

Open the **Settings** page and set:

- **Host name (FQDN)** – the public name the TSA is reachable at, e.g.
  `tsa.example.org`. It must resolve to (or be forwarded to) this cluster.
- **Request Let's Encrypt certificate** – issue a valid TLS certificate for the
  HTTPS transport.
- **Redirect HTTP to HTTPS** – force clients onto HTTPS.

> These three settings only concern the **HTTPS transport**. They do **not**
> touch the RFC 3161 signing certificate — that is managed on the **Certificate**
> page.

On the first save the module generates its self-signed signing chain (see
[Certificate architecture](#certificate-architecture)) and starts the server.

## Endpoints

All endpoints live under the configured host name:

| Method | Path                              | Purpose                                  |
| ------ | --------------------------------- | ---------------------------------------- |
| POST   | `/api/v1/timestamp`               | Submit a `application/timestamp-query`   |
| GET    | `/api/v1/timestamp/certchain`     | Download the signing certificate chain   |
| GET    | `/ping`                           | Health check                             |

The timestamp URL for clients is therefore:

```
https://<fqdn>/api/v1/timestamp
```

## Client examples

### openssl

```bash
# 1) build a request for a file
openssl ts -query -data mydocument.pdf -sha256 -cert -out request.tsq

# 2) send it to the TSA
curl -s -H 'Content-Type: application/timestamp-query' \
     --data-binary @request.tsq \
     https://tsa.example.org/api/v1/timestamp -o response.tsr

# 3) fetch the chain and verify the token
curl -s https://tsa.example.org/api/v1/timestamp/certchain -o tsa-chain.pem
openssl ts -verify -data mydocument.pdf -in response.tsr -CAfile tsa-chain.pem
```

### LibreSign / JSignPdf and other clients

Configure the TSA / timestamp server URL as:

```
https://tsa.example.org/api/v1/timestamp
```

For the token to validate, the client must **trust the Root CA** of this TSA —
see [Trust](#trust).

## Certificate architecture

This module deliberately keeps **two completely separate** certificates. Do not
confuse them.

### 1. HTTPS transport certificate (Let's Encrypt)

This is the ordinary TLS certificate Traefik serves to HTTPS clients. It is
issued and **renewed automatically by the node's Traefik**, independent of which
node actually terminates the connection. A Let's Encrypt certificate can **not**
be used as the timestamp signing certificate: RFC 3161 requires the critical
`extendedKeyUsage = timeStamping`, which public CAs never issue, and the sigstore
server refuses to start without it.

> **Let's Encrypt / cross-node note:** the HTTP-01 challenge requires that ports
> 80/443 for the FQDN reach *this* node. If requests arrive via DNAT/forwarding
> from a gateway node, leave Let's Encrypt **disabled** and run the route with an
> existing certificate or a wildcard; renewal remains the job of the node's
> Traefik and is transparent to this module.

### 2. RFC 3161 signing certificate (self-signed, long-lived)

The tokens are signed with a dedicated, self-signed EC **P-384** chain that the
module generates on first configuration:

- **Root CA** – `CA:TRUE` (critical), `keyUsage = keyCertSign, cRLSign`
  (critical), valid **10950 days (~30 years)**. Common name defaults to
  `<FQDN> TSA Root CA` and is configurable.
- **Leaf** – `CA:FALSE` (critical), `keyUsage = digitalSignature` (critical),
  `extendedKeyUsage = timeStamping` (critical), valid **9125 days (~25 years)**.
- The leaf key is stored as an **aes-256-cbc encrypted PKCS#8** file; the
  password is generated at module creation and kept in the module configuration.
- The chain (`leaf + root`) is served at `/api/v1/timestamp/certchain` and
  embedded in every token (`--include-chain-in-response=true`).

Existing certificates are **never overwritten** on reconfiguration — rotation is
an explicit action.

> **Back up the Root CA key offline.** The Root CA private key
> (`tsa-root-key.pem`, stored `chmod 400` in the certificate volume) is the trust
> anchor of your whole TSA. Copy it to secure offline storage and treat it as a
> long-term secret.

> **Evidentiary value.** A self-operated TSA is perfectly suitable for internal
> and technical use, but against third parties its tokens carry **limited legal
> weight** compared to those of an accredited, audited timestamping provider. If
> you need qualified/eIDAS-grade timestamps, obtain a commercial timestamping
> certificate and install it via *Upload certificate*.

### Managing the signing certificate (Certificate page)

- **View** the current signer: subject, valid-until, SHA-256 fingerprint and
  Root CA name.
- **Download** the certificate chain.
- **Self test** – issues a real timestamp against the local server and verifies
  it (`/ping` + `Status: Granted` + `openssl ts -verify` against the chain).
- **Rotate** – archives the current chain (with a timestamp in the path) and
  generates a fresh one. Tokens issued **before** a rotation remain verifiable
  only against the archived chain, and clients must trust the new Root CA.
- **Upload** – install an externally obtained timestamping certificate
  (chain + PKCS#8 key + passphrase). The upload is validated before anything is
  replaced: the leaf must carry the critical `timeStamping` EKU and the key must
  match the leaf; otherwise the upload is rejected and the previous chain kept.

Archived chains live under the module state in `cert-archive/<timestamp>/`.

## Trust

Clients that verify your tokens must trust the **Root CA**. Download the chain
from `/api/v1/timestamp/certchain` (or the Certificate page) and import the Root
certificate into the verifying client's trust store, for example:

- **Adobe Acrobat / Reader** – import the Root into the *Trusted Certificates*
  list and enable it for *certified documents / timestamping*.
- **openssl** – pass the chain via `-CAfile`, as shown above.
- **OS trust store** – import the Root CA if system-wide trust is required.

## Terms of use and eIDAS disclaimer

This module operates a **self-run** timestamp authority. By installing and using
it you acknowledge:

- **It is not a qualified trust service.** The authority is **not** a qualified
  electronic timestamp service under eIDAS (Regulation (EU) No 910/2014) or any
  comparable scheme, and the module author is not an accredited or supervised
  trust service provider. The tokens do not carry the legal presumption that a
  qualified timestamp enjoys.
- **The trust anchor is a self-signed root.** Tokens are signed under a
  self-signed Root CA that is generated on this node (see
  [Certificate architecture](#certificate-architecture)); they are trusted only
  by parties who have explicitly imported that Root CA. Against third parties who
  have not, the tokens carry limited evidentiary weight.
- **Operating it is your responsibility.** Clock accuracy, protection of the
  signing key, availability and record keeping are the operator's
  responsibility (see [Security and compliance](#security-and-compliance)).

If you need qualified or eIDAS-grade timestamps, obtain a commercial
timestamping certificate from an accredited provider and install it through the
Certificate page (*Upload certificate*).

## Security and compliance

### What is recorded about issued timestamps

The sigstore timestamp-server is **stateless**: it signs each request and
returns the token without keeping a copy. It offers no issuance journal and no
transparency log — the only logging it has is operational HTTP request logging
(`--log-type dev|prod`) written to the container's standard output, which NS8
collects in the node journal (and in Loki, if configured). That log records
*that* a request was served (the time of the HTTP call, the path, the status, a
request id) but **not** the content of the token: it does not store the token
serial number, the RFC 3161 `genTime`, or the message imprint (the hash of the
stamped data).

The authoritative record in RFC 3161 is **the timestamp token itself**. Each
token carries, cryptographically bound and signed by the authority:

- the **serial number** of the token,
- the **genTime** — the asserted time, and
- the **message imprint** — the hash (and hash algorithm) of the data that was
  stamped.

Verification is cryptographic, against the certificate chain; it does not rely
on any server-side record.

### Fit for 21 CFR Part 11 / ALCOA+

Treat the module as GAMP infrastructure (a signing service), not as the system
of record:

- The node journal is **not**, on its own, a sufficient audit trail of issued
  timestamps. It has no per-token serial/hash/time entry, it is operational and
  subject to rotation (not tamper-evident), and because RFC 3161 requests are
  unauthenticated the entries are **not attributable** to an end user.
- The ALCOA+ record is the token, held and stored by the **requesting**
  application next to the data it protects. That application — not the TSA —
  carries the Part 11 obligations (attributability of the requester, retention,
  audit trail). If you need a central issuance log, build it at that integration
  layer by storing each returned token with its serial number, message imprint
  and `genTime`.
- **Time source.** `genTime` is only as trustworthy as the node clock. The
  module relies on the node's system time (chrony / systemd-timesyncd) and does
  not enable the server's optional NTP monitoring. For GMP use, keep the node
  time synchronised and protected against tampering, and record the time source
  in your validation.

### Protecting the signing key and backups

- **The signing keys live on the node.** Both the leaf key
  (`tsa-leaf-key-enc.pem`, the key that actually signs tokens) and the Root CA
  key (`tsa-root-key.pem`, mode `0400`) are kept in the certificate volume on
  the node. Anyone who can read the leaf key together with its password can issue
  tokens in your authority's name; anyone who holds the Root CA key can mint new
  leaf certificates.
- **Keep the Root CA key offline.** The server never uses the Root CA private
  key — it signs only with the leaf key. The root key is needed solely to issue
  or rotate a leaf. The recommended posture is therefore an *offline root*: copy
  `tsa-root-key.pem` to secure offline storage right after the first
  configuration and treat it as a long-term secret. Leaving it on the node is the
  module default so that in-place rotation keeps working; if you remove it, keep
  it somewhere you can restore from before you rotate.
- **Backups are as sensitive as the keys.** The module backup contains the leaf
  key, the Root CA key, every archived chain and `state/passwords.env` with the
  key password — everything needed to impersonate the authority. Send module
  backups only to a **confidential, access-controlled and encrypted**
  destination, and restrict who may restore them.
- **Uploaded certificates are validated strictly.** *Upload certificate*
  installs an externally obtained signer only after verifying that the leaf
  carries the critical `timeStamping` EKU, that the supplied private key matches
  the leaf, and that the passphrase decrypts it. If any check fails the upload is
  rejected and the previous chain is kept untouched; on success the key is
  re-encrypted with the module's own key password before it is installed.

## Tests

Two helper scripts are provided in [`tests/`](tests/):

- `smoke-test.sh <fqdn>` – run in the module user context
  (`runagent -m <instance> bash tests/smoke-test.sh <fqdn>`). It checks that the
  container runs without restart-looping, `/ping` answers, a timestamp query
  returns `Status: Granted`, `openssl ts -verify` succeeds against the chain, the
  certchain endpoint returns the chain, and the public Traefik route issues a
  token over HTTPS.
- `negative-eku-test.sh <instance>` – uploads a certificate **without** the
  `timeStamping` EKU and asserts that the module rejects it.

## Updating from 1.0.2 or older

Up to 1.0.2 the certificate files were owned by a container sub-UID, which makes
`update-module` abort in the core (recursive `chown` over the module directory).
Run this once before updating, with your instance name:

    runagent -m tsa1 podman unshare chown -R 0:0 state/certs state/cert-archive

If the update was already tried and failed: the running service is not
affected. Open the TSA settings in cluster-admin and press Save once, the new
code takes the files back by itself, then update again.
From 1.1.0 on the files stay owned by the module user and the container maps
that user to the server UID (`--userns=keep-id:uid=65532,gid=65532`).

## Backup, restore and secrets

The module backup contains the signing key and certificate chain
(`state/certs`), the archived certificate generations (`state/cert-archive`)
and `state/passwords.env` with the password of the encrypted key. A restored
authority signs with the original key. The key password is never stored in the
module environment (NS8 mirrors that to Redis) and never appears on a command
line: the server reads it from a private configuration file.

## Build and publish

The module image is built and pushed to the GitHub container registry:

```bash
# build locally (produces ghcr.io/tebbiworld/tsa)
./build-images.sh

# or let the GitHub Action publish-images.yml build & push on tag/push
```

Runtime image pinned by this module: `ghcr.io/sigstore/timestamp-server:v2.1.2`.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
