# Changelog — Incremental Traffic: Karesidenan Madiun (Android Edition)

Seluruh perubahan penting pada rilis APK Android (`id.madiun.incrementaltraffic`) didokumentasikan dalam berkas ini.

## 🔐 Jaminan Kontinuitas Sertifikat Penandatanganan APK (*Signing Certificate Continuity*)

Agar pengguna Android dapat melakukan **pembaruan langsung (*in-place update* / `adb install -r`)** tanpa perlu menghapus instalasi lama atau kehilangan data simpanan permainan (`user://save_<map_id>.json`), seluruh rilis mulai `v1.1.0-madiun`, `v1.2.0-madiun`, hingga `v1.3.0-madiun` dan rilis-rilis berikutnya dikunci menggunakan *keystore* rilis tetap (`signing/madiun_godot_release.keystore`) dengan validasi otomatis pada [`scripts/build_android_apk.sh`](scripts/build_android_apk.sh):

| Atribut Sertifikat | Nilai Terkunci |
| :--- | :--- |
| **Package Name** | `id.madiun.incrementaltraffic` |
| **Keystore Alias** | `madiunrelease` (RSA-2048, APK Signature Scheme v1 + v2 + v3) |
| **Subject / Issuer DN** | `CN=Incremental Traffic Karesidenan Madiun, OU=Mobile Game, O=Madiun Open GIS, L=Madiun, ST=Jawa Timur, C=ID` |
| **Certificate Serial Number** | `5071a11bb51cc4dc` |
| **Certificate SHA-256 Digest** | `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce` |
| **Certificate SHA-1 Digest** | `4a10248317724b7f363d92c9874c5c521ef98808` |
| **Masa Berlaku** | `2026-11-13` s/d `2054-03-31` |

> **Catatan Pembaruan**: Jika Anda sebelumnya memasang `v1.1.0-madiun` atau `v1.2.0-madiun`, Anda dapat langsung mengunduh dan memasang `v1.3.0-madiun` di atasnya tanpa *uninstall*.

---

## [`v1.3.0-madiun`] — `versionCode: 130`

