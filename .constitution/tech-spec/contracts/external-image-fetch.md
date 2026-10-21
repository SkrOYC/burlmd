# External image fetch contract

## Purpose

This companion defines the fields and invariants that cross the BND-02 to BND-22 integration. ADR-022 owns the decision and security policy. The code-owned artifact at the sidecar's `artifact_path` implements the final types after BURL-I001 measures the resource envelope.

## Request

An external image request contains an opaque request identity, document revision, opaque image-node identity, and the exact eligible `https` URL parsed from Note source. It carries no Note source, title, concept identity, Workspace path, application authorization, cookie, referrer, origin, client certificate, or inherited proxy credential.

Core rejects user information, a non-HTTPS scheme, a redirect, or a connection target outside the accepted public-address policy before response bytes become render data. The first contract follows zero redirects. A refusal is typed and visible; it isn't retried as a different request policy.

## Result

A successful result contains the request identity, document revision, image-node identity, validated raster media type, dimensions, and bounded compressed bytes or an equivalent inert decoded representation. It contains no active SVG, HTML, script, callback, network handle, or durable cache identity.

A failure contains the same opaque identities and one bounded failure class, such as unsupported destination, redirect refused, network unavailable, TLS refusal, resource limit, unsupported media, invalid bytes, decode refusal, cancellation, or stale revision. It contains no URL, host, query, redirected location, response excerpt, or other content-derived diagnostic field.

Core ignores a result when the Note closes, its revision changes, or the image node disappears. Failure leaves Note source, local Assets, editing, find, undo, save, history, and Export unchanged.

## Resource gate

The final artifact must name encoded-body, decoded-raster, simultaneous-work, and elapsed-work limits accepted from BURL-I001 evidence. This provisional companion deliberately contains no invented numbers. OD-06's imported-image cap does not settle these limits.

## Export and offline behavior

Fetched bytes remain ephemeral. Reopening offline can show alt text and an unavailable state. Plain-directory Export preserves the original external URL and doesn't fetch, embed, import, or convert its bytes. Local Asset export remains a separate verified-copy path.
