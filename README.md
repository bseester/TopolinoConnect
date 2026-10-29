# Topolino Connect

Fiat Topolino / Citroën Ami için CAN verisini ESP32 + MCP2515 üzerinden izleyen araç yazılımı.

## Uygulamalar

| Uygulama | Kaynak | Kullanım |
|---|---|---|
| Android Gateway | [`AndroidGateway/`](AndroidGateway/README.md) | ESP’den Bluetooth LE veya USB-OTG seri bağlantısı; canlı araç ölçümleri, CAN kayıtları ve isteğe bağlı iOS aktarımı |
| Mac CAN Monitor | [`MacApp/`](MacApp/TopolinoConnectMac.swift), [`Sources/MCP2515SerialMonitor.swift`](Sources/MCP2515SerialMonitor.swift) | ESP’nin USB seri CAN akışını, ham kareleri ve hız sinyalini izleme |
| iOS test portu | [`MyCitroenPort/`](MyCitroenPort/README.md) | iOS/Widget/Watch uygulaması; Android rölesinden araç verisi alır |
| Swift ortak paket | [`Sources/`](Sources/) | CAN çerçeve çözümleme ve ESP seri monitör desteği |
| ESP32 firmware | [servicemensch/TopolinoInfoDisplay](https://github.com/servicemensch/TopolinoInfoDisplay) | Ayrı ESP32 + MCP2515 kaynak deposu; CAN dinleme, BLE ve USB seri aktarım |

Proje yapısı ve veri akışı için [`docs/PROJECT_MAP.md`](docs/PROJECT_MAP.md), yerel kurulum için [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md), yayın öncesi için [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md) dosyalarına bak.

## Hızlı başlangıç

### Android

`AndroidGateway/` klasörünü Android Studio’da aç veya orada `./gradlew testDebugUnitTest lintDebug assembleDebug` çalıştır. Uygulamada bağlantı kaynağını **Bluetooth** ya da **USB-OTG** olarak seç. Kaynaklar aynı anda çalıştırılmaz; OTG seçimi Bluetooth servisinin durmasını ve yeniden başlatma tercihinin kapanmasını sağlar. Ayrıntı: [`AndroidGateway/README.md`](AndroidGateway/README.md).

### Mac

Swift ortak kodunu `swift test` ile doğrula. CAN monitörünü derleme ve seri port gereksinimleri için [Mac geliştirme notlarına](docs/DEVELOPMENT.md#mac-can-monitor) bak. Mac uygulamasında hız görünür; Android/iOS gösterge ekranlarında hız alanı bilerek sunulmaz.

### iOS test portu

`MyCitroenPort/MyCitroenPort.xcodeproj` Xcode ile açılır. Bu ayrı bir test hedefidir; üretim dağıtımından önce bundle kimlikleri, imza, gizlilik metinleri, uygulama içi aktarım ve gerçek cihaz akışları gözden geçirilmelidir.

## CAN çözümleme güveni

Android/Mac CAN çözücüleri `0x580`, `0x581`, `0x582`, `0x593`, `0x594`, `0x713`, `0x714` kimliklerinden alan çıkarır. Bazı bit eşleşmeleri adaydır; doğrulanmamış alanlar kesin sinyal gibi gösterilmemelidir. Kanıt ve sınırlamalar [`docs/protocol_hypotheses.md`](docs/protocol_hypotheses.md) içinde açıklanır.

## Git ve veri güvenliği

`.gitignore` derleme klasörlerini, imzalı/paketlenmiş uygulamaları, ham BLE/CAN yakalamalarını, GPS yolculuk kayıtlarını, yerel yapılandırmaları ve iç içe upstream `.git` metadata’sını dışarıda tutar. Ham araç kayıtları VIN/cihaz/GPS benzeri tanımlayıcılar içerebilir; önce kişisel veriyi ayıklamadan eklemeyin. Yayın APK/IPA/bin dosyalarını Git geçmişine eklemek yerine sürümlü GitHub Release’e koyun.
