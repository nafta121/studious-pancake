# Changelog — Incremental Traffic: Karesidenan Madiun (Android Edition)

Seluruh perubahan penting pada rilis APK Android (`id.madiun.incrementaltraffic`) didokumentasikan dalam berkas ini.

## 🔐 Jaminan Kontinuitas Sertifikat Penandatanganan APK (*Signing Certificate Continuity*)

Agar pengguna Android dapat melakukan **pembaruan langsung (*in-place update* / `adb install -r`)** tanpa perlu menghapus instalasi lama atau kehilangan data simpanan permainan (`user://save_<map_id>.json`), seluruh rilis mulai `v1.1.0-madiun` hingga `v1.2.0-madiun` dan rilis-rilis berikutnya dikunci menggunakan *keystore* rilis tetap (`signing/madiun_godot_release.keystore`) dengan validasi otomatis pada [`scripts/build_android_apk.sh`](scripts/build_android_apk.sh):

| Atribut Sertifikat | Nilai Terkunci |
| :--- | :--- |
| **Package Name** | `id.madiun.incrementaltraffic` |
| **Keystore Alias** | `madiunrelease` (RSA-2048, APK Signature Scheme v2 + v3) |
| **Subject / Issuer DN** | `CN=Incremental Traffic Karesidenan Madiun, OU=Mobile Game, O=Madiun Open GIS, L=Madiun, ST=Jawa Timur, C=ID` |
| **Certificate Serial Number** | `5071a11bb51cc4dc` |
| **Certificate SHA-256 Digest** | `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce` |
| **Certificate SHA-1 Digest** | `4a10248317724b7f363d92c9874c5c521ef98808` |
| **Masa Berlaku** | `2026-11-13` s/d `2054-03-31` |

> **Catatan Pembaruan**: Jika Anda sebelumnya memasang `v1.1.0-madiun`, Anda dapat langsung mengunduh dan memasang `v1.2.0-madiun` di atasnya tanpa *uninstall*. (Khusus pengguna awal `v1.0.0-madiun` yang masih memakai sertifikat purwarupa `7b29a431...`, cukup lakukan *uninstall* satu kali sebelum memasang `v1.2.0-madiun`; untuk semua versi berikutnya pembaruan berjalan otomatis).

---

## [`v1.2.0-madiun`] — `versionCode: 120`

