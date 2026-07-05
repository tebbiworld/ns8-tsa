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
