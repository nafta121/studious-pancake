# Incremental Traffic: Karesidenan Madiun (Godot 4.7.2 Android Edition — v1.1.0)

Simulasi rekayasa lalu lintas mikro-agen dan logistik rantai pasok **2.5D** menggunakan **Godot Engine 4.7.2 (`gl_compatibility` Mobile Renderer)** yang memadukan **UI/UX, Tema `"Sticker"`, Font, Ikon Vektor, Logo, Palet Dunia, dan Efek Suara Asli *Incremental Traffic*** dengan tata ruang, batas administrasi, sungai, jalur kereta api, dan jaringan jalan raya dunia nyata di seluruh **6 Kota & Kabupaten eks-Karesidenan Madiun, Jawa Timur**, serta optimalisasi penuh **60–120 FPS** untuk perangkat **Android**.

---

## 📱 Unduh & Instalasi APK Android (`v1.1.0-madiun`)

File APK rilis yang telah ditandatangani secara kriptografis (**APK Signature Scheme v1 + v2 + v3**, arsitektur `arm64-v8a`) tersedia langsung di repositori ini:

- **Lokasi File APK**: [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`26,6 MB` / `27.923.333 byte`)
- **Package ID**: `id.madiun.incrementaltraffic`
- **Versi**: `1.1.0-madiun` (`versionCode: 110`)
- **Engine**: Godot Engine `4.7.2.stable` (Compiled GDScript Bytecode `.gdc`, GLES3 Mobile)
- **SHA-256**: `51e4e8c326872ba633bbf86bf0a109a438e2ac71391d0474b62211e74ef54081`

### Cara Memasang di Perangkat Android:
1. Unduh file `releases/incremental-traffic-madiun-android.apk` ke ponsel atau tablet Android Anda (Android 7.0+ `arm64-v8a`), atau pasang melalui ADB:
   ```bash
   adb install -r releases/incremental-traffic-madiun-android.apk
   ```
2. Game mendukung **Auto-Rotation (Landscape `1152×648` & Portrait `480×960` DPI-adaptive)**, *edge-to-edge immersive mode*, kamera sentuh *2-finger pinch-zoom* + *inertial pan* + *double-tap zoom*, serta navigasi tombol fisik/gestur **Back** bawaan Android.

---

## 🎨 UI/UX, Aset, Ikon & Audio Asli *Incremental Traffic* (`v1.1.0`)

1. **Tema Asli `"Sticker"` Terang & Gelap (`gui/theme.tres` & `gui/theme_dark.tres`) + Font `Jost-Variable.ttf`**:
   - Menggunakan file tema dan tipografi asli *Incremental Traffic* dengan sudut membulat `14px`, garis tepi tinta tebal `2px` (`#23242B`), bayangan stiker tegas, tombol utama emas `#F4C64A`, dan lencana biru `#1C5BD6`.
2. **Ikon Peluncur Adaptif & Logo Judul Asli**:
   - `icon.svg` asli di-render menjadi *Android Adaptive Icon* (`assets/icons/icon_main.png`, `icon_foreground.png`, `icon_background.png` `#F2F0E5`) serta `assets/ui/title_logo.png` pada *boot splash* dan pemilih peta.
3. **5-Zone Authentic HUD (`godot_src/ui/android_hud.gd` + `godot_src/ui/it_icons.gd`)**:
   - **Zona 1 (Atas-Tengah — `MoneyDisplay`)**: Lambang perisai daerah (`TownCrest`), nama wilayah aktif, kas, serta indikator laba bersih `▲ +$388 / min`.
   - **Zona 2 (Atas-Kanan — `GoalsPanel`)**: Kartu target `GOALS FOR REGION N` dengan cincin progres melingkar untuk tiap komoditas (`ShapeGlyphs`), tombol lipat `−` menjadi pil ringkas, dan bilah tahan `30 detik`.
   - **Zona 3 (Kiri-Tengah — `RuleToolbar` + `Lanes` Subbar)**: 6 tombol kartu stiker vertikal (`Yield`, `Stop`, `Lanes`, `Roundabout`, `Lights`, `Roads`) lengkap dengan sub-bar mengambang `+ Add lane`, `− Remove lane`, `One-way`, dan `Close street`.
   - **Zona 4 & 5 (Bawah-Kiri & Bawah-Kanan)**: Tombol emas **`Overview`** & **`Trucks`**, trek 5 ikon **`OverlayBar`** (`Routes`, `Traffic`, `Goods Flow`, `Buildings`, `Demand`), lonceng notifikasi **`Bell`**, jam **`DayClock`** (`09:00` matahari / `22:00` bulan sabit + popover penggeser jam & tema gelap), serta pengatur kecepatan **`||` `1x` `2x` `4x`**.
   - **Panel Inspektor Pabrik (`FactoryPanel`) & Modal `Overview`**: Diagram alur **`In → Cincin Produksi → Out`**, kartu **Upgrades** 2 kolom (`Speed`, `Buffers`, `Bays`, `Train/Ship`) dengan titik level, tab rute `Outgoing / Incoming` + `Swap all trucks`, serta modal **`Overview`** dengan grafik area arus kas 5 menit terakhir, diagram siluet `MiniTruck`, dan kalkulator tukar-tambah armada.
