<!--
First community post for the NS8 TSA module, written in the style
of https://community.nethserver.org/t/ns8-forgejo-testing/28554 (first post).
Paste into a new topic on community.nethserver.org, category "App", tag "ns8".
Fill in the wiki link once the page is published.
-->

# NS8 TSA (testing)

Hi all,

I've built an NS8 module for the [sigstore timestamp-authority](https://github.com/sigstore/timestamp-authority) — an RFC 3161 Timestamp Authority that issues and verifies trusted timestamp tokens for documents and signatures.

It's in my community repository. To try it, add the repo once:

```
api-cli run add-repository --data '{"name":"tebbiworld","url":"https://raw.githubusercontent.com/tebbiworld/ns8-repo/main/ns8/updates/","status":true,"testing":false}'
```

then install **TSA** from the Software Center. (Or straight from the image: `add-module ghcr.io/tebbiworld/tsa:latest 1`.)

What it does:

* Exposes the RFC 3161 timestamp endpoint (`POST /api/v1/timestamp`), plus a certificate-chain download and a health check, on a host name of your choice through Traefik
* Generates its own dedicated self-signed EC **P-384** signing chain on first configuration (a ~30-year Root CA and a `timeStamping` leaf)
* Works with `openssl ts`, LibreSign, JSignPdf and any other RFC 3161 client
* Certificate page lets you view, download, self-test and rotate the signer, or upload an externally obtained timestamping certificate
* Runs as a single rootless container bound to 127.0.0.1, published through the node's reverse proxy

A few things to know:

* The signing certificate is kept completely separate from the HTTPS/Let's Encrypt certificate — a public CA can't be a TSA signer, since RFC 3161 needs the critical `timeStamping` EKU that public CAs never issue.
* Clients that verify your tokens must trust your **Root CA** (download the chain and import the Root). Back up the Root CA private key offline — it's the trust anchor for everything.
* A self-operated TSA is great for internal and technical use, but its tokens carry limited legal weight against third parties compared with an accredited, audited provider. For eIDAS-grade timestamps, buy a commercial timestamping certificate and upload it.

It's been through the smoke tests here and issues/verifies tokens fine, but I'd welcome others trying it against their own signing workflows — let me know how it goes.

Docs: NethServer wiki (tebbiworld repository) · Source: [github.com/tebbiworld/ns8-tsa](https://github.com/tebbiworld/ns8-tsa)

Thanks!

*Category: App · Tags: ns8*