- **Berkas APK**: [`incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`27.980.757 byte` / `26,7 MB`, `arm64-v8a`, Android 7.0+ `minSdk: 24`)
- **APK SHA-256**: `485f4684edde0bf958de000b8363d8a13d8303519f755ed997d89ba904bff797`
- **Certificate Serial / SHA-256**: `5071a11bb51cc4dc` / `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce` (identik dengan `v1.1.0-madiun`)

### ✨ Fitur Baru & Peningkatan Grafis Jalan/Simpang/Bundaran
- **Alur Jalan Dunia Nyata OSRM / OpenStreetMap (`scripts/fetch_osrm_madiun_roads.py` & `scripts/build_madiun_geodata.py`)**:
  - Mengambil **194 koridor jalan nyata WGS84** untuk seluruh **7 peta Karesidenan Madiun** (`karisidenan_madiun`, `kota_madiun`, `kab_madiun`, `kab_magetan`, `kab_ngawi`, `kab_ponorogo`, `kab_pacitan`).
  - Menambahkan pembersihan *GPS micro-hooks* & putaran balik jalan satu arah (*one-way U-turn overshoots*), penjagaan jarak aman terhadap simpang lain, pemisahan sudut lengan simpang minimal `25°`, relaksasi sudut tajam, serta penghalusan kurva **Chaikin B-spline 3-tahap** ($C^1$ mulus dengan sudut belok per simpul `≤ 33,3°`).
  - Mendeteksi secara geometris **62 bentang jembatan sungai nyata (`bridgeSpans`)** (Kali Bengawan Solo, Kali Madiun, Kali Gandong, Kali Grindulu) dan **6 *overpass* tak sebidang (`overpassSpans`)**.
- **Arsitektur `RoadBed` & Simpang Bezier Monolitik Asli *Incremental Traffic* (`road_geom.gd`, `tri_batch.gd`, `map_view_25d.gd`)**:
  - Mengganti segmen polilin terpisah dengan ekstrusi *triangle strip* kontinu ber-*miter-clamp* (`TriBatch2D.add_smooth_strip`, `stretch ≤ 2.0`) setara `TriBatch` asli *Incremental Traffic* — menghapus gelembung sambungan segmen dan memangkas jumlah segitiga jalan di GPU Android hingga `~4×`.
  - Membentuk poligon simpang lengkung Bezier cekung (`swept_sidewalk`, `swept_curb`, `swept_asphalt`) beserta pemotongan ujung jalan presisi (`trimStart`, `trimEnd`) sehingga trotoar `#E2DED2`, bahu `#A9A59B`, dan aspal `#3C3F4A` menyatu mulus tanpa garis sambungan maupun duri sudut lancip.
- **Bundaran 1-Lajur (`roundabout`) & 2-Lajur (`roundabout2`) Autentik**:
  - Menambahkan pulau tengah taman hijau (`#6E9953`), *stone curb* (`#ACA79B`), *paved truck apron* (`#EAE6DA`), tugu monumen / pepohonan, *flare* mulut bundaran, pulau pemisah segitiga (*splitter islands*), cincin marka putus-putus konsentris pada bundaran 2 lajur, dan sirkulasi searah jarum jam standar jalur kiri Indonesia (*Left-Hand Traffic*).
- **Jembatan Sungai *Update 1.9* & *Overpass***:
  - Merender pilar batu tepi sungai (*abutment piers*) & pilar tengah sungai lebar, lantai trotoar beton jembatan, dinding parapet putih di sisi kiri-kanan, serta bayangan permukaan air khusus di atas bentang penyeberangan sungai.
- **Marka `RoadPaint`, Sinyal Sudut, Pita Konektor Lajur & Lintasan Truk Gandeng (`sim_engine.gd`, `rule_hints.gdshader`)**:
  - Marka median ganda + arsiran *gore chevron* menjelang lampu lalu lintas, pembagi lajur putus-putus yang berubah utuh sebelum simpang, jalan taman pedestrian ber-*bollard* merah-putih saat jalan ditutup (*Close street*), *stop bar* putih & gigi hiu *yield* khusus lajur masuk + rambu segitiga *Yield* di bahu jalan, serta panah arah lajur (`←`, `↑`, `→`).
  - Cakram lampu lalu lintas merah/hijau di sudut luar bahu jalan tiap lengan masuk, shader asli `shaders/rule_hints.gdshader`, serta cincin inspeksi biru + pita konektor belokan berwarna transparan (*Steam Update 1.7 style*) saat simpang dipilih.
  - Pergerakan truk dan 1–3 gandengan (*articulated trailers*) mengikuti kurva belok Bezier simpang dan orbit melingkar bundaran secara kontinu, lengkap dengan antrean rapi di belakang garis henti `stop_s` dan fase lampu hijau simultan untuk lengan berhadapan.

### 🐛 Perbaikan Bug & Infrastruktur Rilis
- Memperbaiki *key lookup* pita aliran komoditas (`Goods Flow` Sankey overlay `"%s->%s->%s"`) sehingga label laju `X/min` tampil akurat di mode siang maupun malam.
- Memperbarui *callback* toggle *Left-Hand Traffic* di `android_hud.gd` agar langsung membangun ulang geometri simpang, bundaran, dan kurva belok.
- Mengunci *keystore* rilis di `signing/madiun_godot_release.keystore` dengan pemeriksaan sidik jari sertifikat otomatis pada `scripts/build_android_apk.sh`.

---

## [`v1.1.0-madiun`] — `versionCode: 110`

- **APK SHA-256**: `51e4e8c326872ba633bbf86bf0a109a438e2ac71391d0474b62211e74ef54081`
- **Certificate Serial / SHA-256**: `5071a11bb51cc4dc` / `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce`
- Integrasi penuh tema asli `"Sticker"` terang & gelap (`gui/theme.tres`, `gui/theme_dark.tres`), font `Jost-Variable.ttf`, `icon.svg` Adaptive Icon, `title_logo.png`, 26 efek suara UI WAV asli (`sounds/ui/*.wav`), pustaka 44 bentuk komoditas `ItIcons`, HUD 5-zona (`MoneyDisplay` + `TownCrest`, `GoalsPanel`, `RuleToolbar`, `FactoryPanel`, modal `Overview` bergrafik kas 5 menit, `OverlayBar`, `DayClock`, `SpeedControls`), dan skala DPI responsif Landscape/Portrait.

---

## [`v1.0.0-madiun`] — `versionCode: 100`

- Rilis awal port Android berbasis **Godot Engine 4.7.2 (`gl_compatibility`)** dengan **7 peta dunia nyata eks-Karesidenan Madiun** (`karisidenan_madiun`, `kota_madiun`, `kab_madiun`, `kab_magetan`, `kab_ngawi`, `kab_ponorogo`, `kab_pacitan`), simulasi mikro-agen 30 Hz, *GPU static triangle batching* (`TriBatch2D`), kamera sentuh *pinch-zoom*, dan manajemen siklus hidup baterai Android (30/60/120 FPS).
