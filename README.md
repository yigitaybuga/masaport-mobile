# MasaPort Native Mobile

Native mobile applications live under this directory and deliberately do not
share UI code with the web applications.

| Product | Audience | Planned native clients | Location |
| --- | --- | --- | --- |
| MasaPort Operasyon | Venue teams | iOS first, Android next | `ios/MasaPortOperation` |
| MasaPort | Guests | iOS and Android | Reserved for a later phase |

The API is the single source of truth for both applications. Mobile-specific
authentication, device registration and push contracts belong to
`api.masaport`; they are never implemented as client-side workarounds.

See [`docs/mobile-operations-ios-phase-0.md`](../docs/mobile-operations-ios-phase-0.md)
for the approved initial scope and API gap list.
