# Changelog — Incremental Traffic: Karesidenan Madiun (Android Edition)

Seluruh perubahan penting pada rilis APK Android (`id.madiun.incrementaltraffic`) didokumentasikan dalam berkas ini.

## 🔐 Jaminan Kontinuitas Sertifikat Penandatanganan APK (*Signing Certificate Continuity*)

Agar pengguna Android dapat melakukan **pembaruan langsung (*in-place update* / `adb install -r`)** tanpa perlu menghapus instalasi lama atau kehilangan data simpanan permainan (`user://save_<map_id>.json`), seluruh rilis mulai `v1.1.0-madiun`, `v1.2.0-madiun`, `v1.3.0-madiun`, `v1.4.0-madiun`, `v1.5.0-madiun`, `v1.6.0-madiun`, hingga `v1.7.0-madiun` dan rilis-rilis berikutnya dikunci menggunakan *keystore* rilis tetap (`signing/madiun_godot_release.keystore`) dengan validasi otomatis pada [`scripts/build_android_apk.sh`](scripts/build_android_apk.sh):

| Atribut Sertifikat | Nilai Terkunci |
| :--- | :--- |
| **Package Name** | `id.madiun.incrementaltraffic` |
| **Keystore Alias** | `madiunrelease` (RSA-2048, APK Signature Scheme v2 + v3) |
| **Subject / Issuer DN** | `CN=Incremental Traffic Karesidenan Madiun, OU=Mobile Game, O=Madiun Open GIS, L=Madiun, ST=Jawa Timur, C=ID` |
| **Certificate Serial Number** | `5071a11bb51cc4dc` |
| **Certificate SHA-256 Digest** | `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce` |
| **Certificate SHA-1 Digest** | `4a10248317724b7f363d92c9874c5c521ef98808` |
| **Masa Berlaku** | `2026-11-13` s/d `2054-03-31` |

> **Catatan Pembaruan**: Jika Anda sebelumnya memasang `v1.1.0-madiun` s/d `v1.6.0-madiun`, Anda dapat langsung mengunduh dan memasang `v1.7.0-madiun` di atasnya tanpa *uninstall* (kompatibel penuh dengan simpanan multi-slot atomik `RunSave v: 4` beserta migrasi otomatis dari `v: 2` / `v: 3`).

---

## [`v1.7.0-madiun`] — `versionCode: 170`

