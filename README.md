# Incremental Traffic: Karesidenan Madiun (Godot 4.7.2 Android Edition — v1.5.0)

Simulasi rekayasa lalu lintas mikro-agen dan logistik rantai pasok **2.5D** menggunakan **Godot Engine 4.7.2 (`gl_compatibility` Mobile Renderer)** yang mengambil langsung **12 Berkas Shader Asli (`truck_part`, `truck_ghost`, `city_building`, `city_reveal`, `city_shadow`, `city_ground`, `road_verge`, `cloud_puff`, `rule_hints`, `water_ripples`, `leaning_roof`, `extrude_25d`), Vektor 44 Komoditas `ShapeGlyphs`, 5 Armada `TruckView` & `TruckInspector`, Pelataran Beton `FactoryLook` + `CargoFlights`, Rute OKHSL `RouteColors` + `RouteBreakMarks` + `Depot`, Arsitektur `Road Shape` (`1.68×` Lebar Truk) & Polilin Per-Lajur (`SimCore::set_lane`), Tema `"Sticker"`, Font, Ikon Vektor, Logo, dan 26 Efek Suara Asli *Incremental Traffic***, dipadukan dengan **alur jalan dunia nyata (OSRM / OpenStreetMap WGS84)** di seluruh **6 Kota & Kabupaten eks-Karesidenan Madiun, Jawa Timur**, serta optimalisasi penuh **60–120 FPS bebas kebocoran memori** untuk perangkat **Android**.

---

## 📱 Unduh & Instalasi APK Android (`v1.5.0-madiun`)

File APK rilis yang telah ditandatangani secara kriptografis (**APK Signature Scheme v1 + v2 + v3**, arsitektur `arm64-v8a`) tersedia langsung di repositori ini:

- **GitHub Releases**: [`v1.5.0-madiun`](https://github.com/nafta121/studious-pancake/releases/tag/v1.5.0-madiun) · Riwayat lengkap di [`CHANGELOG.md`](CHANGELOG.md)
- **Lokasi File APK**: [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`26,9 MB` / `28.202.930 byte`)
- **Package ID**: `id.madiun.incrementaltraffic`
- **Versi**: `1.5.0-madiun` (`versionCode: 150` — mendukung *in-place update* langsung di atas `v1.1.0-madiun` – `v1.4.0-madiun` tanpa menghapus data simpanan)
- **Engine**: Godot Engine `4.7.2.stable` (Compiled GDScript Bytecode `.gdc`, GLES3 Mobile, `0` Script/Shader Error, `0` Leaked Resources)
- **APK File SHA-256**: `612e154d65bfce1535f8f346939a373effddde8b201c8e96e1e13fee783373af`
- **Signing Certificate Continuity** (`signing/madiun_godot_release.keystore`):
  - **Certificate Serial Number**: `5071a11bb51cc4dc`
  - **Certificate SHA-256 Digest**: `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce`
  - **Certificate SHA-1 Digest**: `4a10248317724b7f363d92c9874c5c521ef98808`
  - **Validitas**: `2026-11-13` s/d `2054-03-31`

### Cara Memasang / Memperbarui (*Update*) di Perangkat Android:
1. Unduh `incremental-traffic-madiun-android.apk` dari halaman [**GitHub Releases `v1.5.0-madiun`**](https://github.com/nafta121/studious-pancake/releases/tag/v1.5.0-madiun) atau [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk), lalu pasang langsung di atas versi sebelumnya (tanpa *uninstall* agar progres `save_<map_id>.json` tetap tersimpan dan otomatis dimigrasikan ke skema `v: 3`), atau melalui ADB:
   ```bash
   adb install -r releases/incremental-traffic-madiun-android.apk
   ```
2. Game mendukung **Auto-Rotation (Landscape `1152×648` & Portrait `480×960` DPI-adaptive)**, *edge-to-edge immersive mode*, kamera sentuh *2-finger pinch-zoom* + *inertial pan* + *double-tap zoom*, ketuk langsung truk di dunia untuk membuka `TruckInspector`, serta navigasi tombol fisik/gestur **Back** bawaan Android.

---

## 🚛 Pembaruan `v1.5.0`: `Storage`, `Cargo`, `Route`, `Trucks` & `Commodity` Asli *Incremental Traffic*

1. **Vektor 44 Komoditas `ShapeGlyphs` & Ekonomi Konservasi Nilai (`godot_src/core/shape_glyphs.gd`, `godot_src/core/catalog.gd`)**:
   - Memporting ke-**44 bentuk vektor komoditas** (`3` Raw + `9` Tier-2 + `11` Tier-3 + `9` Tier-4 + `12` Tier-5) lengkap dengan pusat kotak pembatas `centered_offset`, orientasi muatan `truck_angle`, palet standar & Okabe-Ito `color_of`, serta *screen-space keyline skirt* (`add_keylined(..., uv_expand=true)`).
2. **Shader `truck_part.gdshader` & `truck_ghost.gdshader` + 5 Model Armada `TruckView` (`shaders/`, `godot_src/render/map_view_25d.gd`)**:
   - Seluruh armada dirender hanya dalam **2 *draw batch* GPU per frame** (`_truck_node` & `_truck_ghost_node`) dengan detail sasis & gandengan asli: **Hauler** (`1` trailer, `2` slot), **Freighter** (`2` trailer, kaca belah + deflektor atap, `4` slot), **Lowloader** (kabin hidung panjang + knalpot krom + `3` *flatbed* ber-*bolster* `#ECEEEA` untuk `3` barang ukuran apa pun), **Express** (hidung baji aerodinamis + V-chevron + bilah sisa bonus waktu `2×` `1.3× + 3.0s`), dan **Bulker** (*headache rack* + `2` bak curah cekung `#B4B9B3` khusus `6` bahan mentah).
3. **Pelataran Beton `FactoryLook`, Animasi `CargoFlights` (`hop` & `crumble`), Stasiun/Pelabuhan `vehicleCargo` & Pemusnahan Kargo (`godot_src/core/sim_engine.gd`)**:
   - Pelataran beton penyimpanan (`4 / 8 / 15 / 30 / 60` slot) di samping bangunan pemasok & pabrik dengan cap air komoditas `22%`, `Lv.0 = 1 bay`, lompatan parabolik kargo saat bongkar-muat (`hop`), pecahan `9` serpihan saat muatan dibuang (`crumble` dengan kompensasi `10%`), serta gerbong kereta & palka kapal kargo yang terisi visual `ShapeGlyphs` dari tumpukan `yardPile`.
4. **Rute OKHSL `RouteColors`, `waypointsBack`, `RouteBreakMarks`, `Depot` & `TruckInspector` (`godot_src/ui/android_hud.gd`, `godot_src/main_game.gd`)**:
   - Warna rute harmonis OKHSL/OKLab + garis strip bergantian di ruas jalan bersama, titik singgah terpisah pergi (`Way there`) & pulang (`Way back`), lencana diagnostik rute putus `RouteBreakMarks` (`! ROAD CLOSED / ONE-WAY / NO TURN`), bangunan **Depo Armada (`Depot`)** di ke-7 peta, serta panel **`TruckInspector`** lengkap dengan pelacakan kamera `Follow truck`, rantai kemacetan klik-langsung (`GRIDLOCK`), `Leave bay`, dan `To depot`.

---

## 🛣️ Arsitektur `Road Shape`, `Road Size` (`1.68×` Lebar Truk) & `Lanes` (`v1.4.0`)

- **Proporsi Eksak `CONST` & Polilin Per-Lajur `SimCore::set_lane` (`godot_src/core/road_geom.gd`)**: `LANE_WIDTH = 6.72` (`1.68×` lebar truk), `LANE_SEPARATION = 3.84`, `LANE_SPACING = 6.00`, mekarnya kantong belok *Cubic Hermite* `ramp(a, b, x)`, 3 cincin `RoadBed` (`Shadow` → `Sidewalk #E2DED2` → `Curb #A9A59B`), `RoadSurface.plaza_polygon` bebas celah, pulau median arsir 45°, dan shader tanah `road_verge.gdshader` + `city_ground.gdshaderinc` dalam **1 *draw batch* statis `TriBatch2D`**.

---

## 🗺️ 7 Peta Dunia Nyata Karesidenan Madiun (Geometri OSRM + WGS84)

| ID Peta | Nama Peta | Cakupan Geografis & Infrastruktur Nyata |
| :--- | :--- | :--- |
| `karisidenan_madiun` | **Karesidenan Madiun Terpadu** | Kampanye penuh **6 Wilayah Progresif** (47 simpang, 65 ruas jalan OSRM, 23 jembatan sungai, 31 fasilitas + Depo Armada, Kali Bengawan Solo, Kali Madiun, Kali Gandong, Kali Grindulu, Jalur KA Lintas Selatan, Tol Trans-Jawa & JLS). |
| `kota_madiun` | **Kota Madiun (27 Kelurahan)** | Detail mikro perkotaan di **Kec. Kartoharjo, Manguharjo & Taman**: Tugu 0 KM Jl. Pahlawan, Stasiun Besar Madiun & kawasan industri kereta api, PG Rejo Agung, Pasar Besar, Bundaran Sleko, 9 jembatan Kali Madiun, Ring Road Barat & Timur. |
| `kab_madiun` | **Kabupaten Madiun (Poros Caruban)** | Ibu kota Caruban (Mejayan), Bundaran Gerbang Tol Dumpil, Hutan Jati Alas Saradan, koridor selatan Pagotan–Geger–Dolopo, hingga perkebunan lereng Gunung Wilis (Wungu & Kare). |
| `kab_magetan` | **Kabupaten Magetan (Kaki Gunung Lawu)** | Simpang Tiga Maospati, Stasiun Kargo Barat, Bundaran Kota Magetan, sentra kerajinan kulit, hingga tanjakan Plaosan & Telaga Sarangan di lereng Gunung Lawu. |
| `kab_ngawi` | **Kabupaten Ngawi (Tempuran Bengawan Solo)** | Tugu Kartonyono & Benteng Pendem (pertemuan Kali Madiun & Bengawan Solo), 8 jembatan sungai besar, lumbung pangan Geneng–Paron, koridor Karangjati, hingga Stasiun Walikukun, Kebun Teh Jamus & Mantingan. |
| `kab_ponorogo` | **Kabupaten Ponorogo (Bumi Reog)** | Bundaran Alun-Alun Ponorogo, persimpangan barat Sumoroto–Badegan, sentra industri Dengok–Jetis–Balong, gerbang selatan Slahung, dan kawasan Telaga Ngebel–Pulung. |
| `kab_pacitan` | **Kabupaten Pacitan (Teluk & JLS Selatan)** | Teluk Pacitan & Samudra Hindia, **Pelabuhan Samudra Tamperan** (ekspor maritim *Harbour* + `yardPile`), jembatan muara Kali Grindulu, Pegunungan Kars Gunungsewu (Punung–Donorojo), dan **Jalur Lintas Selatan (JLS)** hingga Tulakan–Ngadirojo. |

---

## 🛠️ Struktur Proyek & Cara Build Mandiri

```text
├── project.godot                     # Konfigurasi Godot 4.7.2 (v1.5.0, gl_compatibility, Sticker theme)
├── export_presets.cfg                # Preset ekspor APK Android v1.5.0-madiun (versionCode 150, arm64-v8a)
├── icon.svg                          # Ikon vektor asli Incremental Traffic
├── assets/
│   ├── icons/                        # Android Adaptive Icons (192x192 & 432x432 safe-zone)
│   └── ui/title_logo.png             # Logo judul asli Incremental Traffic
├── gui/
│   ├── theme.tres                    # Tema UI asli "Sticker" (Terang)
│   ├── theme_dark.tres               # Tema UI asli "Sticker" (Gelap / Malam)
│   └── theme_studies/fonts/          # Font asli Jost-Variable.ttf
├── sounds/ui/                        # 26 file efek suara UI WAV asli Incremental Traffic
├── shaders/                          # 12 file shader asli (truck_part, truck_ghost, city_ground, road_verge, city_building, city_reveal, city_shadow, cloud_puff, rule_hints, water_ripples, leaning_roof, extrude_25d)
├── godot_src/
│   ├── main_game.gd                  # Orkestrator utama, hit-test truk/waypoint, follow-cam & gameplay smoke test
│   ├── core/                         # shape_glyphs.gd (44 vector shapes), catalog.gd (TruckModel/Ledger/RouteColors), road_geom.gd, pathfinder.gd, sfx_synth.gd, sim_engine.gd
│   ├── render/                       # tri_batch.gd (UV keyline + CUSTOM0), map_view_25d.gd (TruckView, FactoryLook, CargoFlights, RouteBreakMarks, Depot)
│   └── ui/                           # it_icons.gd (ShapeGlyphs + 5 TruckIcon), touch_camera.gd, android_hud.gd (TruckInspector, StreetEditor, Waypoints)
├── geodata/                          # Data batas wilayah, sungai & cache koridor jalan OSRM Karesidenan Madiun
├── data/madiun_maps.json             # Paket 7 peta dunia nyata siap pakai (194 jalan OSRM, 62 jembatan, Depo Armada, 44 komoditas)
├── scripts/
│   ├── fetch_osrm_madiun_roads.py    # Pengambil polilin jalan nyata WGS84 dari OSRM / OpenStreetMap
│   ├── build_madiun_geodata.py       # Kompilator geometri OSRM + Chaikin B-spline + Depo + resep 44 komoditas
│   └── build_android_apk.sh          # Skrip ekspor & penandatanganan APK Godot 4.7.2 otomatis (sertifikat terkunci)
└── releases/
    └── incremental-traffic-madiun-android.apk
```

### Menjalankan Build APK Secara Lokal:
```bash
bash scripts/build_android_apk.sh
```

---

## 🔍 Verifikasi Paket APK dengan REA (`rea-agents@6.9.0` + `JADX`)

File [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`SHA-256: 612e154d65bfce1535f8f346939a373effddde8b201c8e96e1e13fee783373af`, `28.202.930 byte`) telah diverifikasi secara statis menggunakan **REA**:

| Operasi REA | Evidence ID | Temuan Terverifikasi (*Observed*) |
| :--- | :--- | :--- |
| `inspect-apk-signature` | `ev_7690d0219cc232fa120a5ab751e3a61b9fa129443654358e5bb3a78302213eb1` | Skema tanda tangan **v1 (`MADIUNRE.RSA`), v2, dan v3** lengkap dan terverifikasi oleh `apksigner verify` dengan sidik jari sertifikat tetap `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce` (`Serial: 5071a11bb51cc4dc`). |
| `inspect-artifact` | `ev_f374f3f8cc943ff7ac1de9bdfbf8549c22cb681f1231f9a54493912b65b2be5d` | Graf & inventori artefak utuh (`204` entri APK termasuk ke-`12` berkas shader `.gdshader`/`.gdshaderinc` seperti `truck_part.gdshader` & `truck_ghost.gdshader`, `shape_glyphs.gdc` terkompilasi, `Jost-Variable.ttf`, `theme.tres`, `theme_dark.tres`, `26` WAV UI & `madiun_maps.json`). |
| `inspect-android-package` | `ev_701af579a30202d74450c99d9298d74e90828423f026502c11ef93019be77ed4` | `id.madiun.incrementaltraffic`, `versionCode: 150`, `1.5.0-madiun`, `minSdk: 24` (Android 7.0+), `targetSdk: 36`, `glEsVersion: 0x30000`, izin minimal `android.permission.VIBRATE`. |