4. **26 File Efek Suara UI Asli (`sounds/ui/*.wav`) + Haptic Android**:
   - Memuat langsung ke-26 file WAV asli (`click.wav`, `tick.wav`, `confirm.wav`, `purchase.wav`, `sell.wav`, `delivery.wav`, `delivery_bonus.wav`, `panel_open.wav`, `panel_close.wav`, `tool_select.wav`, `tool_deselect.wav`, `place.wav`, `edit.wav`, `remove.wav`, `street_roll.wav`, `route_opened.wav`, `gate_press.wav`, `gate_ready.wav`, `yay.wav`, `star_ring.wav`, `speed.wav`, `pause.wav`, `resume.wav`, `refused.wav`, `popup_row.wav`, `building_slam.wav`) dengan *priority gating*, *pitch jitter*, dan getaran halus Android tanpa menyertakan musik desktop berukuran besar agar APK tetap ringan (`~26,6 MB`).
5. **Palet Dunia Kartografi & Pin Dunia Asli (`map_view_25d.gd`)**:
   - Kertas perkamen `#F2F0E5`, sungai `#A9CDD8` dengan riak air, jalan aspal `#3C3F4A` ber-trotoar `#A9A59B`, sawah beralur & pepohonan yang dipanggang ke *static GPU batch*, atap pabrik Teal/Ink/Brick ber-*skylight*, kabut awan lembut pada wilayah terkunci, pin gerbang `REGION N`, dan pil koin emas `+$100` mengambang saat pengiriman tiba.

---

## ⚡ Optimalisasi Performa Khusus Android (Godot 4.7.2)

1. **Renderer `gl_compatibility` (OpenGL ES 3.0 Mobile)**: Menghindari *Vulkan shader compilation stutter* pada GPU ponsel menengah ke bawah, menghasilkan waktu muat instan dan konsumsi memori rendah.
2. **Batching Geometri Statis Berbasis `RenderingServer` (`TriBatch2D` & `_StaticBatchLayer`)**: Seluruh poligon wilayah/kelurahan, alur sawah, pohon, sungai, rel KA, jembatan, bundaran, dan jaringan jalan dikompilasi ke dalam `RenderingServer.canvas_item_add_triangle_array` (**0 beban triangulasi ulang per frame**).
3. **Skala DPI Dinamis Landscape (`1152×648`) & Portrait (`480×960`)**: Mengatur `content_scale_size` secara otomatis saat orientasi layar berubah sehingga antarmuka seluas versi desktop saat *Landscape* dan tetap besar serta ramah ibu jari saat *Portrait* tanpa panel bertumpuk.
4. **Simulasi Fisika Deterministik 30 Hz + *Frustum Culling***: Pergerakan mikro-agen truk, *cooperative lane-changing*, lampu lalu lintas teraktuasi, dan bundaran dihitung pada *fixed timestep* `30 Hz`, sedangkan perenderan dinamis menerapkan *world-rect frustum culling*.
5. **Manajemen Siklus Hidup & Baterai Android**: Tiga preset performa (**30 / 60 / 120 FPS**), *autosave* otomatis ke `user://save_<map_id>.json`, dan penurunan otomatis ke `10 FPS` saat aplikasi berada di latar belakang.

---

## 🗺️ 7 Peta Dunia Nyata Karesidenan Madiun (Geometri WGS84)

| ID Peta | Nama Peta | Cakupan Geografis & Infrastruktur Nyata |
| :--- | :--- | :--- |
| `karisidenan_madiun` | **Karesidenan Madiun Terpadu** | Kampanye penuh **6 Wilayah Progresif** (47 simpang, 65 ruas jalan, 31 fasilitas, Kali Bengawan Solo, Kali Madiun, Kali Gandong, Kali Grindulu, Jalur KA Lintas Selatan, Tol Trans-Jawa & JLS). |
| `kota_madiun` | **Kota Madiun (27 Kelurahan)** | Detail mikro perkotaan di **Kec. Kartoharjo, Manguharjo & Taman**: Tugu 0 KM Jl. Pahlawan, Stasiun Besar Madiun & kawasan industri kereta api, PG Rejo Agung, Pasar Besar, Kali Madiun, Ring Road Barat & Timur. |
| `kab_madiun` | **Kabupaten Madiun (Poros Caruban)** | Ibu kota Caruban (Mejayan), Gerbang Tol Dumpil, Hutan Jati Alas Saradan, koridor selatan Pagotan–Geger–Dolopo, hingga perkebunan lereng Gunung Wilis (Wungu & Kare). |
| `kab_magetan` | **Kabupaten Magetan (Kaki Gunung Lawu)** | Simpang Tiga Maospati, Stasiun Kargo Barat, Alun-Alun Kota Magetan, sentra kerajinan kulit, hingga tanjakan Plaosan & Telaga Sarangan di lereng Gunung Lawu. |
| `kab_ngawi` | **Kabupaten Ngawi (Tempuran Bengawan Solo)** | Tugu Kartonyono & Benteng Pendem (pertemuan Kali Madiun & Bengawan Solo), lumbung pangan Geneng–Paron, koridor Karangjati, hingga Stasiun Walikukun, Kebun Teh Jamus & Mantingan. |
| `kab_ponorogo` | **Kabupaten Ponorogo (Bumi Reog)** | Bundaran Alun-Alun Ponorogo, persimpangan barat Sumoroto–Badegan, sentra industri Dengok–Jetis–Balong, gerbang selatan Slahung, dan kawasan Telaga Ngebel–Pulung. |
| `kab_pacitan` | **Kabupaten Pacitan (Teluk & JLS Selatan)** | Teluk Pacitan & Samudra Hindia, **Pelabuhan Samudra Tamperan** (ekspor maritim *Harbour*), muara Kali Grindulu, Pegunungan Kars Gunungsewu (Punung–Donorojo), dan **Jalur Lintas Selatan (JLS)** hingga Tulakan–Ngadirojo. |

