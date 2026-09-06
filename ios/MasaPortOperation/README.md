# MasaPort Operasyon for iOS

`MasaPortOperation.xcodeproj` dosyasını Xcode 26+ ile açın. Uygulama iOS 17 ve
sonrasını hedefler.

Yerel API için Debug scheme'de `MASAPORT_API_BASE_URL` varsayılanı
`http://127.0.0.1:3000/api`'dir ve iOS Simulator içindir. Fiziksel cihazda
güvenilir bir HTTPS geliştirme endpoint'i kullanın; production API değeri
kaynak koda yazılmaz.

Bu ilk dilim Faz 1 altyapısıdır. iOS uygulaması `/mobile/auth/*` ile kısa
ömürlü erişim token'ı ve Keychain'deki döndürülen refresh token'ı kullanır.
Host Masası ve Bekleme Listesi, kısa ömürlü mobil Bearer token'ıyla WebSocket
bağlantısı kurar ve ilgili operasyon değişikliklerinde veriyi yeniler. APNs
teslimi ve QR token sözleşmeleri sonraki dilimlerde etkinleştirilecektir.

Mevcut native kapsam:

- `/mobile/auth/*` ile cihaz-bağımlı giriş, refresh ve güvenli çıkış
- Aktif mekan seçimi, Bugün özeti için REST veri katmanı ve profil/çıkış
- Operasyon önceliğine göre geciken, sıradaki ve içerideki misafir durumları
- Host Masası hızlı check-in, masa atama ve servis durumu geçişleri
- Aktif bekleme listesi, teklif gönderme ve güvenli listeden kaldırma akışı
- Kamera ile QR check-in (restoran ve etkinlik rezervasyonu, kısa kodla elle giriş, erken check-in onayı)
- Etkinlikler sekmesi: seans bazlı katılımcı listesi, arama ve check-in (oluşturma/düzenleme web panelinde kalır)
- Uygulama ikonuyla aynı lacivert/slate marka rengini kullanan, sistem renklerine dayalı
  açık/koyu tema uyumlu tasarım dili (`Shared/DesignSystem.swift`)
- Küçük ve orta boy “Bugünün Operasyonu” ana ekran widget'ı

## Demo modu (yalnızca Debug)

Tasarımı ve akışları gerçek API'ye bağlanmadan denemek için Debug derlemesini
`MASAPORT_DEMO=1` ortam değişkeni veya `-masaport-demo` başlatma argümanıyla
çalıştırın. Ağ istekleri `Core/Networking/DemoAPI.swift` içindeki bellek içi örnek
verilerle yanıtlanır; herhangi bir e-posta ve parola ile giriş yapılır. Release
derlemelerine bu kod dahil edilmez.

```bash
xcrun simctl launch --terminate-running-process <UDID> com.masaport.operation.debug --setenv MASAPORT_DEMO=1
```

## Widget ve App Group

Uygulama ile widget yalnızca kişisel veri içermeyen operasyon özetini
`group.com.masaport.operation` App Group'u üzerinden paylaşır. Token, müşteri adı,
telefon, e-posta ve rezervasyon notu widget alanına yazılmaz. Oturum kapatıldığında
paylaşılan özet temizlenir.

Fiziksel cihaz ve App Store dağıtımından önce Apple Developer hesabında aynı App
Group'u oluşturup aşağıdaki App ID'lerine ekleyin; ardından provisioning
profillerini yenileyin:

- `com.masaport.operation`
- `com.masaport.operation.widget`
- Debug cihaz kurulumu kullanılacaksa `com.masaport.operation.debug` ve
  `com.masaport.operation.debug.widget`