- **Berkas APK**: [`incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`28.392.040 byte` / `27,1 MB`, `arm64-v8a`, Android 7.0+ `minSdk: 24`, `212` berkas terpaket)
- **APK SHA-256**: `43d4124fc6a0f5601e692506cc0705ba86433c7819a9a92d768d01788104f556`
- **Certificate Serial / SHA-256**: `5071a11bb51cc4dc` / `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce` (identik dengan `v1.1.0-madiun` – `v1.6.0-madiun`)

### 📱 Audit Menyeluruh & Perombakan UI/UX Sentuh, Scroll, Pop-up & Modal Android (`v1.7.0`)
1. **Modal Scrim Interaktif & Gatekeeper Kamera Sentuh Presisi (`touch_camera.gd`, `android_hud.gd`, `stage_overlays.gd`, `main_game.gd`)**:
   - **Tap Area Gelap/Scrim Langsung Menutup Modal**: Menambahkan backdrop gelap interaktif (`_modal_scrim` pada `AndroidHUD` serta handler scrim pada `StageOverlays`) yang langsung menutup modal (`Overview`, `PauseMenu`, `SaveLoadMenu`, `AudioOptions`, `RegionOpenPopup`, `ConfirmModal`) saat mengetuk area di luar kartu.
   - **Drift Kamera `0,000 px` & Isolasi *Double-Tap Zoom***: `TouchCamera2D.ui_input_blocker` memblokir kebocoran geseran/cubitan ke kamera peta saat modal terbuka atau sentuhan dimulai di atas kontrol HUD (`0,000 px` drift), menolak `InputEventScreenDrag` dari jari yang tidak terdaftar di `_touches`, serta mengunci *double-tap zoom* hanya pada mode `pan` kosong agar ketukan cepat saat memegang tool jalan/simpang tidak memicu aksi ganda.
2. **Touch-Flick `ScrollContainer` Mulus di Atas Tombol & Pelestarian Posisi Scroll (`android_hud.gd`, `stage_overlays.gd`)**:
   - **Propagasi Sentuh Rekursif (`MOUSE_FILTER_PASS` / `IGNORE`)**: Seluruh `ScrollContainer` (`TitleStage -> New Game`, `SaveLoadMenu`, `RoadReroutePanel`, 5 tab `Overview`, `Contextual Inspector`, dan `Overlay Legend`) kini mengizinkan *touch-drag* yang dimulai tepat di atas tombol langsung menggulirkan daftar dengan mulus tanpa menghilangkan ketukan tombol.
   - **Bilah Ubah-Nama Slot Terdedikasi & Proteksi Keyboard Virtual**: Memindahkan `LineEdit` keluar dari baris scroll `SaveLoadMenu` agar menggeser daftar slot tidak memunculkan keyboard virtual Android secara tak sengaja, membungkus `TitleStage` dalam `_title_scroll` dengan kompensasi `DisplayServer.virtual_keyboard_get_height()`, serta membersihkan kontainer dengan `remove_child` + pelestarian `scroll_vertical` bebas inflasi ukuran `autowrap_mode`.
3. **Tata Letak Portrait `480×960` Bebas Overflow & Tombol Jam Ringkas (`android_hud.gd`, `stage_overlays.gd`)**:
   - **Tombol Jam Ringkas (`☀ 09:00`) Tetap Tampil di Bar Bawah Portrait**: Mempertahankan `_clock_btn` (`74×44 px`) pada Baris 1 bar bawah Portrait berdampingan rapi dengan `[Overview][Trucks]` dan `[||][1x][2x][4x]` tanpa meluber di layar `480 px`, dilengkapi auto-dismiss `_day_popover` saat mengetuk area luar.
   - **Grid `3×2` Lane Subbar, Kartu Responsif & `ScrollContainer` Anti-Clipping**: Mengubah `_lane_subbar` menjadi `GridContainer` responsif (`6×1` Landscape / `3×2` Portrait), membungkus aksi kartu rute dengan `HFlowContainer` + grid *Swap Model* `2` kolom, menyusun pemilih FPS `Options` secara vertikal di Portrait, serta membungkus `_overlay_card` dan seluruh rute terdampak di `RoadReroutePanel` dalam `ScrollContainer` dengan koordinasi z-order otomatis.
4. **Stack Navigasi Android Back / `ESC`, Pembekuan `TitleStage` & Konfirmasi Aksi Destruktif (`main_game.gd`, `stage_overlays.gd`, `android_hud.gd`, `world_shows.gd`)**:
   - **Stack Navigasi Back Terpadu & Jeda `TitleStage`**: Membekukan `sim.step_frame(delta)`, `_autosave_timer`, dan ekspor `camera_meta` selama `TitleStage` atau layar muat aktif (`dt = 0,0000 dtk`), serta menyatukan tombol fisik/gestur **Android Back** (`NOTIFICATION_WM_GO_BACK_REQUEST`) dan **`ESC`** ke dalam satu stack prioritas `handle_back_navigation()`.
   - **Konfirmasi 2-Langkah, Safe-Area & Standar Sentuh `>= 40–46 px`**: Menambahkan modal konfirmasi sebelum menjalankan aksi destruktif (`Pensiunkan Rute / Retire`, `Reset Progress Peta`, `Ulangi Kota Ini $500`, `Hapus Slot Simpanan`), menerapkan inset `DisplayServer.get_display_safe_area()` pada seluruh layar & penunjuk gerbang wilayah (`192×44 px`), serta memperluas pill ketuk `RoadOfferSigns`.

---

## [`v1.6.0-madiun`] — `versionCode: 160`

- **Berkas APK**: [`incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`28.371.560 byte` / `27,1 MB`, `arm64-v8a`, Android 7.0+ `minSdk: 24`, `212` berkas terpaket)
- **APK SHA-256**: `de6e6fde62c41f0f74e5e4b9df0988a80c160f87db209f2580ca4f6a9443bd57`
- **Certificate Serial / SHA-256**: `5071a11bb51cc4dc` / `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce` (identik dengan `v1.1.0-madiun` – `v1.5.0-madiun`)