---

## 🛠️ Struktur Proyek & Cara Build Mandiri

```text
├── project.godot                     # Konfigurasi Godot 4.7.2 (gl_compatibility, Sticker theme, splash)
├── export_presets.cfg                # Preset ekspor APK Android v1.1.0-madiun (arm64-v8a, bytecode)
├── icon.svg                          # Ikon vektor asli Incremental Traffic
├── assets/
│   ├── icons/                        # Android Adaptive Icons (192x192 & 432x432 safe-zone)
│   └── ui/title_logo.png             # Logo judul asli Incremental Traffic
├── gui/
│   ├── theme.tres                    # Tema UI asli "Sticker" (Terang)
│   ├── theme_dark.tres               # Tema UI asli "Sticker" (Gelap / Malam)
│   └── theme_studies/fonts/          # Font asli Jost-Variable.ttf
├── sounds/ui/                        # 26 file efek suara UI WAV asli Incremental Traffic
├── shaders/                          # Shader ekstrusi 2.5D radial & gelombang sungai GLES3
├── godot_src/
│   ├── main_game.gd                  # Orkestrator utama, input dunia, siklus hidup Android & smoke test
│   ├── core/                         # catalog.gd, road_geom.gd, pathfinder.gd, sfx_synth.gd, sim_engine.gd
│   ├── render/                       # tri_batch.gd, map_view_25d.gd (palet dunia & 5 overlay asli)
│   └── ui/                           # it_icons.gd (44 ShapeGlyphs & ikon vektor), touch_camera.gd, android_hud.gd
├── geodata/                          # Data batas wilayah, sungai & topologi WGS84 Karesidenan Madiun
├── data/madiun_maps.json             # Paket 7 peta siap pakai hasil kompilasi skrip geodata
├── scripts/
│   ├── build_madiun_geodata.py       # Kompilator geometri WGS84 -> data/madiun_maps.json
│   └── build_android_apk.sh          # Skrip ekspor & penandatanganan v1+v2+v3 APK Godot 4.7.2 otomatis
└── releases/
    └── incremental-traffic-madiun-android.apk
```

### Menjalankan Build APK Secara Lokal:
```bash
bash scripts/build_android_apk.sh
```

---

## 🔍 Verifikasi Paket APK dengan REA (`rea-agents@6.9.0` + `JADX 0.7.1`)

File [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`SHA-256: 51e4e8c326872ba633bbf86bf0a109a438e2ac71391d0474b62211e74ef54081`) telah diverifikasi secara statis menggunakan **REA**:

| Operasi REA | Evidence ID | Temuan Terverifikasi (*Observed / Derived*) |
| :--- | :--- | :--- |
| `inspect-apk-signature` | `ev_1081ceb35685ddbd4119cffbb90287e0cf984a1dc30f98cdfc30fb151abdbb12` | Skema tanda tangan **v1 JAR, v2, dan v3** ketiganya hadir (`self_consistent: true`, `schemes_agree_on_signer: true`), sertifikat RSA-2048 `7bae8ba2...bf4981ce`. |
| `inspect-artifact` | `ev_e9c6c0d51d699dafd06c633b85536b2d43e3878ada79d8331755e07f849f6745` | Graf artefak utuh (`187` simpul, `192` entri arsip termasuk font, tema, logo & 26 WAV UI, `0` kontradiksi; manifes `agm_daef2a96...ae5ab965`). |
| `inspect-android-package` | `ev_5ac0af8f43674d5ff7db7c906982afbb4dc562662bff1d2b836d5fc61f6095ef` | `id.madiun.incrementaltraffic`, `versionCode: 110`, `1.1.0-madiun`, `minSdk: 24` (Android 7.0+), `targetSdk: 36`, `1.920` kelas DEX, `191` resource, izin minimal `android.permission.VIBRATE`. |
