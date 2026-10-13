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

| Amaç                                   | Uç nokta                                                                                                        |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Canlı vitrin                           | `GET /public/discovery/feed?surface=homepage\|events&city_id=`                                                  |
| Şehir/semt sayıları                    | `GET /public/discovery/locations`                                                                               |
| Konumdan şehir                         | `GET /locations/reverse-geocode?lat=&lng=`                                                                      |
| Restoran listesi + müsaitlik           | `GET /public/listings` (`date`, `start_time`, `guestCount`, `lat/lng/radius`, `listingIds`, `cuisine`, `query`) |
| Filtre seçenekleri                     | `GET /public/listings/filters`                                                                                  |
| Restoran detayı                        | `GET /public/restaurants/:slug`                                                                                 |
| Slot ve müsaitlik                      | `GET /venues/public/:venueId?startDate=&endDate=&guestCount=`                                                   |
| Restoran rezervasyonu                  | `POST /reservations` (`source: masaport_ios`)                                                                   |
| Bekletmeyi bırakma                     | `POST /reservations/holds/:holdId/cancel` (`hold_uuid`; rezervasyona dönüşmüş bekletmeye dokunmaz)               |
| Misafir rezervasyon durumu             | `GET /public/reservations/:uuid/manage` (yönetim bağlantısındaki token ile Bearer)                              |
| Etkinlik listesi / kategoriler / detay | `GET /public/events`, `GET /public/event-categories`, `GET /events/:id/public`                                  |
| Etkinlik kaydı                         | `POST /events/:id/instances/:instanceId/reservations`                                                           |
| Ödeme yapılandırması / durumu          | `GET /payments/config`, `GET /payments/:id/public-status`                                                       |
| QR                                     | `GET /qr/:uuid` (etkinlik kayıtları)                                                                            |

| Hesap | `POST /customer/auth/register`, `/register/verify`, `/register/resend`, `/login`, `/refresh`, `/logout`, `/forgot-password`; `GET/PATCH /customer/auth/me`; `POST /customer/auth/change-password` |
| Rezervasyonlarım | `GET /customer/reservations` (restoran kayıtlarında `management_url`) |

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
restoranlarda tarih, saat, kişi ve iletişim bilgileri uygulamada alınır; yalnızca kart ve
3D Secure adımı `app.masaport.com` üzerindeki güvenli web akışına `SFSafariViewController`
ile devredilir. Giriş yapılmış kullanıcıda ödeme öncesi masa bekletmesi API üzerinden
oluşturulur ve kullanıcı hesabına bağlı kalır. Web ödeme sayfası kapatılınca uygulama
rezervasyonun hesaba düşüp düşmediğini kontrol eder; düşmediyse kısa bir bekleme süresinden sonra
bekletmeyi bırakır. Slot rozetleri, tutarlar ve web'e aktarılan parametreler haftalık şablondan değil,
`availability[tarih].slots[id]` içindeki o tarihe özel kuraldan gelir; `prepayment_capture_mode: PREAUTH`
olan saatlerde "Kart provizyonu" gösterilir (tutar çekilmez, kartta bloke edilir).
Ücretli etkinlikler de aynı güvenli web akışını kullanır. Bilet seçenekli etkinliklerde (`ticketConfig`)
bilet uygulamada seçilir ve `ticket_option_id` gönderilir; ücretli bilet web'e devredilir.
Uygulamadan yapılan restoran rezervasyonlarında "Rezervasyonu yönet" iptal/değişiklik talebi için
app.masaport'taki imzalı misafir sayfasını açar.
`GET /payments/config` hosted bir sağlayıcı bildirirse
(`requiresCardDetails: false`) uygulama doğrudan `checkoutUrl` açar ve `public-status` ucunu
yoklayarak sonucu yerel kayda işler. Harici bilet siteleri (`ticket_url`) doğrudan açılır.

## Ortam

`Configuration/Debug.xcconfig` yerel API'yi (`http://127.0.0.1:3000/api`), public web'i
(`http://127.0.0.1:3001`) ve web'e devredilen rezervasyon/ödeme akışını
(`http://localhost:5173`) kullanır. Vite geliştirme sunucusu varsayılan olarak
IPv6 loopback (`[::1]`) üzerinde dinlediği için rezervasyon adresinde `localhost`
kullanılır. Bu loopback adresleri iOS Simulator içindir.

Fiziksel cihazdaki Debug derlemesi Mac'e aynı Wi-Fi üzerinden, DHCP ile değişmeyen
Bonjour adıyla (`Yigit-MacBook-Pro-2.local`) ulaşır. Bunun için sunucular tüm
arayüzlerde dinlemelidir (landing: `npm run dev -- -p 3001 -H 0.0.0.0`, Vite:
`npm run dev -- --host`) ve ilk açılışta iOS'un yerel ağ iznine onay verilmelidir.
Web'e devredilen ödeme sayfası telefonda açıldığında `app.masaport` kendi API adresini
(`VITE_API_URL`) kullanır; o adres `localhost` ise cihazdaki ödeme adımı yerelde
tamamlanamaz. Başka bir Mac veya sabit IP için git'e girmeyen
`Configuration/Debug.local.xcconfig` dosyasına örneğin
`MASAPORT_DEV_HOST[sdk=iphoneos*] = 192.168.1.20` yazın.

Release yapılandırması sırasıyla `https://api.masaport.com/api`, `https://www.masaport.com`
ve `https://app.masaport.com` production adreslerini kullanır.

## Universal Links ve deep link

`https://masaport.com/restaurant/:slug`, `/:city/restoranlar/:slug`, kısa rezervasyon bağlantısı
`/r/:slug?date=&time=&guests=` (restoran detayı açılır ve rezervasyon akışı ön seçimle başlar),
`https://masaport.com/etkinlikler/:id|:slug` ve şehirli etkinlik URL'leri uygulama
yüklüyse ilgili detay ekranını açar; uygulama yoksa aynı web sayfası çalışmaya devam eder.
İlişkilendirme için `MasaPort/MasaPort.entitlements` içindeki Associated Domains ve
landing projesindeki `public/.well-known/apple-app-site-association` birlikte deploy
edilmelidir. `masaport://restaurant/:slug` ve `masaport://event/:id` özel şemaları da
geriye dönük olarak desteklenir.

Associated Domains Release'te ve Debug'ın simülatör derlemesinde bağlıdır; Debug cihaz
kurulumunda bilerek bağlı değildir (imzalama profili gerektirir). Cihazlar AASA dosyasını
Apple'ın CDN'inden alır; `masaport.com` (www'suz) adresi Cloudflare'de `www`'ya 301 verse
de CDN'de iki alan adı için de dosya bulunur (2026-10-12'de doğrulandı). AASA değişikliği
deploy edildikten sonra CDN'in güncellenmesi zaman alabilir; kontrol için:
`curl https://app-site-association.cdn-apple.com/a/v1/www.masaport.com` (ve `masaport.com`).
Simülatörde deneme:
`xcrun simctl openurl booted https://www.masaport.com/istanbul/restoranlar/<slug>`.

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
- Universal Links: `https://masaport.com/...` ve `https://www.masaport.com/...`
