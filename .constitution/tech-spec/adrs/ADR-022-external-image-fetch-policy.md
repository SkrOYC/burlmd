---
id: ADR-0022
status: proposed
date: 2026-10-14
certainty: assumed
assumption: "The policy is grounded in the pinned HTTP client and two independent designs, but SPK-BURL-I001 has not established the encoded-body, decoded-raster, concurrency, or deadline limits or proved connection-target enforcement."
---
# ADR-022: External image fetch policy

## Context

CAP-090 requires automatic loading of an external Markdown image when its Note opens. The external response is untrusted and crosses BND-22. It isn't a local Asset, an Object, a Provider request, or Remote synchronization. Loading through a general UI image widget or an authenticated client would hide redirects, inherited credentials, network destinations, resource costs, and cancellation from Core authority.

## Candidate decision

Core uses a dedicated external-image client built on the pinned `reqwest` 0.13.4 dependency. It doesn't reuse the Provider, Remote, Object Store, OAuth, or Flutter image-networking clients. Opening a Note returns immediately with placeholders, then schedules cancellable fetches keyed by the document revision and image identity.

The initial policy accepts only `https` URLs without user information. It rejects HTTP and non-web schemes. It also rejects loopback, link-local, private, multicast, and otherwise nonpublic connection targets based on the actual connection address. The first implementation follows zero redirects. A redirect is a visible unavailable-image outcome rather than permission to cross to another target. A later policy can allow bounded HTTPS redirects only after each hop receives the complete destination and credential-isolation checks.

The client uses standard certificate and hostname validation. It sends no `Authorization`, `Proxy-Authorization`, cookies, `Referer`, `Origin`, client certificate, Note-derived header, or telemetry. It doesn't inherit a credential-bearing proxy configuration. The request contains only what the selected external reference requires.

The client streams into a bounded buffer, validates the media type and magic bytes, and accepts only inert raster data that decodes within the measured resource envelope. SVG, HTML, and other active documents are refused. Exact body, pixel, memory, concurrency, and elapsed-work limits remain evidence-dependent. The provisional 25 MiB imported-image value from OD-06 is an input to measurement, not a web-download or decoded-image limit.

Fetched bytes are ephemeral render data. They don't create a local Asset, enter the Local Asset Store, become an Object, or enter Workspace history. Closing or changing the Note, changing its revision, or removing the image cancels or invalidates the result. Offline or failed loading shows alt text and an unavailable state without blocking Note opening, editing, find, undo, save, local-image use, or history.

Plain-folder Export preserves the external URL in the Note. It neither fetches nor embeds external bytes. Export continues to copy and verify referenced local Assets under its separate contract.

Diagnostics record only a bounded failure class. They never record the URL, host, query, response bytes, redirected location, or another content-derived value.

## Evidence required

SPK-BURL-I001 must measure a shared encoded-body and decoded-raster envelope against NFC-02, NFC-05, and NFC-08 without settling OD-06 by assumption. It must cover false `Content-Length`, streaming overflow, extreme dimensions, decompression bombs, slow or stalled responses, cancellation, unsupported formats, simultaneous images, URL user information, redirects, DNS rebinding, and public names that resolve to nonpublic addresses.

The evidence must also prove that the configured `reqwest` client disables redirects, automatic referrers, cookies, inherited proxy credentials, and application authorization. A Stage 3 patch must publish the measured limits and the tested connection-target enforcement before production implementation begins.

## Alternatives considered

Both independent designs selected a dedicated credential-free Core client, HTTPS-only external loading, public connection targets, inert raster decoding, ephemeral results, placeholders on failure, and URL-preserving Export. One design recommended zero redirects for the first implementation. The other allowed a bounded redirect count with complete per-hop revalidation. Zero redirects is the smaller reversible policy and needs no invented count, so it is the proposed initial behavior.

Using Flutter `Image.network` was rejected because a widget isn't the application's credential, redirect, target-address, resource, or cancellation policy. Reusing an authenticated client was rejected because credentials and cookies must be unrepresentable on this path. Persisting a cache or automatically importing the image was rejected because CAP-090 keeps external references distinct from local Assets.

## Consequences

- External image loading adds no durable state and doesn't weaken offline guarantees for imported local images.
- Some valid public images fail because they use HTTP, redirects, SVG, or a refused resource shape. The UI reports the refusal without rewriting the Note.
- The pinned `reqwest` version is reusable, but its defaults don't satisfy this policy. The implementation must configure each required behavior explicitly and run blocking I/O away from the UI thread.
- No production ticket can choose resource limits or claim DNS and connection-address safety before the evidence-backed Stage 3 patch lands.

## Verification anchors

- [`reqwest` 0.13.4 blocking `ClientBuilder`](https://docs.rs/reqwest/0.13.4/reqwest/blocking/struct.ClientBuilder.html)
- [Flutter `Image.memory`](https://api.flutter.dev/flutter/widgets/Image/Image.memory.html)

