# Menjalankan KatyuFlow secara lokal

Gunakan Docker Desktop atau Docker Engine dengan plugin Compose. Pengujian SDK dan Rules memerlukan Node.js 22 dan npm. Pengujian aplikasi memerlukan Flutter SDK beserta browser atau Android SDK.

## Build dan jalankan

Dari root repo:

```sh
docker compose -p katyuflow-form-final config --quiet
docker compose -p katyuflow-form-final build
docker compose -p katyuflow-form-final up --wait --wait-timeout 100
docker compose -p katyuflow-form-final ps
```

| Layanan | Di host | Di container |
| --- | --- | --- |
| Firebase Authentication | `127.0.0.1:29099` | `9099` |
| Cloud Firestore | `127.0.0.1:28080` | `8080` |
| Emulator UI | [http://127.0.0.1:24000](http://127.0.0.1:24000) | `4000` |

Service `firebase-emulators` berjalan di jaringan bridge `katyuflow_local` dan mount volume `firebase_data` ke `/data`. Docker Compose memberi prefix nama project pada resource tersebut. Jika port bentrok, hentikan stack lokal yang memakai port itu atau sesuaikan pemetaan dan port klien.

Build sebelumnya tertahan saat APT mengambil indeks paket Debian. Uji unduh terpisah menerima sebagian indeks lalu timeout. Dockerfile sekarang mengambil JRE 21 dari image resmi `eclipse-temurin:21-jre-noble` dan menyalinnya ke `node:22-trixie-slim`. Tahap build memasang Firebase CLI dan mengunduh emulator. Build pertama memerlukan akses ke Docker Hub, npm, dan server distribusi emulator Firebase.

## Buat akun fiktif

Jalankan perintah berikut dari root repo. Masukkan sandi fiktif minimal delapan karakter ketika diminta.

```sh
npm --prefix database/tools ci
printf 'Sandi fiktif untuk emulator: '
IFS= read -r -s katyuflow_demo_password
printf '\n'
KATYUFLOW_DEMO_PASSWORD="$katyuflow_demo_password" \
  FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:29099 \
  FIRESTORE_EMULATOR_HOST=127.0.0.1:28080 \
  node database/tools/scripts/seed-emulator.js
unset katyuflow_demo_password
```

Akun fixture yang dapat digunakan adalah `local-owner@example.test` dan `local-worker@example.test`. Seed menetapkan role dan membuat profil lokal bila profil belum ada. Gunakan sandi yang baru dimasukkan.

## Hubungkan Flutter

```sh
cd flutter_app
flutter pub get
flutter run -d chrome
# Untuk Android Emulator, ganti chrome dengan ID perangkat dari flutter devices.
```

Mode debug menargetkan project `demo-katyuflow`. Flutter Web dan iOS Simulator memakai `127.0.0.1`. Android Emulator memakai `10.0.2.2` untuk mengakses port loopback host. Nilai dapat diganti melalui `KATYUFLOW_EMULATOR_HOST`, `KATYUFLOW_AUTH_PORT`, dan `KATYUFLOW_FIRESTORE_PORT` pada `--dart-define`. Port bawaan adalah `29099` dan `28080`.

## Uji integrasi dan pemulihan

Jalankan dari root repo. Mode `create` memakai satu UID fixture tetap. Gunakan volume demo baru untuk mengulangi tahap create jika fixture sudah ada.

```sh
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:29099
export FIRESTORE_EMULATOR_HOST=127.0.0.1:28080
node database/tools/scripts/smoke-emulators.cjs create
GCLOUD_PROJECT=demo-katyuflow-docker-tests npm --prefix database/tools test
docker compose -p katyuflow-form-final down
docker compose -p katyuflow-form-final up --wait --wait-timeout 100
node database/tools/scripts/smoke-emulators.cjs restore
unset FIREBASE_AUTH_EMULATOR_HOST FIRESTORE_EMULATOR_HOST
```

Saat `down`, Firebase CLI mengekspor data Auth dan Firestore ke `/data/export`. Container yang baru dibuat mengimpor snapshot jika metadata tersedia. `down` mempertahankan volume. Opsi `-v` menghapus volume dan data fixture di dalamnya. Penghentian paksa dapat kehilangan perubahan setelah snapshot terakhir.

Pada pengujian akhir, build selesai, container berstatus healthy, dan Emulator UI merespons pada port 24000. Login Owner fiktif, custom claim, pembacaan profil melalui SDK klien, serta 15 pengujian Firestore Rules lulus. Setelah container dihapus dan dibuat ulang, ekspor dari volume memulihkan akun Auth, claim, dan dokumen Firestore.

Salinan Flutter lulus `flutter analyze` dan 22 pengujian `flutter test`. Build Web debug dan APK Android debug berhasil. Login online melalui antarmuka Flutter dan build iOS berada di luar pengujian ini.
