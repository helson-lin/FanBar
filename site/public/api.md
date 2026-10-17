# FanBar Product Facts API

> A public, read-only API exposing canonical FanBar product, compatibility, installation, and safety facts. No key or account is required.

- Documentation: https://fanbar.jarin.me/api
- API catalog: https://fanbar.jarin.me/.well-known/api-catalog
- OpenAPI 3.1 description: https://fanbar.jarin.me/openapi.json
- Last updated: 2026-10-12

## Endpoints

### Product facts

`GET https://fanbar.jarin.me/api/product.json`

Returns canonical product, pricing, compatibility, installation, feature, language, and safety facts as JSON.

### Publication status

`GET https://fanbar.jarin.me/api/health.json`

Returns a small JSON status document confirming that the static API is available.

## Discovery

`GET https://fanbar.jarin.me/.well-known/api-catalog`

Returns RFC 9727 Linkset JSON with `service-desc`, `service-doc`, and `status` relations.

## Usage

```sh
curl https://fanbar.jarin.me/api/product.json
curl https://fanbar.jarin.me/api/health.json
curl https://fanbar.jarin.me/.well-known/api-catalog
```

All endpoints are read-only, public, and served over HTTPS. They do not expose device-control operations or personal data.
