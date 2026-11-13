# Incremental Traffic: Karesidenan Madiun (Godot 4.7.2 Android Edition — v1.2.0)

Simulasi rekayasa lalu lintas mikro-agen dan logistik rantai pasok **2.5D** menggunakan **Godot Engine 4.7.2 (`gl_compatibility` Mobile Renderer)** yang memadukan **Geometri Jalan (`RoadBed` & `RoadPaint`), Simpang Bezier Monolitik, Bundaran 1/2 Lajur, Jembatan Sungai Update 1.9, UI/UX, Tema `"Sticker"`, Font, Ikon Vektor, Logo, Palet Dunia, dan Efek Suara Asli *Incremental Traffic*** dengan **alur jalan dunia nyata (OSRM / OpenStreetMap WGS84)**, batas administrasi, sungai, dan jalur kereta api di seluruh **6 Kota & Kabupaten eks-Karesidenan Madiun, Jawa Timur**, serta optimalisasi penuh **60–120 FPS** untuk perangkat **Android**.

---

## 📱 Unduh & Instalasi APK Android (`v1.2.0-madiun`)

File APK rilis yang telah ditandatangani secara kriptografis (**APK Signature Scheme v1 + v2 + v3**, arsitektur `arm64-v8a`) tersedia langsung di repositori ini:

- **GitHub Releases**: [`v1.2.0-madiun`](https://github.com/nafta121/studious-pancake/releases/tag/v1.2.0-madiun) · Riwayat lengkap di [`CHANGELOG.md`](CHANGELOG.md)
- **Lokasi File APK**: [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`26,7 MB` / `27.980.757 byte`)
- **Package ID**: `id.madiun.incrementaltraffic`
- **Versi**: `1.2.0-madiun` (`versionCode: 120` — mendukung *in-place update* langsung di atas `v1.1.0-madiun` tanpa menghapus data simpanan)
- **Engine**: Godot Engine `4.7.2.stable` (Compiled GDScript Bytecode `.gdc`, GLES3 Mobile)
- **APK File SHA-256**: `485f4684edde0bf958de000b8363d8a13d8303519f755ed997d89ba904bff797`
- **Signing Certificate Continuity** (`signing/madiun_godot_release.keystore`):
  - **Certificate Serial Number**: `5071a11bb51cc4dc`
  - **Certificate SHA-256 Digest**: `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce`
  - **Certificate SHA-1 Digest**: `4a10248317724b7f363d92c9874c5c521ef98808`
  - **Validitas**: `2026-11-13` s/d `2054-03-31`

### Cara Memasang / Memperbarui (*Update*) di Perangkat Android:
1. Unduh `incremental-traffic-madiun-android.apk` dari halaman [**GitHub Releases**](https://github.com/nafta121/studious-pancake/releases/tag/v1.2.0-madiun) atau [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk), lalu pasang langsung di atas versi sebelumnya (tanpa *uninstall* agar progres `save_<map_id>.json` tetap tersimpan), atau melalui ADB:
   ```bash
   adb install -r releases/incremental-traffic-madiun-android.apk
   ```
2. Game mendukung **Auto-Rotation (Landscape `1152×648` & Portrait `480×960` DPI-adaptive)**, *edge-to-edge immersive mode*, kamera sentuh *2-finger pinch-zoom* + *inertial pan* + *double-tap zoom*, serta navigasi tombol fisik/gestur **Back** bawaan Android.

---

## 🛣️ Pembaruan `v1.2.0`: Jalan, Simpang, Bundaran & Jembatan Asli *Incremental Traffic* + Alur Jalan Akurat OSRM

1. **Alur Jalan Dunia Nyata Akurat & Halus (`scripts/fetch_osrm_madiun_roads.py` + `scripts/build_madiun_geodata.py`)**:
   - Menarik **194 koridor jalan nyata WGS84** dari **OSRM / OpenStreetMap** di seluruh 7 peta Karesidenan Madiun (`geodata/madiun_osrm_roads_cache.json`), dilengkapi pembersihan *micro-hook* GPS & jalan satu arah, penjagaan jarak terhadap simpang tak terkait, pemisahan sudut lengan simpang (`≥ 25°`), relaksasi sudut tajam, serta penghalusan kurva B-spline **Chaikin 3-tahap** ($C^1$ mulus dengan sudut belok per simpul `≤ 33,3°`).
   - Deteksi otomatis perpotongan ruas jalan dengan sungai nyata (Kali Bengawan Solo, Kali Madiun, Kali Gandong, Kali Grindulu) menghasilkan **62 bentang jembatan sungai akurat (`bridgeSpans`)** dan **6 *overpass* tak sebidang (`overpassSpans`)**.
2. **Multi-Pass `RoadBed`, Simpang Bezier Monolitik & Bundaran 1/2 Lajur (`road_geom.gd`, `tri_batch.gd`, `map_view_25d.gd`)**:
   - Ekstrusi *triangle strip* kontinu ber-*miter-clamp* (`TriBatch2D.add_smooth_strip`, `stretch ≤ 2.0`) seperti `TriBatch` asli *Incremental Traffic* — menghilangkan gelembung sambungan segmen dan memangkas jumlah segitiga jalan hingga `~4×`.
   - **Simpang Bezier Monolitik (`swept_sidewalk`, `swept_curb`, `swept_asphalt`)**: Trotoar `#E2DED2`, bahu `#A9A59B`, dan aspal `#3C3F4A` menyatu mulus melintasi simpang 3/4 lengan maupun belokan dengan *concave Bezier curb fillets* tanpa garis sambungan di tengah simpang.
   - **Bundaran 1-Lajur (`roundabout`) & 2-Lajur (`roundabout2`)**: Pulau tengah taman hijau (`#6E9953`) dengan *stone curb* (`#ACA79B`), *truck apron* (`#EAE6DA`), monumen tugu/pepohonan, *flare* mulut bundaran, pulau pemisah segitiga (*splitter islands*), marka melingkar putus-putus pada bundaran 2 lajur, dan sirkulasi searah jarum jam standar jalur kiri Indonesia (*Left-Hand Traffic*).
   - **Jembatan Sungai Update 1.9 (`bridgeSpans`)**: Pilar batu tepi sungai (*abutment piers*), lantai trotoar beton jembatan, dinding parapet putih di sisi kiri-kanan, dan bayangan jatuh di atas permukaan sungai.
3. **Marka `RoadPaint`, Sinyal Sudut Simpang, Pita Konektor Lajur & Lintasan Truk Ber-gandengan (`sim_engine.gd`, `rule_hints.gdshader`)**:
   - Marka jalan dipotong presisi sebelum mulut simpang (`trimStart` / `trimEnd`): garis ganda median arteri + arsiran *gore chevron* menjelang lampu lalu lintas, garis henti putih tebal (*stop bar*) dan gigi hiu (*shark-teeth yield*) khusus pada lajur masuk + rambu segitiga *Yield* di trotoar, panah arah lajur (`←`, `↑`, `→`, `↰`, `↱`), cakram lampu lalu lintas merah/hijau di sudut bahu jalan, cincin petunjuk aturan (`shaders/rule_hints.gdshader`), cincin inspeksi biru + pita konektor belokan berwarna transparan (seperti *Steam Update 1.7*), serta lintasan belok Bezier & orbit bundaran mulus untuk truk beserta 1–3 gandengan (*articulated trailers*).

---

## 🎨 UI/UX, Aset, Ikon & Audio Asli *Incremental Traffic*

1. **Tema Asli `"Sticker"` Terang & Gelap (`gui/theme.tres` & `gui/theme_dark.tres`) + Font `Jost-Variable.ttf`**:
   - Menggunakan file tema dan tipografi asli *Incremental Traffic* dengan sudut membulat `14px`, garis tepi tinta tebal `2px` (`#23242B`), bayangan stiker tegas, tombol utama emas `#F4C64A`, dan lencana biru `#1C5BD6`.
2. **Ikon Peluncur Adaptif & Logo Judul Asli**:
   - `icon.svg` asli di-render menjadi *Android Adaptive Icon* (`assets/icons/icon_main.png`, `icon_foreground.png`, `icon_background.png` `#F2F0E5`) serta `assets/ui/title_logo.png` pada *boot splash* dan pemilih peta.
3. **5-Zone Authentic HUD (`godot_src/ui/android_hud.gd` + `godot_src/ui/it_icons.gd`)**:
   - **Zona 1 (`MoneyDisplay`)**: Lambang perisai daerah (`TownCrest`), nama wilayah aktif, kas, serta indikator laba bersih `▲ +$388 / min`.
   - **Zona 2 (`GoalsPanel`)**: Kartu target `GOALS FOR REGION N` dengan cincin progres melingkar untuk tiap komoditas (`ShapeGlyphs`), tombol lipat `−`, dan bilah tahan `30 detik`.
   - **Zona 3 (`RuleToolbar` + `Lanes` Subbar)**: 6 tombol kartu stiker vertikal (`Yield`, `Stop`, `Lanes`, `Roundabout`, `Lights`, `Roads`) lengkap dengan sub-bar `+ Add lane`, `− Remove lane`, `One-way`, dan `Close street`.
   - **Zona 4 & 5**: Tombol emas **`Overview`** & **`Trucks`**, trek 5 ikon **`OverlayBar`** (`Routes`, `Traffic`, `Goods Flow`, `Buildings`, `Demand`), **`Bell`**, **`DayClock`** (`09:00` / `22:00`), serta **`||` `1x` `2x` `4x`**.
4. **26 File Efek Suara UI Asli (`sounds/ui/*.wav`) + Haptic Android**:
   - Memuat langsung ke-26 file WAV asli *Incremental Traffic* dengan *priority gating*, *pitch jitter*, dan getaran halus Android tanpa menyertakan musik desktop berukuran besar agar APK tetap ringan (`~26,7 MB`).

---

## ⚡ Optimalisasi Performa Khusus Android (Godot 4.7.2)

1. **Renderer `gl_compatibility` (OpenGL ES 3.0 Mobile)**: Menghindari *Vulkan shader compilation stutter* pada GPU ponsel menengah ke bawah, menghasilkan waktu muat instan dan konsumsi memori rendah.
2. **Batching Geometri Statis Berbasis `RenderingServer` (`TriBatch2D` & `_StaticBatchLayer`)**: Seluruh poligon wilayah/kelurahan, alur sawah, pohon, sungai, rel KA, jembatan, bundaran, marka jalan, dan jaringan aspal dikompilasi ke dalam `RenderingServer.canvas_item_add_triangle_array` (**0 beban triangulasi ulang per frame**).
3. **Skala DPI Dinamis Landscape (`1152×648`) & Portrait (`480×960`)**: Mengatur `content_scale_size` secara otomatis saat orientasi layar berubah.
4. **Simulasi Fisika Deterministik 30 Hz + *Frustum Culling***: Pergerakan mikro-agen truk, *cooperative lane-changing*, antrean di garis henti `stop_s`, lampu lalu lintas berfase lengan berhadapan, dan bundaran dihitung pada *fixed timestep* `30 Hz` dengan *frustum culling*.
5. **Manajemen Siklus Hidup & Baterai Android**: Tiga preset performa (**30 / 60 / 120 FPS**), *autosave* otomatis ke `user://save_<map_id>.json`, dan penurunan otomatis ke `10 FPS` saat aplikasi berada di latar belakang.

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
| `kab_pacitan` | **Kabupaten Pacitan (Teluk & JLS Selatan)** | Teluk Pacitan & Samudra Hindia, **Pelabuhan Samudra Tamperan** (ekspor maritim *Harbour*), jembatan muara Kali Grindulu, Pegunungan Kars Gunungsewu (Punung–Donorojo), dan **Jalur Lintas Selatan (JLS)** hingga Tulakan–Ngadirojo. |

---

## 🛠️ Struktur Proyek & Cara Build Mandiri

```text
├── project.godot                     # Konfigurasi Godot 4.7.2 (v1.2.0, gl_compatibility, Sticker theme)
├── export_presets.cfg                # Preset ekspor APK Android v1.2.0-madiun (arm64-v8a, bytecode)
├── icon.svg                          # Ikon vektor asli Incremental Traffic
├── assets/
│   ├── icons/                        # Android Adaptive Icons (192x192 & 432x432 safe-zone)
│   └── ui/title_logo.png             # Logo judul asli Incremental Traffic
├── gui/
│   ├── theme.tres                    # Tema UI asli "Sticker" (Terang)
│   ├── theme_dark.tres               # Tema UI asli "Sticker" (Gelap / Malam)
│   └── theme_studies/fonts/          # Font asli Jost-Variable.ttf
├── sounds/ui/                        # 26 file efek suara UI WAV asli Incremental Traffic
├── shaders/                          # rule_hints.gdshader asli + shader ekstrusi 2.5D & air sungai GLES3
├── godot_src/
│   ├── main_game.gd                  # Orkestrator utama, input dunia, siklus hidup Android & smoke test
│   ├── core/                         # catalog.gd, road_geom.gd (Bezier junction/roundabout), pathfinder.gd, sim_engine.gd
│   ├── render/                       # tri_batch.gd (miter-clamped strips), map_view_25d.gd (RoadBed/RoadPaint/Bridges)
│   └── ui/                           # it_icons.gd, touch_camera.gd, android_hud.gd
├── geodata/                          # Data batas wilayah, sungai & cache koridor jalan OSRM Karesidenan Madiun
├── data/madiun_maps.json             # Paket 7 peta dunia nyata siap pakai (194 jalan OSRM, 62 jembatan)
├── scripts/
│   ├── fetch_osrm_madiun_roads.py    # Pengambil polilin jalan nyata WGS84 dari OSRM / OpenStreetMap
│   ├── build_madiun_geodata.py       # Kompilator geometri OSRM + Chaikin B-spline + deteksi jembatan sungai
│   └── build_android_apk.sh          # Skrip ekspor & penandatanganan APK Godot 4.7.2 otomatis
└── releases/
    └── incremental-traffic-madiun-android.apk
```

### Menjalankan Build APK Secara Lokal:
```bash
bash scripts/build_android_apk.sh
```

---

## 🔍 Verifikasi Paket APK dengan REA (`rea-agents` + `JADX 0.7.1`)

File [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`SHA-256: 485f4684edde0bf958de000b8363d8a13d8303519f755ed997d89ba904bff797`) telah diverifikasi secara statis menggunakan **REA**:

| Operasi REA | Evidence ID | Temuan Terverifikasi (*Observed*) |
| :--- | :--- | :--- |
| `inspect-apk-signature` | `ev_e22c36aa7b16073942cd97c37a8d09e1d3ddad45a780ea151bdba54cd5e70dcc` | Blok tanda tangan **v1, v2, dan v3** konsisten (`self_consistent: true`, `schemes_agree_on_signer: true`), diverifikasi kriptografis oleh `apksigner verify` (v2 + v3 aktif untuk `minSdk: 24`). |
| `inspect-artifact` | `ev_fa9c31dc17678e5a99189105f0ab29a62687fa5629cdb4feea5d5f6c90883e71` | Graf artefak utuh (`188` simpul termasuk `rule_hints.gdshader`, `Jost-Variable.ttf`, `theme.tres`, `theme_dark.tres`, `26` WAV UI & `madiun_maps.json`, `0` kontradiksi; manifes `agm_74a2c1f3...c43e8f9`). |
| `inspect-android-package` | `ev_a4127207fb070b8cc66e74839b8ba70aa94332e6078b6a9e9133ae567b9e54d3` | `id.madiun.incrementaltraffic`, `versionCode: 120`, `1.2.0-madiun`, `minSdk: 24` (Android 7.0+), `targetSdk: 36`, `1.920` kelas DEX, `192` resource, izin minimal `android.permission.VIBRATE`. |