### 🚦 Sinkronisasi Penuh 4 Pilar Inti *Incremental Traffic* `v1.4.1` (`v1.6.0`)
1. **Fisika Lalu Lintas Mikro, Lot Parkir Fisik (`ParkingSpace`) & Jalan Keluar (`ExitRoads`) (`parking_lot.gd`, `sim_engine.gd`, `road_geom.gd`, `map_view_25d.gd`)**:
   - **Eliminasi *Ghost-Driving* Anti-Stuck**: Menghapus mekanisme tembus-tabrakan lama setelah tunggu lama, sehingga antrean macet nyata terbentuk secara organik dan diagnosis *Gridlock* bekerja seperti `SimCore` asli.
   - **Pengereman Kinematik Lintas Segmen & Zona Konflik Simpang/Bundaran**: Kendaraan memindai ruang bebas hingga `2–3` segmen ke depan (`v²/(2·decel)`), menghormati celah `2,2s` bundaran serta matriks konflik belok `RoadGeom.movements_conflict` pada simpang `Yield` dan belok kiri lawan arus di lampu hijau.
   - **Halaman Parkir Fisik `ParkingSpace` (`8` Bay) & `wideGate`**: Setiap pabrik, pemasok, pasar, stasiun, dan pelabuhan kini memiliki apron aspal fisik dengan `1..4` teluk parkir luar ruang + bangunan garasi beratap metal bergelombang (`5..8` teluk dalam ruang), manuver kurva Bezier masuk/mundur/keluar nyata per truk, serta gerbang ganda simultan (`wideGate` saat `bays >= 5`) dengan antrean masuk fasilitas.
   - **Jalan Keluar Fisik (`ExitRoads`) & `CityRebuild`**: Opsi pembelian akses satu arah keluar terpisah seharga `$20.000` (beserta penjualan kembali `Sell (+$10k)` / pengembalian dana `50%`) yang memisahkan arus keluar truk ke ruas jalan belakang/samping dan merelokasi otomatis bangunan kota sekitar jalan baru (`CityRebuild`).
2. **Kereta Api & Kapal Aktif + Palang Perlintasan Sebidang & Jembatan Angkat *Bascule* (`transport_sim.gd`, `sim_engine.gd`, `map_view_25d.gd`, `sfx_synth.gd`)**:
   - **Layanan Kereta Api Aktif (`TrainService`) & Palang Perlintasan Otomatis**: Lokomotif diesel + rangkaian gerbong kargo melintasi rel peta secara terjadwal (`110 dtk`), singgah di Stasiun untuk mengangkut tumpukan `yardPile` (`2,0×`), dan memicu palang pintu perlintasan sebidang otomatis (`5,0 dtk` peringatan awal + lampu merah berkedip ganda + dentang lonceng `crossing_bell`) yang menghentikan truk di garis henti rel.
   - **Layanan Kapal Kargo (`ShipService`), Tongkang Sungai & Jembatan Angkat *Bascule***: Kapal kargo samudra bersandar di Pelabuhan (`1,6×`) dan tongkang sungai berlayar di alur Bengawan Solo / Kali Madiun; jembatan sungai pelayaran bertransformasi menjadi jembatan angkat *bascule* 2.5D dengan menara penyeimbang dan daun dek terangkat yang menahan lalu lintas jalan saat kapal melintas.
