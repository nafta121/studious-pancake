# Incremental Traffic: Karesidenan Madiun (Godot 4.7.2 Android Edition — v1.4.0)

Simulasi rekayasa lalu lintas mikro-agen dan logistik rantai pasok **2.5D** menggunakan **Godot Engine 4.7.2 (`gl_compatibility` Mobile Renderer)** yang mengambil langsung **10 Berkas Shader Asli (`city_building`, `city_reveal`, `city_shadow`, `city_ground`, `road_verge`, `cloud_puff`, `rule_hints`, `water_ripples`, `leaning_roof`, `extrude_25d`), Arsitektur `Road Shape`, `Road Size` (`1.68×` Lebar Truk) & Polilin Per-Lajur (`SimCore::set_lane`, `RoadBed`, `RoadSurface`, `LaneMarkings`), Seluruh 44 Komoditas & Ekonomi `simcore` Asli, Lampu Lalu Lintas Multi-Fase, Gudang Stasiun/Pelabuhan *Update 1.10*, Tema `"Sticker"`, Font, Ikon Vektor, Logo, dan 26 Efek Suara Asli *Incremental Traffic***, dipadukan dengan **alur jalan dunia nyata (OSRM / OpenStreetMap WGS84)** di seluruh **6 Kota & Kabupaten eks-Karesidenan Madiun, Jawa Timur**, serta optimalisasi penuh **60–120 FPS bebas kebocoran memori** untuk perangkat **Android**.

---

## 📱 Unduh & Instalasi APK Android (`v1.4.0-madiun`)

File APK rilis yang telah ditandatangani secara kriptografis (**APK Signature Scheme v1 + v2 + v3**, arsitektur `arm64-v8a`) tersedia langsung di repositori ini:

- **GitHub Releases**: [`v1.4.0-madiun`](https://github.com/nafta121/studious-pancake/releases/tag/v1.4.0-madiun) · Riwayat lengkap di [`CHANGELOG.md`](CHANGELOG.md)
- **Lokasi File APK**: [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`26,8 MB` / `28.087.908 byte`)
- **Package ID**: `id.madiun.incrementaltraffic`
- **Versi**: `1.4.0-madiun` (`versionCode: 140` — mendukung *in-place update* langsung di atas `v1.1.0-madiun` – `v1.3.0-madiun` tanpa menghapus data simpanan)
- **Engine**: Godot Engine `4.7.2.stable` (Compiled GDScript Bytecode `.gdc`, GLES3 Mobile, `0` Script/Shader Error, `0` Leaked Resources)
- **APK File SHA-256**: `8a9c1dcb7522dcd38e89a7cbdc1b78a1e54c4a9c1c6eb63d0246742b1eab042e`
- **Signing Certificate Continuity** (`signing/madiun_godot_release.keystore`):
  - **Certificate Serial Number**: `5071a11bb51cc4dc`
  - **Certificate SHA-256 Digest**: `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce`
  - **Certificate SHA-1 Digest**: `4a10248317724b7f363d92c9874c5c521ef98808`
  - **Validitas**: `2026-11-13` s/d `2054-03-31`

### Cara Memasang / Memperbarui (*Update*) di Perangkat Android:
1. Unduh `incremental-traffic-madiun-android.apk` dari halaman [**GitHub Releases `v1.4.0-madiun`**](https://github.com/nafta121/studious-pancake/releases/tag/v1.4.0-madiun) atau [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk), lalu pasang langsung di atas versi sebelumnya (tanpa *uninstall* agar progres `save_<map_id>.json` tetap tersimpan), atau melalui ADB:
   ```bash
   adb install -r releases/incremental-traffic-madiun-android.apk
   ```
2. Game mendukung **Auto-Rotation (Landscape `1152×648` & Portrait `480×960` DPI-adaptive)**, *edge-to-edge immersive mode*, kamera sentuh *2-finger pinch-zoom* + *inertial pan* + *double-tap zoom*, serta navigasi tombol fisik/gestur **Back** bawaan Android.

---

## 🛣️ Pembaruan `v1.4.0`: `Road Shape`, `Road Size` & Arsitektur `Lanes` Asli *Incremental Traffic* (REA)

1. **Proporsi Eksak `Road Size` & Rasio `1.68×` Lebar Truk (`godot_src/core/road_geom.gd`)**:
   - Seluruh ukuran jalan diturunkan langsung dari konstanta asli `CONST`, `RoadBed`, `LaneMarkings`, dan `TruckView` (`UNIT_SCALE = 0.20`): `LANE_WIDTH = 6.72` (`33.6 × 0.20`, tepat `1.68×` lebar truk `4.0`), `LANE_SEPARATION = 3.84` (`19.2 × 0.20`), `LANE_SPACING = 6.00` (`30.0 × 0.20`), `SIDEWALK = 1.76`, `CURB = 0.40`, dan `SHADOW_BAND = 1.20`.
2. **Polilin Eksplisit Per-Lajur (`lanesFwd` / `lanesBwd`) & Kantong Belok *Cubic Hermite* (`ramp`)**:
   - Meniru arsitektur `SimCore::set_lane` (`ram:0x180014c40` pada `simcore.windows.x86_64.dll`), setiap lajur (`1–4` sepanjang ruas jalan + `1–4` lajur pendekatan simpang / *turn pockets*) dibangun sebagai polilin mandiri dengan mekarnya kantong belok halus `ramp(a, b, x) = t²(3 - 2t)` serta 3 ukuran panjang kantong asli (`Short = 26.0`, `Medium = 52.0`, `Long = 82.0`).
3. **`RoadBed` 3-Lapis, `RoadSurface.plaza_polygon` Asimetris Bebas Celah & Marka `LaneMarkings` Asli (`godot_src/render/map_view_25d.gd`)**:
   - `RoadBed` 3 cincin konsentris (`Contact Shadow` → `Sidewalk #E2DED2` → `Curb #A9A59B`), poligon simpang `plaza_poly` yang menyatu presisi dari titik ujung lajur aktual (*fillet* Bezier kuadratik 8-segmen `< 145°` & busur Bezier kubik `bend(..., arc=true)` `>= 145°`), pulau bundaran rumput `#C9D8A6` (`COL_GRASS`), garis tengah tunggal `#F2F0E5` putus-putus/utuh, pulau median berarsir diagonal 45° pada `medianZones`, serta panel inspektur jalan `StreetEditor` lengkap (`$1,125` per kantong lajur simpang).
   - Seluruh geometri jalan dikompilasi ke dalam **1 *draw batch* statis `TriBatch2D`** pada GPU ditambah shader tanah asli `road_verge.gdshader` + `city_ground.gdshaderinc` (`FastNoiseLite` `128×128`) untuk performa mulus **60–120 FPS** di Android.

---

## 🔬 Fitur Paritas Penuh File Asli *Incremental Traffic* (`v1.3.0` – `v1.4.0`)

1. **Seluruh 44 Komoditas Asli & Ekonomi `Ledger`/`Industry` Presisi (`godot_src/core/catalog.gd`, `godot_src/core/sim_engine.gd`)**:
   - Lengkap **44 bentuk komoditas** (`3` Raw Tier-1 + `9` Tier-2 + `11` Tier-3 + `9` Tier-4 + `12` Tier-5 seperti `Rocket`, `Star`, `Crown`, `Key`, `Heart`, `Spade`) dengan konservasi nilai bahan baku `$50` per input mentah (`validate_catalog()` tervalidasi `0` galat), harga jual kembali truk marginal `50%`, faktor jadwal tunggu `[1.0, 0.6, 0.3, 0.0]`, kapasitas `Low-loader` `3` slot `large`, dan biaya `Bays` eksponensial `$500 * 2^level`.
2. **10 Berkas Shader Asli *Incremental Traffic* Berjalan Mulus di Android GLES3 (`shaders/`, `godot_src/render/map_view_25d.gd`)**:
   - `city_ground.gdshaderinc`, `city_ground.gdshader`, & `road_verge.gdshader`: Tekstur padang rumput/pasir/butir halus prosedural dunia nyata.
   - `city_building.gdshader` + `city_reveal.gdshaderinc`, `city_shadow.gdshader`, `leaning_roof.gdshader`, `cloud_puff.gdshader`, `rule_hints.gdshader`, & `water_ripples.gdshader`.
3. **Gudang Penumpukan `yardPile` Stasiun (`2.0×`) & Pelabuhan (`1.6×`) (*Steam Update 1.10*)**, **Lampu Lalu Lintas Multi-Fase (`2–4` Fase)**, serta **194 Koridor Jalan Nyata WGS84 (OSRM / OpenStreetMap)** + **62 jembatan sungai nyata (`bridgeSpans`)**.

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
├── project.godot                     # Konfigurasi Godot 4.7.2 (v1.4.0, gl_compatibility, Sticker theme)
├── export_presets.cfg                # Preset ekspor APK Android v1.4.0-madiun (versionCode 140, arm64-v8a)
├── icon.svg                          # Ikon vektor asli Incremental Traffic
├── assets/
│   ├── icons/                        # Android Adaptive Icons (192x192 & 432x432 safe-zone)
│   └── ui/title_logo.png             # Logo judul asli Incremental Traffic
├── gui/
│   ├── theme.tres                    # Tema UI asli "Sticker" (Terang)
│   ├── theme_dark.tres               # Tema UI asli "Sticker" (Gelap / Malam)
│   └── theme_studies/fonts/          # Font asli Jost-Variable.ttf
├── sounds/ui/                        # 26 file efek suara UI WAV asli Incremental Traffic
├── shaders/                          # 10 file shader asli (city_ground, road_verge, city_building, city_reveal, city_shadow, cloud_puff, rule_hints, water_ripples, leaning_roof, extrude_25d)
├── godot_src/
│   ├── main_game.gd                  # Orkestrator utama, input dunia, siklus hidup Android & zero-leak smoke test
│   ├── core/                         # catalog.gd (44 goods), road_geom.gd (per-lane + plaza_polygon), pathfinder.gd, sfx_synth.gd, sim_engine.gd
│   ├── render/                       # tri_batch.gd (CUSTOM0 + MeshInstance2D), map_view_25d.gd (RoadBed 3-ring, LaneMarkings, 2.5D shaders)
│   └── ui/                           # it_icons.gd (44 glyphs), touch_camera.gd, android_hud.gd (StreetEditor, 6-tool RuleToolbar)
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

## 🔍 Verifikasi Paket APK dengan REA (`rea-agents@6.9.0` + `JADX 0.7.1`)

File [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`SHA-256: 8a9c1dcb7522dcd38e89a7cbdc1b78a1e54c4a9c1c6eb63d0246742b1eab042e`, `28.087.908 byte`) telah diverifikasi secara statis menggunakan **REA**:

| Operasi REA | Evidence ID | Temuan Terverifikasi (*Observed*) |
| :--- | :--- | :--- |
| `inspect-apk-signature` | `ev_de86f45859bbc7c12ce93e757bb67c08644138de3709b3bd7df405039fe17802` | Skema tanda tangan **v1 (`MADIUNRE.RSA`), v2, dan v3** lengkap dan terverifikasi oleh `apksigner verify` dengan sidik jari sertifikat tetap `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce` (`Serial: 5071a11bb51cc4dc`). |
| `inspect-artifact` | `ev_28e357bef25f7ab0076881f443fe3e11a466838f0ce5fd1753a0217f388172d7` | Graf & inventori artefak utuh (ringkasan proyeksi `ev_d2e97eb0fafecf98a1d4832a99d5381ac1b6cd6fff2125aeb88dc15e708ade46`, `200` entri APK termasuk seluruh `10` berkas shader `.gdshader`/`.gdshaderinc`, `.gdc` terkompilasi, `Jost-Variable.ttf`, `theme.tres`, `theme_dark.tres`, `26` WAV UI & `madiun_maps.json`). |
| `inspect-android-package` | `ev_405ad98084a7090bc6251ad91f171dd74c981cf5ec118d47fe69cca7f768e5e4` | `id.madiun.incrementaltraffic`, `versionCode: 140`, `1.4.0-madiun`, `minSdk: 24` (Android 7.0+), `targetSdk: 36`, `glEsVersion: 0x30000`, izin minimal `android.permission.VIBRATE`. |
