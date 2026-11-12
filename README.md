# Incremental Traffic: Karesidenan Madiun (Godot 4.7.2 Android Edition)

Simulasi rekayasa lalu lintas mikro-agen dan logistik rantai pasok **2.5D** yang dibangun secara *clean-room* menggunakan **Godot Engine 4.7.2 (`gl_compatibility` Mobile Renderer)** khusus untuk perangkat **Android**, dengan tata ruang, batas administrasi, sungai, jalur kereta api, dan jaringan jalan raya dunia nyata di seluruh **6 Kota & Kabupaten eks-Karesidenan Madiun, Jawa Timur**.

---

## 📱 Unduh & Instalasi APK Android

File APK rilis yang telah ditandatangani secara kriptografis (**APK Signature Scheme v2 & v3**, arsitektur `arm64-v8a`) tersedia langsung di repositori ini:

- **Lokasi File APK**: [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (~26 MB)
- **Package ID**: `id.madiun.incrementaltraffic`
- **Versi**: `1.0.0-madiun` (`versionCode: 100`)
- **Engine**: Godot Engine `4.7.2.stable` (Compiled GDScript Bytecode `.gdc`)
- **SHA-256**: `c3617efa2252b27006a313b7011b4477c0efcdb7ce8ea546ebd66ea8939883de`

### Cara Memasang di Perangkat Android:
1. Unduh file `releases/incremental-traffic-madiun-android.apk` ke ponsel atau tablet Android Anda (Android 7.0+ `arm64-v8a`), atau pasang melalui ADB:
   ```bash
   adb install -r releases/incremental-traffic-madiun-android.apk
   ```
2. Game mendukung **Auto-Rotation (Portrait & Landscape)**, *edge-to-edge immersive mode*, kamera sentuh *2-finger pinch-zoom* + *inertial pan* + *double-tap zoom*, serta navigasi tombol fisik/gestur **Back** bawaan Android.

---

## ⚡ Optimalisasi Performa Khusus Android (Godot 4.7.2)

1. **Renderer `gl_compatibility` (OpenGL ES 3.0 Mobile)**: Menghindari *pipeline/shader compilation stutter* yang kerap terjadi pada driver Vulkan ponsel kelas menengah ke bawah, menghasilkan waktu muat instan dan konsumsi memori rendah.
2. **Batching Geometri Statis Berbasis `RenderingServer` (`TriBatch2D` & `_StaticBatchLayer`)**: Seluruh poligon wilayah/kelurahan, ekologi sawah/hutan jati/kars, sungai, rel KA, dan jaringan jalan dikompilasi ke dalam `PackedVector2Array` + `RenderingServer.canvas_item_add_triangle_array` sehingga **tidak membebani CPU per frame** dan tetap utuh saat layar Android berputar otomatis antara *Portrait* dan *Landscape*.
3. **Shader Ekstrusi 2.5D 1-Draw-Call (`shaders/extrude_25d.gdshader`)**: Seluruh atap gedung, dinding berbayang matahari, dan jendela malam dihitung langsung di *vertex/fragment shader* berdasarkan jarak radial terhadap pusat `Camera2D` tanpa beban kamera 3D penuh.
4. **Simulasi Fisika Deterministik 30 Hz + *Frustum Culling***: Pergerakan mikro-agen truk, *cooperative lane-changing*, lampu lalu lintas teraktuasi, dan bundaran dihitung pada *fixed timestep* `30 Hz` (`SIM_DT = 1/30 dtk`), sedangkan penggambaran truk multi-gandengan dan label menerapkan *world-rect frustum culling* sehingga hanya objek di layar aktif yang digambar.
5. **Sintesis Audio PCM 16-bit Prosedural (`SfxSynth`) & Haptic**: Efek suara klik taktil, koin pendapatan, lonceng Express, dan *fanfare* pembukaan wilayah bertangga nada **Pelog/Slendro Jawa** dibangkitkan secara matematis di memori (`AudioStreamWAV` 22,05 kHz) bersama getaran halus `Input.vibrate_handheld` tanpa membengkakkan ukuran APK.
6. **Manajemen Siklus Hidup & Baterai Android**:
   - Tiga preset performa langsung dari menu **⚙️ Opsi**: **🔋 Hemat Baterai (30 FPS)** (otomatis menyederhanakan detail rumah minor & gelombang air), **⚡ Seimbang Android (60 FPS)**, dan **🚀 Ultra Smooth (120 FPS)**.
   - Saat aplikasi berpindah ke latar belakang (`NOTIFICATION_APPLICATION_PAUSED`), progres otomatis disimpan ke `user://save_<map_id>.json` dan batas *frame rate* diturunkan ke `10 FPS`.

---

## 🗺️ 7 Peta Dunia Nyata Karesidenan Madiun (Geometri WGS84)

Seluruh koordinat wilayah, sungai, rel kereta api, simpang jalan, dan fasilitas ekonomi diolah dari data geospasial terbuka WGS84 (`geodata/karisidenan_madiun_wgs84.json` → `data/madiun_maps.json`):

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

## 🎮 Fitur & Mekanik Rekayasa Lalu Lintas

- **22 Komoditas Rantai Pasok & Hukum Konservasi Bahan Mentah (`$50`)**: Mulai dari komoditas hulu lokal (*Padi, Tebu, Kayu Jati Saradan, Batu Kars, Kulit Sapi Magetan, Susu Ngebel, Hasil Laut Tamperan*) hingga manufaktur bernilai tinggi (*Komponen Kereta Api, Mesin Penggiling, Sepatu Kulit, Bus Antarkota*).
- **5 Kelas Armada Truk & Kalkulator Tukar-Tambah (*Model Swap*)**:
  - **Truk Engkel (Hauler)** — serbaguna pembuka wilayah awal.
  - **Truk Fuso 2-Slot (Freighter)** — volume ganda antarkabupaten.
  - **Boks Ekspres (Express)** — kecepatan tinggi dengan bonus nilai jual **`2×`** bila tiba sebelum tenggat waktu (*deadline*).
  - **Tronton Low-Loader (3-Slot)** — spesialis muatan industri berat.
  - **Gandengan Bulker (4-Slot)** — truk artikulasi multi-gandengan untuk komoditas curah jarak jauh.
- **Alat Rekayasa Simpang & Jalan Raya**:
  - **⚠️ Rambu Yield (`$0`)**, **🔄 Bundaran 1 Lajur (`$10k`) & Upgrade 2 Lajur (`$16k`)**, serta **🚦 Lampu Lalu Lintas Teraktuasi (`$1k`)** dengan pengatur durasi hijau Fase A/B dan sensor celah detektor (`1,5 dtk`).
  - **➕/➖ Manajemen Lajur** (termasuk kantong belok & pengembalian dana `50%`), **➡️ Jalan Satu Arah (`$0`)**, **🌳 Penutupan Jalan Menjadi Taman Kota (`$3.200`)**, dan pembangunan **🛣️ Proyek Jalan Tol / Bypass / JLS**.
- **5 Mode Overlay Analitik**: *Jaringan Rute & Waypoint*, *Heatmap Kemacetan Jalan*, *Diagram Aliran Barang (Sankey)*, *Status & Efisiensi Pabrik*, serta *Permintaan Pasar & Target Wilayah*.
- **Sisi Kemudi Kiri (Standar Indonesia) & Kanan**: Dapat diubah kapan saja secara *real-time* dari menu **⚙️ Opsi**.
- **Progresi Gerbang Wilayah 30 Detik & Mode Boomtown**: Pertahankan target pengiriman per menit selama 30 detik untuk membuka wilayah berikutnya; setelah seluruh wilayah terbuka, permainan berlanjut ke tantangan tanpa batas **Boomtown Mode**.

---

## 🛠️ Struktur Proyek & Cara Build Mandiri

```text
├── project.godot                     # Konfigurasi Godot 4.7.2 (gl_compatibility, Android touch & stretch)
├── export_presets.cfg                # Preset ekspor APK Android (arm64-v8a, adaptive icons, bytecode)
├── scenes/main.tscn                  # Scene utama permainan
├── shaders/
│   ├── extrude_25d.gdshader          # Shader ekstrusi atap/dinding 2.5D radial & cahaya malam
│   └── water_ripples.gdshader        # Shader gelombang sungai & Samudra Hindia
├── godot_src/
│   ├── main_game.gd                  # Orkestrator utama, input dunia, siklus hidup Android & smoke test
│   ├── core/
│   │   ├── catalog.gd                # 22 komoditas, 5 kelas truk & utilitas warna/harga
│   │   ├── road_geom.gd              # Geometri polilin lajur kiri/kanan & pencarian biner O(log N)
│   │   ├── pathfinder.gd             # Pencari rute tercepat Dijkstra + waypoint & diagnostik rute putus
│   │   ├── sfx_synth.gd              # Sintesis audio PCM 16-bit prosedural & getaran Android
│   │   └── sim_engine.gd             # Mesin simulasi mikro-agen 30 Hz, ekonomi, upgrade & penyimpanan
│   ├── render/
│   │   ├── tri_batch.gd              # Batcher segitiga RenderingServer berkinerja tinggi
│   │   └── map_view_25d.gd           # Perender dunia 2.5D, truk artikulasi & 5 mode overlay
│   └── ui/
│       ├── touch_camera.gd           # Kamera sentuh Android (pinch-zoom, pan inersia, double-tap)
│       └── android_hud.gd            # Antarmuka Tactile Cartography adaptif Portrait & Landscape
├── geodata/                          # Data batas wilayah, sungai & topologi WGS84 Karesidenan Madiun
├── data/madiun_maps.json             # Paket 7 peta siap pakai hasil kompilasi skrip geodata
├── scripts/
│   ├── build_madiun_geodata.py       # Kompilator geometri WGS84 -> data/madiun_maps.json
│   └── build_android_apk.sh          # Skrip ekspor & penandatanganan APK Godot 4.7.2 otomatis
├── releases/
│   └── incremental-traffic-madiun-android.apk
└── .github/workflows/
    └── build-godot-android.yml       # Pipeline CI GitHub Actions untuk build APK otomatis
```

### Menjalankan Build APK Secara Lokal:
Pastikan Godot `4.7.2-stable` (beserta *export templates* `4.7.2.stable`), JDK 21, dan Android SDK (`platforms;android-34`, `build-tools;34.0.0`, `platform-tools`) terpasang, lalu jalankan:
```bash
bash scripts/build_android_apk.sh
```

---

## 🔍 Verifikasi Paket APK dengan REA (`rea-agents@6.9.0` + `JADX 0.7.1`)

File [`releases/incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`SHA-256: c3617efa2252b27006a313b7011b4477c0efcdb7ce8ea546ebd66ea8939883de`) telah diverifikasi secara statis tanpa eksekusi target menggunakan **REA**:

| Operasi REA | Evidence ID | Temuan Terverifikasi (*Observed / Derived*) |
| :--- | :--- | :--- |
| `inspect-apk-signature` | `ev_253db982523a070c27e4a5f2291c3b815db9e8c3261b7d1d484dce815f20acbb` | Skema tanda tangan **v1 JAR, v2, dan v3** aktif (`matches_apk: true`), sertifikat RSA-2048 `7b29a431...be83788e`. |
| `inspect-artifact` | `ev_21d9cb4741669b8f3dbd12709a4ec121b8a368537ac0a72bcd27b9037b4be930` | Graf artefak utuh (`125` simpul, `130` entri arsip, `0` kontradiksi; manifes akar `ev_9014267d...165203be`). |
| `inspect-android-package` | `ev_69774372afd6bdf2f3734879e98c72cb0434e6e217c32aea231c46a2c75af038` | `id.madiun.incrementaltraffic`, `versionCode: 100`, `1.0.0-madiun`, `minSdk: 24` (Android 7.0+), `targetSdk: 36`, izin minimal `android.permission.VIBRATE`. |
| `inspect-android-class` | `ev_e1607562f1f03df0a18b01d897cdab5ac57084c7ebbc47ec379bcd236bd8ea16` | Aktivitas utama `com.godot.game.GodotApp` tervalidasi oleh `jadx-headless-mcp 0.7.1`. |
| `inspect-android-jni-bindings` | `ev_ad045d73506e494c30aea839fbb026080db14217ceb8bbd9175e7a251914a4ae` | Jembatan JNI `org.godotengine.godot.GodotLib` konsisten terhadap pustaka native 64-bit `lib/arm64-v8a/libgodot_android.so` & `libc++_shared.so`. |

---

## 📜 Lisensi & Atribusi Data Terbuka

- Seluruh kode sumber GDScript (`godot_src/`), shader (`shaders/`), ikon (`assets/icons/`), dan skrip kompilasi ditulis **100% secara *clean-room*** di bawah lisensi [MIT](LICENSE).
- Geometri batas wilayah administrasi, jaringan jalan, jalur kereta api, dan alur sungai Karesidenan Madiun bersumber dari data publik terbuka (BPS / HDX Indonesia Subnational Boundaries, OpenStreetMap Contributors — ODbL, dan hidrografi DAS Bengawan Solo / Kali Madiun).