3. **Presisi Rumus Ekonomi, Gudang & *Boomtown* 10-Level (`catalog.gd`, `sim_engine.gd`, `android_hud.gd`)**:
   - **Modal Awal `$500`, Penutupan Jalan `$0` & Harga Lajur Per-Arah**: Menyelaraskan kas awal permainan ke `$500` (`STARTING_CASH = 500`), penutupan jalan gratis (`close_street = $0`), serta pembelian/pengembalian `50%` lajur dihitung per arah (`Dir: Fwd` / `Back` = `1×`, `Both` = `2×`).
   - **Inflasi Penawaran Jalan Baru (`0.88 × 1.2^n`) & Eksklusi Bentrok**: Penawaran pintasan jalan baru mengalami inflasi `1,2^n` setiap pembelian jalan baru dan otomatis mengecualikan kandidat ruas yang berpotongan terlalu dekat dengan jalan aktif.
   - **Kapasitas Integer Komoditas `2`-Slot & Bongkar Muat Parsial Unit-demi-Unit**: Memperbaiki kapasitas efektif gudang input untuk komoditas ukuran `2`-slot (`int(cap / 2)`, mis. `15 / 2 = 7` unit) serta bongkar muat bertahap `0,55 dtk/unit` agar truk dapat membongkar sebagian muatan yang muat dan menunggu sisa ruang tanpa kehilangan kargo.
   - **Kernel Trapesium `MarketDemand` `105 dtk` & *Boomtown* `10`-Level + `CityBoom`**: Menghitung laju pengiriman pasar menggunakan jendela trapesium mulus `105 dtk` (`15 dtk` *ramp-in* + `60 dtk` penuh + `30 dtk` ekor), menahan syarat kelulusan target selama `GOAL_HOLD_SEC = 60 dtk`, serta menghadirkan fase akhir **Boomtown Level 1–10** (`+3,0 / mnt` per level) yang memicu pemadatan gedung tinggi `CityBoom` dan pertumbuhan populasi kota.
4. **Alur Stage, Sinematik Wilayah & Mixer Audio 5-Kanal Asli (`stage_overlays.gd`, `world_shows.gd`, `touch_camera.gd`, `sfx_synth.gd`, `main_game.gd`)**:
   - **Alur Stage Penuh (`TitleStage` → `LoadingRoundabout` → `PauseMenu` / `SaveLoadMenu`)**: Layar judul dengan kamera mengorbit kota hidup, pemilih ke-7 peta Karesidenan Madiun berpratinjau minimap vektor `CityPreview` + kode peta Base-32 `CityCode` yang dapat disalin/ditempel, transisi bundaran berputar `18` truk warna-warni (`LoadingRoundabout`), serta menu jeda (`☰`) dengan **3 slot simpanan atomik `RunSave v4`** (`.tmp` → `.bak` → `.json` + *autosave*).
   - **Gerbang Wilayah Interaktif (`RegionGate`) & Sinematik `UnlockShow` / `BoomShow` / `RoadShow`**: Plang gerbang kunci berdenyut di batas wilayah terkunci lengkap dengan penunjuk tepi layar (*off-screen pointer*), terbang kamera sinematik `fly_to_world`, semburan `170` konfeti warna-warni + kartu `RegionOpenPopup` saat wilayah baru terbuka, kembang api `BoomShow` saat naik level *Boomtown*, serta animasi hamparan segmen jalan baru `RoadShow`.
   - **Plang Penawaran Jalan di Peta (`RoadOfferSigns`), `RoadReroutePanel` & Audio 5-Kanal**: Menampilkan `6` lencana penawaran jalan terbaik langsung di atas peta, panel konfirmasi pengalihan rute terdampak (`RoadReroutePanel`) dan spanduk peringatan rute putus (`BrokenRouteBanner`), serta synthesizer efek suara baru (`crossing_bell`, `train_depart`, `ship_horn`, `firework_pop`, `truck_honk`, *city ambience*) dengan mixer **5 kanal independen** (`Master`, `SFX`, `UI`, `Deliveries`, `Ambience`).

---

## [`v1.5.0-madiun`] — `versionCode: 150`

