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
- Walk-in misafir kaydı (`POST /reservations/:venueId/walk-in`): ad, telefon, kişi, saat, süre,
  isteğe bağlı masa seçimi (`/available-tables`) ve anında check-in
- Rezervasyon detayında personel işlemleri: onayla / iptal et (`PUT .../status`), gelmedi
  (`POST .../no-show`, sebep zorunlu); sonuçlanan kayıtlar için masa ve servis bölümleri kapanır
- Rezervasyon detayında düzenleme (`PUT /reservations/:venueId/:id`): ad, telefon, kişi sayısı, not
  ve check-in öncesi başlangıç saati (`start_time`, süre korunur; masa çakışmasında 409
  `TABLE_CONFLICT` mesajı gösterilir); kayıt sonrası `GET .../:id` ile güncel `updatedAt` çekilir
- Etkinlik katılımcısına operasyon notu (`PUT /events/:venueId/reservations/:eventId/:id/note`),
  satırda kaydırma veya uzun basma ile
- Host Masası'nda içerideki misafir satırında kaydırma/uzun basma ile servis adımı
  (`PUT .../service-status`); Bugün'de bekleme listesi kısayolu ve tek dokunuşla masa teklifi
- Host Masası "Salon" görünümü: masalar bölge bölge, masasız misafirler tepsi olarak; misafiri
  basılı tutup bir masaya sürükleyince onayla `PUT .../tables` (mevcut masa tek masayla değişir)
- Bekleme listesi kaydını walk-in'e dönüştürme (form ön dolu; kayıt sonrası bekleme kaydı
  `CONVERTED`); Bugün'deki bekleme bölümünden de ulaşılır
- Host Masası ve etkinlik katılımcı aramasında öneriler (eşleşen misafir adları) ve cihazda
  tutulan son aramalar (`Shared/SearchHistoryStore.swift`)
- Host Masası'nda gün seçimi (Bugün / Yarın / takvim) ve Bugün'de masaya dokununca o masanın
  günlük rezervasyon sayfası
- Kamera ile QR check-in (restoran ve etkinlik rezervasyonu, kısa kodla elle giriş, erken check-in onayı)
- Etkinlikler sekmesi: seans bazlı katılımcı listesi, arama ve check-in (oluşturma/düzenleme web panelinde kalır)
- Uygulama ikonuyla aynı lacivert/slate marka rengini kullanan, açık/koyu tema uyumlu
  tasarım dili (`Shared/DesignSystem.swift`): lacivert hero başlık (Bugün, Giriş, Profil),
  saat bloğu ve takvim yaprağı, baş harf avatarları, halka/çubuk ilerleme, kayan segment
  çubuğu, hairline+gölgeli kartlar
- Bugün ekranında hızlı eylemler (QR, Host Masası, Bekleme), saatlik "Gün akışı" yoğunluk
  grafiği ve bölge bazlı "Salon durumu" masa haritası (masa servis durumu renkleri)
- Küçük ve orta boy “Bugünün Operasyonu” ana ekran widget'ı (lacivert hero yüzey, karşılanan
  misafir halkası, sıradaki rezervasyon, içeride/dolu masa/bekleme/onay metrikleri)

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
