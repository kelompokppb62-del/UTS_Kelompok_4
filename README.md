# KatyuFlow — pengumpulan tugas Docker

KatyuFlow adalah aplikasi Flutter untuk pengelolaan pekerjaan Owner dan Worker. Salinan ini memakai Firebase Authentication dan Cloud Firestore Emulator dengan project `demo-katyuflow`. Firebase Cloud production pada paket Spark tetap terpisah.

## Struktur

```text
.
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── .gitignore
├── firebase.emulator.json
├── README.md
├── README-Docker.md
├── database/
│   ├── firestore.rules
│   ├── firestore.indexes.json
│   └── tools/
│       ├── package.json dan package-lock.json
│       ├── scripts/
│       └── test/
└── flutter_app/
    ├── android/
    ├── ios/
    ├── lib/
    ├── test/
    ├── web/
    └── pubspec.yaml dan pubspec.lock
```

Ikuti [README-Docker.md](README-Docker.md) untuk membangun container, menjalankan Flutter, membuat akun fiktif, dan mengulangi pengujian. Folder `database/` berisi aturan, indeks, dan alat uji. Snapshot emulator berada di volume Docker lokal.

Salinan Flutter berasal dari checkpoint `9009e9d`. Launcher salinan ini memilih mode emulator secara default untuk build debug. Deskriptor native Android dan iOS berisi nilai dummy untuk project demo. Build release online menggunakan konfigurasi pada repo aplikasi asli.

Untuk pengumpulan, unggah berkas yang tercatat dalam Git, termasuk kedua folder dan konfigurasi tersembunyi `.gitignore` serta `.dockerignore`. Setelah unggah, gunakan tautan langsung ke `docker-compose.yml` dan `Dockerfile` pada Soal 1 Google Form.