- **Berkas APK**: [`incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`28.202.930 byte` / `26,9 MB`, `arm64-v8a`, Android 7.0+ `minSdk: 24`, `204` berkas terpaket)
- **APK SHA-256**: `612e154d65bfce1535f8f346939a373effddde8b201c8e96e1e13fee783373af`
- **Certificate Serial / SHA-256**: `5071a11bb51cc4dc` / `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce` (identik dengan `v1.1.0-madiun` – `v1.4.0-madiun`)

### 🚛 Penyelarasan Penuh `Storage`, `Cargo`, `Route`, `Trucks` & `Commodity` Asli *Incremental Traffic* (`v1.5.0`)
1. **Geometri Vektor 44 Komoditas `ShapeGlyphs` Asli (`shape_glyphs.gd`, `it_icons.gd`, `catalog.gd`)**:
   - Memporting langsung seluruh templat poligon, titik pusat kotak pembatas (`box_center` / `centered_offset`), rotasi muatan di bak truk (`truck_angle`: `fish = π`, `bull = 0`, lainnya `π/2`), palet warna standar & buta warna Okabe-Ito (`color_of`), serta *skirt* garis tepi *screen-space* (`add_keylined(..., uv_expand=true)`) untuk ke-**44 komoditas** (`3` Raw + `9` Tier-2 + `11` Tier-3 + `9` Tier-4 + `12` Tier-5).
2. **Shader Asli `truck_part.gdshader` & `truck_ghost.gdshader` + Siluet 5 Model Truk `TruckView` (`shaders/`, `tri_batch.gd`, `map_view_25d.gd`, `catalog.gd`)**:
   - Mengintegrasikan langsung `shaders/truck_part.gdshader` (ekspansi tepi *screen-space* `clamp(screen_px, 0.26, 0.85)` bebas pecah di segala tingkat zoom Android) dan `shaders/truck_ghost.gdshader` (desaturasi abu-abu luminans `alpha = 0.80` untuk armada menuju/di Depo).
   - Merender ke-5 model `TruckView` asli (`Hauler` `1` trailer, `Freighter` `2` trailer + kaca depan belah & deflektor atap, `Lowloader` kabin hidung panjang + knalpot krom ganda + `3` *flatbed* ber-*bolster* `#ECEEEA` yang sanggup mengangkut `3` barang ukuran apa pun, `Express` hidung baji aerodinamis + garis chevron V + bilah progres sisa bonus `2×` waktu nyata `1.3× + 3.0s`, serta `Bulker` *headache rack* + `2` bak curah cekung `#B4B9B3` khusus `6` bahan baku hulu) dalam hanya **2 *draw batch* GPU per frame** (`_truck_node` & `_truck_ghost_node`).
   - Menyelaraskan harga beli/jual marginal `Ledger.round_price` (pembulatan 2 angka penting + penalti kuadratik di atas 60 armada) dan kinematika waktu tempuh trapesium `TruckModel.drive_time`.
3. **Pelataran Beton Penyimpanan `FactoryLook`, Kapasitas `4..60`, `Lv.0 = 1 Bay` & Pemusnahan Kargo Basi (`sim_engine.gd`, `map_view_25d.gd`, `build_madiun_geodata.py`)**:
   - Merender pelataran beton penyimpanan (`#CFCAC0` berbingkai `#B6B0A4`) di sisi bangunan pemasok & pabrik lengkap dengan cap air siluet komoditas `22%` serta kisi visual stok nyata sesuai level `Buffer` (`Lv.0 = 2×2 (4)`, `Lv.1 = 4×2 (8)`, `Lv.2 = 5×3 (15)`, `Lv.3 = 6×5 (30)`, `Lv.4 = 10×6 (60)`).
   - Menyelaraskan fasilitas awal `Lv.0 = 1 bay` (dengan migrasi otomatis simpanan lama `v: 2 -> v: 3`) serta logika pemusnahan (*scrapping*) muatan yang tertahan penuh di dermaga bongkar lebih dari `SCRAP_WAIT_SEC` dengan nilai rongsokan `10%` dan penghitung `scrappedCount` pada `FactoryPanel`.
4. **Animasi Parabolik `CargoFlights` (`hop` & `crumble`) serta Gerbong Kereta & Palka Kapal `vehicleCargo` (`sim_engine.gd`, `map_view_25d.gd`)**:
   - Setiap bongkar-muat truk ke pelataran beton atau halaman peron/dermaga kini memicu lompatan kargo parabolik `CargoFlights.hop` disertai cincin pendaratan berdenyut, sedangkan muatan yang dibuang/ kadaluarsa memicu efek pecah `9` serpihan berputar `CargoFlights.crumble`.
   - Rangkaian kereta api di Stasiun (`2.0×`) dan kapal kargo di Pelabuhan Tamperan (`1.6×`) merender gerbong gandeng / palka kapal yang terisi visual `ShapeGlyphs` satu per satu saat menyedot tumpukan `yardPile`.
5. **Harmonisasi Warna Rute OKHSL `RouteColors`, `waypointsBack`, `RouteBreakMarks`, `Depot` & `TruckInspector` (`catalog.gd`, `pathfinder.gd`, `sim_engine.gd`, `map_view_25d.gd`, `android_hud.gd`, `main_game.gd`)**:
   - Pemilihan warna rute perseptual OKHSL/OKLab (`±44°` dari warna komoditas), garis strip warna bergantian otomatis saat beberapa rute berbagi ruas jalan, serta dukungan titik singgah terpisah pergi (`Way there`) dan pulang (`Way back` / `waypointsBack`) ketika `Same way back` dimatikan.
   - Penanda rute putus autentik `RouteBreakMarks` (garis putus-putus jalan `#FBFAF6`/`#C8323A` + lencana pil `! ROAD CLOSED / ONE-WAY / NO TURN / BLOCKED` + lencana `"N stuck"` di fasilitas asal).
   - Bangunan **Depo Armada (`Depot`)** beratap emblem truk di setiap peta untuk parkir truk sementara/rute putus, serta panel **`TruckInspector`** lengkap saat mengetuk truk di peta maupun chip rute (kecepatan aktual, muatan, bilah bonus Express, diagnosis rantai kemacetan klik-langsung `#D4383B` + `GRIDLOCK`, jalur sisa `#4B80CA`, `Follow truck`, `Go to cause`, `Leave bay`, `To depot`, `Open route`, `Swap model`, dan `Sell truck`).

---

## [`v1.4.0-madiun`] — `versionCode: 140`

- **Berkas APK**: [`incremental-traffic-madiun-android.apk`](releases/incremental-traffic-madiun-android.apk) (`28.087.908 byte` / `26,8 MB`, `arm64-v8a`, Android 7.0+ `minSdk: 24`, `200` berkas terpaket)
- **APK SHA-256**: `8a9c1dcb7522dcd38e89a7cbdc1b78a1e54c4a9c1c6eb63d0246742b1eab042e`
- **Certificate Serial / SHA-256**: `5071a11bb51cc4dc` / `7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce` (identik dengan `v1.1.0-madiun` – `v1.3.0-madiun`)

### 🛣️ Audit REA & Penyelarasan Penuh `Road Shape`, `Road Size` & `Lanes` Asli *Incremental Traffic* (`v1.4.0`)
1. **Proporsi Eksak `Road Size` & `Lane Width` (`1.68×` Rasio Lebar Truk) (`road_geom.gd`, `map_view_25d.gd`)**:
   - Hasil audit REA atas `const.gd`, `road_bed.gd`, `lane_markings.gd`, `truck_view.gd`, dan dekompilasi Ghidra `SimCore::set_lane` (`ram:0x180014c40`) menyelaraskan seluruh skala geometri jalan (`UNIT_SCALE = 0.20`): `LANE_WIDTH = 6.72` (`33.6 × 0.20`, rasio presisi `1.68×` terhadap lebar truk `4.0` = `20.0 × 0.20`), `LANE_SEPARATION = 3.84` (`19.2 × 0.20`), `LANE_SPACING = 6.00` (`30.0 × 0.20`), `MAX_LANES = 4`, `SIDEWALK = 1.76`, `CURB = 0.40`, `SHADOW_BAND = 1.20`, `LINE_WIDTH = 0.44`, dan `STOP_LINE_WIDTH = 0.90`.
2. **Arsitektur Polilin Eksplisit Per-Lajur (`lanesFwd` / `lanesBwd`) & Pelebaran Kantong Belok *Cubic Hermite* (`ramp`) (`road_geom.gd`, `sim_engine.gd`)**:
   - Setiap lajur arah maju dan balik (`1–4` lajur sepanjang ruas jalan + `1–4` lajur pendekatan simpang `approachLanesForward` / `approachLanesBackward`) kini dibangun sebagai polilin eksplisit per-lajur seperti `SimCore::set_lane`, lengkap dengan pelebaran kantong belok (*turn pocket flare*) halus `ramp(a, b, x) = t²(3 - 2t)` serta 3 pilihan panjang kantong asli (`Short = 26.0`, `Medium = 52.0`, `Long = 82.0`, setara `[130, 260, 410] px` asli).
3. **Bentuk Jalan `RoadBed` 3-Cincin Konsentris & `RoadSurface.plaza_polygon` Asimetris Bebas Celah (`road_geom.gd`, `map_view_25d.gd`)**:
   - Mengimplementasikan 3 lapisan konsentris `RoadBed` asli (`Contact Shadow Color("#363D55", 0.08)` → `Sidewalk #E2DED2` → `Curb #A9A59B`) di sekeliling polilin tiap lajur dan poligon simpang, menyinkronkan sudut tenggorokan simpang `[left_corner, right_corner]` langsung dari titik ujung lajur aktual (menjamin `0` celah antara lengan jalan dan simpang di segala sudut kurva OSRM), *fillet* Bezier kuadratik 8-segmen untuk belokan `< 145°`, busur Bezier kubik `bend(..., arc=true)` untuk sambungan lurus/siku luar `>= 145°`, serta pulau bundaran rumput `#C9D8A6` (`COL_GRASS`) bertepi trotoar `#E2DED2` dan kereb `#A9A59B`.
4. **Marka Lajur Asli `LaneMarkings` & Pulau Median Berarsir 45° (`map_view_25d.gd`)**:
   - Garis tengah tunggal `#F2F0E5` putus-putus (`DASH = 3.20`, `GAP = 2.80`) di tengah ruas jalan dua arah yang berubah utuh menjelang simpang (`CENTER_SOLID_DIST = 10.0`), membelah menjadi pulau median berarsir diagonal 45° (`_add_hatched_median_island`) khusus pada zona `medianZones`, pembatas antarlajur searah yang dihitung di titik tengah pasangan lajur bertetangga (hanya muncul setelah kantong belok mekar `>= 0.82 × LANE_SPACING`), serta panah belok per lajur yang hanya digambar ketika lajur pendekatan `> 1` atau memiliki masker belok khusus (`!= 7`).
5. **Integrasi Langsung Shader Tanah Asli (`city_ground.gdshaderinc`, `city_ground.gdshader`, `road_verge.gdshader`)**:
   - Mengintegrasikan langsung shader tanah prosedural *Incremental Traffic* (padang rumput/pasir/butir halus berbasis `FastNoiseLite` *seamless* `128×128`) pada kanvas daratan dengan peredaman otomatis saat mode malam/gelap dan preset hemat baterai.
6. **Panel Inspektur Jalan `StreetEditor` Autentik (`android_hud.gd`, `sim_engine.gd`)**:
   - Memisahkan kontrol **Lanes along the road (`1–4` per arah)**, **Lanes at junction / Turn pockets (`$1,125` per lajur ekstra di simpang, pengembalian dana `50%`)**, dan **Pocket Length (`Short / Medium / Long`)**, dengan seluruh geometri jalan tetap dikompilasi ke dalam **1 *draw batch* statis `TriBatch2D`** untuk performa stabil **60–120 FPS** di Android.

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
