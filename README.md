# Incremental Traffic: Karesidenan Madiun (Godot 4.7.2 Android Edition — v1.3.0)

Simulasi rekayasa lalu lintas mikro-agen dan logistik rantai pasok **2.5D** menggunakan **Godot Engine 4.7.2 (`gl_compatibility` Mobile Renderer)** yang mengambil langsung **7 Shader Asli (`city_building`, `city_reveal`, `city_shadow`, `cloud_puff`, `rule_hints`, `water_ripples`, `leaning_roof`), Seluruh 44 Komoditas & Ekonomi `simcore` Asli, Geometri Jalan (`RoadBed` & `RoadPaint`), Simpang Bezier Monolitik, Bundaran 1/2 Lajur, Lampu Lalu Lintas Multi-Fase, Gudang Stasiun/Pelabuhan *Update 1.10*, Tema `"Sticker"`, Font, Ikon Vektor, Logo, dan 26 Efek Suara Asli *Incremental Traffic***, dipadukan dengan **alur jalan dunia nyata (OSRM / OpenStreetMap WGS84)** di seluruh **6 Kota & Kabupaten eks-Karesidenan Madiun, Jawa Timur**, serta optimalisasi penuh **60–120 FPS bebas kebocoran memori** untuk perangkat **Android**.

---

## 📱 Unduh & Instalasi APK Android (`v1.3.0-madiun`)

File APK rilis yang telah ditandatangani secara kriptografis (**APK Signature Scheme v1 + v2 + v3**, arsitektur `arm64-v8a`) tersedia langsung di repositori ini:

- **GitHub Releases**: [`v1.3.0-madiun`](https://github.com/nafta121/studious-pancake/releases/tag/v1.3.0-madiun) · Riwayat lengkap di [`CHANGELOG.md`](CHANGELOG.md)
- **Lokasi File APK**: [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`26,8 MB` / `28.058.991 byte`)
- **Package ID**: `id.madiun.incrementaltraffic`
- **Versi**: `1.3.0-madiun` (`versionCode: 130` — mendukung *in-place update* langsung di atas `v1.1.0-madiun` & `v1.2.0-madiun` tanpa menghapus data simpanan)
- **Engine**: Godot Engine `4.7.2.stable` (Compiled GDScript Bytecode `.gdc`, GLES3 Mobile, `0` Script/Shader Error, `0` Leaked Resources)
- **APK File SHA-256**: `1318a7ad8349682b0bbe45ab01ea09544761dd1fdc8dbacacc2a965b8812831a`
- **Signing Certificate Continuity** (`signing/madiun_godot_release.keystore`):
  - **Certificate Serial Number**: `5071a11bb51cc4dc`
  - **Certificate SHA-256 Digest**: `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce`
  - **Certificate SHA-1 Digest**: `4a10248317724b7f363d92c9874c5c521ef98808`
  - **Validitas**: `2026-11-13` s/d `2054-03-31`

### Cara Memasang / Memperbarui (*Update*) di Perangkat Android:
1. Unduh `incremental-traffic-madiun-android.apk` dari halaman [**GitHub Releases `v1.3.0-madiun`**](https://github.com/nafta121/studious-pancake/releases/tag/v1.3.0-madiun) atau [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk), lalu pasang langsung di atas versi sebelumnya (tanpa *uninstall* agar progres `save_<map_id>.json` tetap tersimpan), atau melalui ADB:
   ```bash
   adb install -r releases/incremental-traffic-madiun-android.apk
   ```
2. Game mendukung **Auto-Rotation (Landscape `1152×648` & Portrait `480×960` DPI-adaptive)**, *edge-to-edge immersive mode*, kamera sentuh *2-finger pinch-zoom* + *inertial pan* + *double-tap zoom*, serta navigasi tombol fisik/gestur **Back** bawaan Android.

---

## 🔬 Pembaruan `v1.3.0`: Audit Menyeluruh & Paritas Penuh File Asli *Incremental Traffic* (REA)

1. **Seluruh 44 Komoditas Asli & Ekonomi `Ledger`/`Industry` Presisi (`godot_src/core/catalog.gd`, `godot_src/core/sim_engine.gd`)**:
   - Lengkap **44 bentuk komoditas** (`3` Raw Tier-1 + `9` Tier-2 + `11` Tier-3 + `9` Tier-4 + `12` Tier-5 seperti `Rocket`, `Star`, `Crown`, `Key`, `Heart`, `Spade`) dengan konservasi nilai bahan baku `$50` per input mentah (`validate_catalog()` tervalidasi `0` galat).
   - Formula harga jual kembali truk marginal asli (`50%` dari harga beli marginal ke-$N$), faktor jadwal tunggu `[1.0, 0.6, 0.3, 0.0]`, kapasitas `Low-loader` `3` slot `large`, biaya `Bays` eksponensial `$500 * 2^level`, syarat pembukaan `Expand` pada `rate >= 10 / min`, serta batas tunggu `Full load` `20 detik` bebas *deadlock*.
2. **7 Shader Asli *Incremental Traffic* Berjalan Mulus di Android GLES3 (`shaders/`, `godot_src/render/map_view_25d.gd`)**:
   - `city_building.gdshader` + `city_reveal.gdshaderinc`: Bangunan kota 2.5D beratap limas dengan animasi *pop* gelombang pembukaan wilayah dan kilau pertumbuhan saat pabrik naik level (`CUSTOM0`).
   - `city_shadow.gdshader` & `cloud_puff.gdshader`: Bayangan bangunan terarah dan bayangan awan lembut mengambang melintasi lanskap Madiun.
   - `rule_hints.gdshader` & `water_ripples.gdshader`: Cincin & garis petunjuk aturan berdenyut melalui `MeshInstance2D` (bebas artefak alpha berlapis) serta riak arus Kali Bengawan Solo, Kali Madiun, dan Samudra Hindia Pacitan.
3. **Gudang Penumpukan `yardPile` Stasiun (`2.0×`) & Pelabuhan (`1.6×`) (*Steam Update 1.10*)**:
   - Pembayaran instan saat truk membongkar muatan di Stasiun Kereta Api maupun Pelabuhan Samudra Tamperan, dengan tumpukan kargo visual di halaman peron/dermaga yang diangkut bertahap oleh rangkaian kereta dan kapal kargo.
4. **Lampu Lalu Lintas Multi-Fase (`2–4` Fase), Masker Belok Lajur & Prioritas `Yield` *Update 1.9***:
   - Pengaturan `2–4` fase hijau (`3s–40s`), izin belok `Left / Straight / Right` per lengan per fase, validasi rute otomatis di `RoutePathfinder`, sensor adaptif *gap-out* `3,0 detik`, rotasi jalan utama pada simpang `Yield` tanpa menahan arus mayor, serta penambahan/pengurangan lajur terarah (`Both / Fwd / Back`), kantong belok (*turn pocket*), dan panah lajur kustom.
5. **UI/UX Lengkap & Bebas Kebocoran Resource (`0` Leak pada Godot 4.7.2)**:
   - Urutan `RuleToolbar` 6-alat autentik (`Yield`, `Roundabout`, `Lights`, `Lanes`, `One-way`, `Roads`), lampu rem & sein truk, bilah sisa bonus waktu *Express*, opsi `Same way back` pada rute, tab `Alerts (N)` di `Overview`, opsi `Hide Flyovers`, mode aksesibilitas buta warna Okabe-Ito (`Colour-blind`), `Cloud Shadows`, serta kontrol volume `Master / UI / Delivery` dengan *teardown* memori bersih `100%`.

---

## 🛣️ Geometri Jalan Dunia Nyata OSRM, Simpang Bezier, Bundaran & Jembatan

- **194 Koridor Jalan Nyata WGS84 (OSRM / OpenStreetMap)** di 7 peta Karesidenan Madiun dengan penghalusan kurva **Chaikin B-spline 3-tahap** ($\le 33,3^\circ$) serta **62 bentang jembatan sungai nyata (`bridgeSpans`)** dan **6 *overpass* (`overpassSpans`)** yang dapat disembunyikan lewat opsi `Hide Flyovers`.
- **Ekstrusi `RoadBed` Ber-*Miter-Clamp* (`TriBatch2D`)**, simpang lengkung Bezier monolitik bebas sambungan, bundaran 1/2 lajur searah jarum jam standar jalur kiri Indonesia (*Left-Hand Traffic*), serta lintasan kontinu untuk truk beserta 1–3 gandengan (*articulated trailers*).

---

## 🗺️ 7 Peta Dunia Nyata Karesidenan Madiun (Geometri OSRM + WGS84)

| ID Peta | Nama Peta | Cakupan Geografis & Infrastruktur Nyata |
| :--- | :--- | :--- |
| `karisidenan_madiun` | **Karesidenan Madiun Terpadu** | Kampanye penuh **6 Wilayah Progresif** (47 simpang, 65 ruas jalan OSRM, 23 jembatan sungai, 31 fasilitas, Kali Bengawan Solo, Kali Madiun, Kali Gandong, Kali Grindulu, Jalur KA Lintas Selatan, Tol Trans-Jawa & JLS). |
| `kota_madiun` | **Kota Madiun (27 Kelurahan)** | Detail mikro perkotaan di **Kec. Kartoharjo, Manguharjo & Taman**: Tugu 0 KM Jl. Pahlawan, Stasiun Besar Madiun & kawasan industri kereta api, PG Rejo Agung, Pasar Besar, Bundaran Sleko, 9 jembatan Kali Madiun, Ring Road Barat & Timur. |
| `kab_madiun` | **Kabupaten Madiun (Poros Caruban)** | Ibu kota Caruban (Mejayan), Bundaran Gerbang Tol Dumpil, Hutan Jati Alas Saradan, koridor selatan Pagotan–Geger–Dolopo, hingga perkebunan lereng Gunung Wilis (Wungu & Kare). |
| `kab_magetan` | **Kabupaten Magetan (Kaki Gunung Lawu)** | Simpang Tiga Maospati, Stasiun Kargo Barat, Bundaran Kota Magetan, sentra kerajinan kulit, hingga tanjakan Plaosan & Telaga Sarangan di lereng Gunung Lawu. |
| `kab_ngawi` | **Kabupaten Ngawi (Tempuran Bengawan Solo)** | Tugu Kartonyono & Benteng Pendem (pertemuan Kali Madiun & Bengawan Solo), 8 jembatan sungai besar, lumbung pangan Geneng–Paron, koridor Karangjati, hingga Stasiun Walikukun, Kebun Teh Jamus & Mantingan. |
| `kab_ponorogo` | **Kabupaten Ponorogo (Bumi Reog)** | Bundaran Alun-Alun Ponorogo, persimpangan barat Sumoroto–Badegan, sentra industri Dengok–Jetis–Balong, gerbang selatan Slahung, dan kawasan Telaga Ngebel–Pulung. |
| `kab_pacitan` | **Kabupaten Pacitan (Teluk & JLS Selatan)** | Teluk Pacitan & Samudra Hindia, **Pelabuhan Samudra Tamperan** (ekspor maritim *Harbour* + `yardPile`), jembatan muara Kali Grindulu, Pegunungan Kars Gunungsewu (Punung–Donorojo), dan **Jalur Lintas Selatan (JLS)** hingga Tulakan–Ngadirojo. |

---

## 🛠️ Struktur Proyek & Cara Build Mandiri

```text
├── project.godot                     # Konfigurasi Godot 4.7.2 (v1.3.0, gl_compatibility, Sticker theme)
├── export_presets.cfg                # Preset ekspor APK Android v1.3.0-madiun (versionCode 130, arm64-v8a)
├── icon.svg                          # Ikon vektor asli Incremental Traffic
├── assets/
│   ├── icons/                        # Android Adaptive Icons (192x192 & 432x432 safe-zone)
│   └── ui/title_logo.png             # Logo judul asli Incremental Traffic
├── gui/
│   ├── theme.tres                    # Tema UI asli "Sticker" (Terang)
│   ├── theme_dark.tres               # Tema UI asli "Sticker" (Gelap / Malam)
│   └── theme_studies/fonts/          # Font asli Jost-Variable.ttf
├── sounds/ui/                        # 26 file efek suara UI WAV asli Incremental Traffic
├── shaders/                          # 7 shader asli (city_building, city_reveal, city_shadow, cloud_puff, rule_hints, water_ripples, leaning_roof)
├── godot_src/
│   ├── main_game.gd                  # Orkestrator utama, input dunia, siklus hidup Android & zero-leak smoke test
│   ├── core/                         # catalog.gd (44 goods), road_geom.gd, pathfinder.gd (turn masks), sfx_synth.gd, sim_engine.gd
│   ├── render/                       # tri_batch.gd (CUSTOM0 + MeshInstance2D), map_view_25d.gd (2.5D shaders, yardPile, signals)
│   └── ui/                           # it_icons.gd (44 glyphs), touch_camera.gd, android_hud.gd (6-tool RuleToolbar, multi-phase UI)
├── geodata/                          # Data batas wilayah, sungai & cache koridor jalan OSRM Karesidenan Madiun
├── data/madiun_maps.json             # Paket 7 peta dunia nyata siap pakai (194 jalan OSRM, 62 jembatan, 44 komoditas)
├── scripts/
│   ├── fetch_osrm_madiun_roads.py    # Pengambil polilin jalan nyata WGS84 dari OSRM / OpenStreetMap
│   ├── build_madiun_geodata.py       # Kompilator geometri OSRM + Chaikin B-spline + resep 44 komoditas
│   └── build_android_apk.sh          # Skrip ekspor & penandatanganan APK Godot 4.7.2 otomatis (sertifikat terkunci)
└── releases/
    └── incremental-traffic-madiun-android.apk
```

### Menjalankan Build APK Secara Lokal:
```bash
bash scripts/build_android_apk.sh
```

---

## 🔍 Verifikasi Paket APK dengan REA (`rea-agents` + `JADX 0.7.1`)

File [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`SHA-256: 1318a7ad8349682b0bbe45ab01ea09544761dd1fdc8dbacacc2a965b8812831a`, `28.058.991 byte`) telah diverifikasi secara statis menggunakan **REA**:

| Operasi REA | Evidence ID | Temuan Terverifikasi (*Observed*) |
| :--- | :--- | :--- |
| `inspect-apk-signature` | `ev_501a740cb1ff9cf0423b96380cbed83a699ac20259790e88c341d2c22b6a7201` | Skema tanda tangan **v1 (`MADIUNRE.RSA`), v2, dan v3** lengkap dan terverifikasi oleh `apksigner verify` dengan sidik jari sertifikat tetap `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce` (`Serial: 5071a11bb51cc4dc`). |
| `inspect-artifact` | `ev_f3ace6287e6a38b66855a1deadc045e415d9ec2e1fb16dd38be53c06dce9bfdd` | Graf & inventori artefak utuh (`197` entri APK termasuk seluruh `7` shader `.gdshader`/`.gdshaderinc`, `.gdc` terkompilasi, `Jost-Variable.ttf`, `theme.tres`, `theme_dark.tres`, `26` WAV UI & `madiun_maps.json`, `0` kontradiksi; manifes `agm_cb7b75ae784d93cdf774f5dc34923ba7b4251a5dca80c3d1d281d25fd717701d`). |
| `inspect-android-package` | `ev_bf58808b5fe88805e2894cec25e0bf0e7523b16d011f40c19b0032920a14dba0` | `id.madiun.incrementaltraffic`, `versionCode: 130`, `1.3.0-madiun`, `minSdk: 24` (Android 7.0+), `targetSdk: 36`, `glEsVersion: 0x30000`, izin minimal `android.permission.VIBRATE`. |
