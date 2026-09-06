# MasaPort for iOS (tüketici uygulaması)

masaport.com'un native iOS karşılığı: ziyaretçiler restoranları ve etkinlikleri keşfeder,
müsait masa veya seans varsa uygulama içinden rezervasyon yapar. `MasaPortOperation`
(işletme/operasyon uygulaması) ile aynı klasörde, bağımsız bir Xcode projesidir.

`MasaPort.xcodeproj` dosyasını Xcode 26+ ile açın. Uygulama **iOS 26 ve sonrasını**
hedefler; Liquid Glass tasarım dili (cam sekme çubuğu, arama rolü sekmesi, cam alt
çubuklar, `backgroundExtensionEffect` hero görselleri) doğrudan sistem API'leriyle kullanılır.

## Yapı

- `App/` – giriş noktası, sekmeler (`AppRootView`), ortak rotalar (`AppRoute`), paylaşılan durum (`AppModel`)
- `Core/Networking/` – `APIClient` (envelope çözümleme, hata haritalama), `PublicAPI` (tip güvenli uç noktalar), `DemoAPI` (yalnızca Debug)
- `Core/Models/` – public API modelleri; Prisma `Decimal` alanları `APINumber` ile string/sayı fark etmeksizin çözülür
- `Core/Persistence/` – favoriler, yerel rezervasyon kaydı ve tercihler (cihazda saklanır)
- `Core/Location/` – tek seferlik "kullanırken" konum
- `Features/` – Keşfet, Restoranlar, Rezervasyon akışı, Etkinlikler, Arama, Rezervasyonlarım, Profil
- `Shared/DesignSystem.swift` – `MP` tokenları (Operasyon uygulamasıyla aynı lacivert marka rengi), cam rozetler, çipler, form bileşenleri

Proje "file system synchronized group" kullanır; `MasaPort/` altına eklenen her Swift dosyası
otomatik olarak hedefe dahil olur, pbxproj'a elle kayıt gerekmez.

## Kullanılan public API uçları

| Amaç | Uç nokta |
|---|---|
| Canlı vitrin | `GET /public/discovery/feed?surface=homepage\|events&city_id=` |
| Şehir/semt sayıları | `GET /public/discovery/locations` |
| Konumdan şehir | `GET /locations/reverse-geocode?lat=&lng=` |
| Restoran listesi + müsaitlik | `GET /public/listings` (`date`, `start_time`, `guestCount`, `lat/lng/radius`, `listingIds`, `cuisine`, `query`) |
| Filtre seçenekleri | `GET /public/listings/filters` |
| Restoran detayı | `GET /public/restaurants/:slug` |
| Slot ve müsaitlik | `GET /venues/public/:venueId?startDate=&endDate=&guestCount=` |
| Restoran rezervasyonu | `POST /reservations` (`source: masaport_ios`) |
| Etkinlik listesi / kategoriler / detay | `GET /public/events`, `GET /public/event-categories`, `GET /events/:id/public` |
| Etkinlik kaydı | `POST /events/:id/instances/:instanceId/reservations` |
| Ödeme yapılandırması / durumu | `GET /payments/config`, `GET /payments/:id/public-status` |
| QR | `GET /qr/:uuid` (etkinlik kayıtları) |

| Hesap | `POST /customer/auth/register`, `/register/verify`, `/register/resend`, `/login`, `/refresh`, `/logout`, `/forgot-password`; `GET/PATCH /customer/auth/me`; `POST /customer/auth/change-password` |
| Rezervasyonlarım | `GET /customer/reservations` |

## Hesap ve oturum

Tüketici hesabı işletme panelinden (app.masaport) bağımsızdır. Kayıt e-posta OTP ile
doğrulanır; giriş sonrası erişim token'ı bellekte, refresh token Keychain'de tutulur
(`Core/Session/CustomerSessionStore.swift`). `APIClient` süresi dolan token'ı 401 sonrası bir
kez yeniler. Giriş yapılmışken yapılan rezervasyonlar Bearer ile gönderilir ve hesaba
bağlanır; Rezervasyonlar sekmesi sunucudaki hesap kayıtlarıyla cihazdaki kayıtları
birleştirir. Şifre sıfırlama bağlantısı web'e (`masaport.com/hesap/sifre-sifirla`) gider;
kullanıcı yeni şifreyle uygulamadan giriş yapar. Favoriler cihazda tutulmaya devam eder.

## Ödeme akışı

Varsayılan sağlayıcı kart bilgisi istediğinden (`requiresCardDetails: true`), ön ödeme gerektiren
restoran slotları ve ücretli etkinlikler `app.masaport.com` üzerindeki güvenli web akışına
`SFSafariViewController` ile devredilir. `GET /payments/config` hosted bir sağlayıcı bildirirse
(`requiresCardDetails: false`) uygulama doğrudan `checkoutUrl` açar ve `public-status` ucunu
yoklayarak sonucu yerel kayda işler. Harici bilet siteleri (`ticket_url`) doğrudan açılır.

## Ortam

`Configuration/Debug.xcconfig` yerel API'yi (`http://127.0.0.1:3000/api`) kullanır; Release
`https://api.masaport.com/api`. `MASAPORT_WEB_BASE_URL` paylaşım bağlantıları,
`MASAPORT_BOOKING_BASE_URL` web'e devredilen ödeme akışları içindir.

## Demo modu (yalnızca Debug)

Gerçek API olmadan denemek için `MASAPORT_DEMO=1` ortam değişkeni veya `-masaport-demo`
başlatma argümanı kullanılır. API çağrıları `Core/Networking/DemoAPI.swift` içindeki örnek
verilerle yanıtlanır; görseller ağdan gelir. Release derlemelerine dahil edilmez. Demo hesap:
`demo@masaport.com` / `Demo1234`; kayıt akışında doğrulama kodu her zaman `123456`. Yerel API
ile test ederken `@e2e.masaport.local` adresleri e-posta göndermez ve kod cevapta
(`debug_code`) döner; Debug derlemesi bu kodu OTP alanına otomatik yazar.

```bash
SIMCTL_CHILD_MASAPORT_DEMO=1 xcrun simctl launch --terminate-running-process <UDID> com.masaport.app.debug
```

## Derleme ve test

```bash
xcodebuild -project MasaPort.xcodeproj -scheme MasaPort -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

```bash
xcodebuild -project MasaPort.xcodeproj -scheme MasaPort -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Bundle kimlikleri

- Release: `com.masaport.app`
- Debug: `com.masaport.app.debug`
- URL şeması: `masaport://`