- **Berkas APK**: [`incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`28.058.991 byte` / `26,8 MB`, `arm64-v8a`, Android 7.0+ `minSdk: 24`, `197` berkas terpaket)
- **APK SHA-256**: `1318a7ad8349682b0bbe45ab01ea09544761dd1fdc8dbacacc2a965b8812831a`
- **Certificate Serial / SHA-256**: `5071a11bb51cc4dc` / `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce` (identik dengan `v1.1.0-madiun` & `v1.2.0-madiun`)

### 🐛 Hasil Audit Menyeluruh & Perbaikan Bug/Error (`v1.3.0`)
1. **Eliminasi Total Kebocoran Resource & ObjectDB Saat Keluar (`sfx_synth.gd`, `map_view_25d.gd`, `android_hud.gd`, `main_game.gd`)**:
   - Memperbaiki kebocoran `26 AudioStreamWAV`, `AudioStreamPlaybackWAV`, `ArrayMesh` RID, dan `ShaderMaterial` saat aplikasi ditutup dengan menambahkan metode `SfxSynth.shutdown()` + pemutusan sinyal `SceneTree.node_added` serta pembersihan `_exit_tree()` deterministik (**terverifikasi `0` *leaked ObjectDB instances* dan `0` *resources in use at exit* pada Godot 4.7.2 `--verbose`**).
2. **Perbaikan Fallback Nama Komoditas Tidak Valid `"grain"` (`map_view_25d.gd`)**:
   - Mengganti fallback string lama `"grain"` (yang tidak terdaftar di `GameCatalog.GOODS`) menjadi `"dot"` pada render muatan truk dan pita aliran barang.
3. **Perbaikan Formula Harga Jual Kembali Truk Marginal (`catalog.gd`, `sim_engine.gd`)**:
   - Mengganti rumus rata-rata total armada lama menjadi rumus `Ledger.gd` asli (`50%` dari harga beli marginal truk ke-$N$: `base_cost * 1.12^(N-1) * 0.5`), menghapus celah eksploitasi harga jual-beli truk.
4. **Perbaikan Faktor `TIMETABLE_WAIT_FACTORS` & Kapasitas `Low-loader` (`catalog.gd`)**:
   - Menyelaraskan faktor tunggu jadwal ke nilai asli `[1.0, 0.6, 0.3, 0.0]` dan memperbaiki kapasitas `slot_cap` truk berat `Low-loader` menjadi `3` slot komoditas `large` (`max_speed: 62 px/s`).
5. **Perbaikan Biaya Upgrade `Bays` & Prasyarat `Expand` (`sim_engine.gd`)**:
   - Menyelaraskan harga upgrade `Bays` ke formula eksponensial asli `$500 * 2^level` (`$500`, `$1.000`, `$2.000`, ...) dan mengunci tombol `Expand` hingga laju produksi mencapai `>= 10.0 / min` seperti di `Industry` C# asli.
6. **Perbaikan Perhitungan Laju Pengiriman Global pada `GoalsPanel` (`sim_engine.gd`)**:
   - Memastikan `get_global_delivery_rate_per_min()` hanya menghitung pengiriman akhir ke hub pasar konsumen (`market`, `station`, `harbour`) dan tidak menghitung ganda pengiriman bahan setengah jadi antar-pabrik.
7. **Perbaikan Batas Tunggu Pemuatan `MAX_LOAD_WAIT_SEC` & Prioritas Jalan Utama `Yield` (`sim_engine.gd`)**:
   - Menambahkan batas tunggu maksimum `20,0 detik` untuk mode `Full load` (agar truk dengan muatan parsial tetap berangkat dan tidak memicu kebuntuan rantai pasok) serta membebaskan kendaraan di jalan utama mayor pada simpang `Yield` agar melaju kecepatan penuh tanpa tertahan antrean lengan minor (*Update 1.9*).
8. **Perbaikan Ekspor `.gdshaderinc` & Tata Letak Header Modal `Overview` (`export_presets.cfg`, `android_hud.gd`)**:
   - Menambahkan `shaders/*.gdshaderinc` ke `include_filter` ekspor APK agar `#include "res://shaders/city_reveal.gdshaderinc"` selalu terpaket utuh di Android, serta merapikan rasio lebar label ringkasan kas/armada di modal `Overview` agar tidak pernah terpotong tombol tutup `×`.

### ✨ Peningkatan Paritas Penuh dari File Asli *Incremental Traffic* (REA Upgrade)
1. **Seluruh 44 Komoditas Asli (`3` Raw + `9` Tier-2 + `11` Tier-3 + `9` Tier-4 + `12` Tier-5) (`catalog.gd`, `build_madiun_geodata.py`)**:
   - Mengimplementasikan ke-44 komoditas asli dengan konservasi nilai bahan baku `$50` per input mentah (`validate_catalog()` lolos `0` galat), penamaan proses autentik (`Press`, `Cut`, `Assembly`), serta target *Boomtown* komoditas tingkat tinggi (`Rocket`, `Star`, `Crown`, `Key`, `Heart`, `Spade`, dll.) di seluruh 7 peta Karesidenan Madiun.
2. **Pipeline 7 Shader Asli *Incremental Traffic* di `gl_compatibility` (`shaders/`, `tri_batch.gd`, `map_view_25d.gd`)**:
   - Mengintegrasikan langsung `city_building.gdshader` + `city_reveal.gdshaderinc` (ekstrusi bangunan 2.5D beratap limas + animasi pop gelombang pembukaan wilayah + kilau pertumbuhan pabrik `CUSTOM0`), `city_shadow.gdshader` (bayangan jatuh terarah), `leaning_roof.gdshader`, `cloud_puff.gdshader` (bayangan awan lembut mengambang), `rule_hints.gdshader` (cincin & garis putus-putus berdenyut tanpa tumpang-tindih alpha melalui `MeshInstance2D`), dan `water_ripples.gdshader` (riak sungai & laut berarah).
3. **Gudang Penumpukan On-Site `yardPile` Stasiun (`2.0×`) & Pelabuhan (`1.6×`) (*Steam Update 1.10*) (`sim_engine.gd`, `map_view_25d.gd`, `android_hud.gd`)**:
   - Pengiriman komoditas ke Stasiun Kereta Api maupun Pelabuhan Samudra Tamperan kini membayar penuh secara instan (`2.0×` / `1.6×`), menumpuk kargo secara visual di halaman peron/dermaga (`yardPile`), dan dimuat bertahap saat rangkaian kereta/kapal kargo bersandar.
4. **Lampu Lalu Lintas Multi-Fase (`2–4` Fase) + Masker Belok per Lengan + Sensor Celah (*Gap-Out*) (`sim_engine.gd`, `pathfinder.gd`, `android_hud.gd`)**:
   - Mendukung penambahan/penghapusan hingga `4` fase lampu hijau (`3s–40s`), pengaturan izin arah belok per lengan per fase (`Left`, `Straight`, `Right`), validasi rute otomatis di `RoutePathfinder`, sensor adaptif pemotong fase kosong setelah `3,0 detik`, serta rotasi jalan utama pada simpang `Yield`.
5. **Toolbar 6-Alat Asli, Modifikasi Lajur Terarah, Kantong Belok & Panah Kustom (`android_hud.gd`, `sim_engine.gd`, `map_view_25d.gd`)**:
   - Menyelaraskan urutan `RuleToolbar` ke versi asli (`Yield`, `Roundabout`, `Lights`, `Lanes`, `One-way`, `Roads`) beserta subbar `Lanes` (`+ Lane`, `− Lane`, `Pocket`, `Arrows`, `Close`, dan pemilih arah `Dir: Both / Fwd / Back`), pratinjau jumlah rute terputus saat menutup jalan, lampu rem & sein truk gandeng, bilah sisa bonus waktu truk *Express*, opsi `Same way back` pada rute, tab `Alerts (N)` di `Overview`, serta pengaturan lengkap (`Hide Flyovers`, mode buta warna Okabe-Ito `Colour-blind`, `Cloud Shadows`, dan penggeser volume `Master` / `UI` / `Delivery`).

---

## [`v1.2.0-madiun`] — `versionCode: 120`

- **Berkas APK**: `incremental-traffic-madiun-android.apk` (`27.980.757 byte` / `26,7 MB`, `arm64-v8a`, Android 7.0+ `minSdk: 24`)
- **APK SHA-256**: `485f4684edde0bf958de000b8363d8a13d8303519f755ed997d89ba904bff797`
- **Certificate Serial / SHA-256**: `5071a11bb51cc4dc` / `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce`
- Alur jalan dunia nyata OSRM / OpenStreetMap (`194` koridor WGS84 + Chaikin B-spline 3-tahap + `62` jembatan sungai nyata), `RoadBed` ber-*miter-clamp*, simpang Bezier monolitik, bundaran 1/2 lajur autentik, dan jembatan sungai *Update 1.9*.

---

## [`v1.1.0-madiun`] — `versionCode: 110`

- **APK SHA-256**: `51e4e8c326872ba633bbf86bf0a109a438e2ac71391d0474b62211e74ef54081`
- **Certificate Serial / SHA-256**: `5071a11bb51cc4dc` / `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce`
- Integrasi penuh tema asli `"Sticker"` terang & gelap (`gui/theme.tres`, `gui/theme_dark.tres`), font `Jost-Variable.ttf`, `icon.svg` Adaptive Icon, `title_logo.png`, 26 efek suara UI WAV asli (`sounds/ui/*.wav`), dan HUD 5-zona responsif Landscape/Portrait.

---

## [`v1.0.0-madiun`] — `versionCode: 100`

- Rilis awal port Android berbasis **Godot Engine 4.7.2 (`gl_compatibility`)** dengan **7 peta dunia nyata eks-Karesidenan Madiun**, simulasi mikro-agen 30 Hz, *GPU static triangle batching*, kamera sentuh *pinch-zoom*, dan manajemen siklus hidup baterai Android (30/60/120 FPS).
