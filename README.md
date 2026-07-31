# Vocal Remover Phase — Sub-band PLV+IPD

Algoritma vocal remover murni berbasis fasa (**phase-based**), dikembangkan sebagai bagian dari program **Kerja Praktik (KP)** di **ICDEC (Indonesia Chip Design Collaborative Center)**, kolaborasi non-profit antara Polytron dan universitas-universitas di Indonesia.

Proyek ini merupakan bagian dari inisiatif **"New Audio Effect Exploration"**, dengan target akhir deployment pada chip DSP Polytron. Scope resmi KP adalah *modelling and software*, namun seluruh keputusan pengembangan diarahkan agar **chip-ready**: real-time capable, kompleksitas komputasi rendah, dan kompatibel dengan Simulink/code generation.

---

## Ringkasan Metode

Algoritma menggunakan **Sub-band Phase Locking Value (PLV)** dikombinasikan dengan **Interaural Phase Difference (IPD)** — diadaptasi dari literatur neuroscience (Lachaux et al., 1999) ke domain audio stereo, **tanpa Mid/Side encoding** (constraint eksplisit dari pembimbing, karena M/S sudah digunakan di proyek sebelumnya).

Evaluasi performa menggunakan metrik **BSS Eval (SDR/SIR/SAR)** pada dataset **MUSDB18-HQ**.

### Hasil Akhir (v9m)

Divalidasi pada 50 lagu test set MUSDB18-HQ dengan metodologi BSS Eval yang telah dikoreksi:

| Metrik | Median |
|---|---|
| SDR | ≈ 9.30 – 9.31 dB |
| SIR | ≈ 15.93 – 16.07 dB |
| SAR | ≈ 10.64 – 11.06 dB |

**Real-time streaming performance:**
- RTF ≈ 0.113
- Latency ≈ 34.83 ms (1536 samples)
- CPU usage ≈ 13.6% per hop (1.58 ms rata-rata dari budget 11.6 ms)

> **Catatan keterbatasan:** Metode pure-phase secara fundamental tidak bisa mencapai vocal removal sempurna. Bass/kick yang mono-korelasi akan ikut tereduksi, sementara vokal reverberant sebagian bisa lolos deteksi. Target realistis adalah reduksi signifikan, bukan eliminasi total — SAR menjadi gap utama dibanding metode deep learning.

---

## Struktur File

### 🎯 Algoritma Inti
| File | Deskripsi |
|---|---|
| `metode3_v9m_treble_boost_16k.m` | Versi final algoritma (v9m), ekstensi `vocalBoostHighHz` hingga 16.000 Hz |

### 🔴 Real-Time Streaming
| File | Deskripsi |
|---|---|
| `metode3_v9m_streaming_init.m` | Inisialisasi state untuk pemrosesan streaming (causal) |
| `metode3_v9m_streaming_frame.m` | Pemrosesan per-frame untuk real-time |
| `run_streaming_simulation_v9m.m` | Simulasi/runner streaming versi v9m |
| `align_streaming_output.m` | Penyelarasan output streaming untuk evaluasi |

### 📊 Evaluasi
| File | Deskripsi |
|---|---|
| `batch_compare_FINAL_verified.m` | **Script evaluasi utama (valid)** — mengevaluasi tiap channel L/R secara terpisah dengan vokal sebagai interfering source eksplisit |
| `bss_eval_sources.m` | Implementasi BSS Eval v3 (Vincent et al., 2006) |
| `bss_eval_images.m` | Evaluasi BSS Eval berbasis image/spatial |
| `bss_eval_mix.m` | Utilitas evaluasi untuk sinyal mix |
| `generate_output_v9m.m` | Generate output audio hasil pemrosesan v9m untuk keperluan evaluasi |

### 🖥️ Aplikasi & Visualisasi
| File | Deskripsi |
|---|---|
| `VocalRemoverAppRealtime_v9m.m` | Aplikasi MATLAB App Designer — Play/Pause/Stop, toggle vocal remover ON/OFF, dual waveform graph real-time, timing profiler |
| `visualize_before_after.m` | Visualisasi perbandingan sinyal sebelum/sesudah pemrosesan |

### 🔧 Simulink
| File | Deskripsi |
|---|---|
| `Blok_Diagram_RealTime.slx` | Model Simulink real-time vocal remover, dibangun di atas versi streaming causal (v9m) |
| `precompute_cfg.m` | Precompute seluruh parameter/struct konfigurasi (band allocation, `bandMask`, `protectGain`, `boostRamp`, `sigmaIPDperBand`, koefisien attack/release, dsb.) secara **offline**, menghasilkan `cfgData` yang murni numerik dan fixed-layout — siap dipakai sebagai input block Simulink tanpa memanggil fungsi non-codegen (`discretize`, `unique`, dll.) di dalam model |

Model Simulink (`Blok_Diagram_RealTime.slx`) dibangun di atas versi streaming causal, dengan seluruh masalah code generation telah diselesaikan (lihat bagian **Catatan Teknis** di bawah).

> **Catatan konteks:** Eksplorasi Simulink ini merupakan inisiatif mandiri di luar arahan langsung pembimbing (Ferriady) — dilakukan sebagai eksplorasi tambahan menuju kesiapan deployment ke chip DSP Polytron. Progresnya tetap tercatat di logbook harian dan laporan KP.

---

## Cara Penggunaan

Urutan eksekusi yang disarankan:

1. **Generate output** dari algoritma pada dataset test:
   ```matlab
   generate_output_v9m
   ```
2. **Evaluasi hasil** menggunakan metodologi yang sudah dikoreksi:
   ```matlab
   batch_compare_FINAL_verified
   ```
3. **Visualisasi** (opsional, untuk inspeksi kualitatif):
   ```matlab
   visualize_before_after
   ```
4. **Simulasi streaming** (untuk uji real-time performance):
   ```matlab
   run_streaming_simulation_v9m
   ```
5. **Jalankan aplikasi interaktif**:
   ```matlab
   VocalRemoverAppRealtime_v9m
   ```
6. **(Opsional) Siapkan config lalu buka model Simulink:**
   ```matlab
   cfgData = precompute_cfg(fs, N);
   ```
   `cfgData` inilah yang di-load sebagai parameter awal ke workspace sebelum membuka/mensimulasikan `Blok_Diagram_RealTime.slx` (fixed-layout, numerik murni, aman untuk code generation).

> ⚠️ **Jangan gunakan `bss_eval_sources.m` secara langsung untuk evaluasi stereo L/R** tanpa melalui `batch_compare_FINAL_verified.m` — versi mentah memperlakukan channel L/R sebagai *competing sources*, yang menyebabkan nilai SIR ter-inflate.

---

## Requirements

- **MATLAB R2026a** (atau versi kompatibel)
- Signal Processing Toolbox
- Simulink & Simulink Coder (jika menjalankan/mengedit model Simulink)
- Dataset **MUSDB18-HQ** (tidak disertakan dalam repo, unduh terpisah)
- Python + `museval` (opsional, untuk evaluasi eksternal/cross-check — lihat `evaluate_vrm23_fixed.py` jika disertakan)

---

## Catatan Teknis Penting

### Perbaikan Audio Normalization
Normalisasi peak whole-signal (`y_out ./ max(abs(y_out(:))) * 0.95`) menyebabkan gain shift tak terduga antar lagu dan SDR sangat rendah pada evaluasi museval eksternal. **Diganti dengan soft-limiter berbasis `tanh`** (hanya memengaruhi sample yang melewati threshold 0.95) plus hard clamp di ±0.99. Versi streaming secara arsitektur sudah bersih dari isu ini karena sifatnya causal/frame-based.

### Kompatibilitas Simulink Code Generation
Fungsi-fungsi berikut **tidak kompatibel dengan codegen** dan telah digantikan:
| Fungsi bermasalah | Pengganti |
|---|---|
| `xcorr` | Autokorelasi manual |
| `corr`, `discretize`, `unique`, `conv2`, `prctile`, `medfilt1` | EMA, ring buffer causal, running statistics, atau precompute offline |

Perbaikan tambahan untuk Simulink Coder:
- Struct fields harus **fixed-layout** saat compile time — pola inisialisasi lazy (`isfield`) dipindah ke fungsi init
- `cfg.bandBins` dikonversi dari cell array menjadi matriks numerik `bandMask` (N × numBands)
- Demux/Mux digantikan dengan penanganan matriks langsung (512×2) + blok Matrix Concatenate
- Sample rate Audio Device Writer diset manual ke 44100 Hz untuk menghindari mismatch

### Evaluasi Eksternal (museval)
Setelah perbaikan soft-limiter, hasil Acc_SDR pada evaluasi museval eksternal meningkat dari **0.22 → 5.59**. Gap yang tersisa terhadap metodologi internal (BSS Eval v3) disebabkan oleh perbedaan pendekatan **framewise (museval/v4) vs. global/per-channel (BSS Eval v3)**, bukan indikasi masalah kualitas algoritma.

### Caveat Benchmark
Proyek ini melakukan separasi **2-way** (vokal vs. accompaniment), sementara benchmark publik seperti Open-Unmix dan E-MRP-CNN melakukan separasi **4-stem**. Perbandingan angka bersifat *reference-for-scale* saja, bukan evaluasi yang setara.

---

## Riwayat Versi

Pengembangan dilakukan secara iteratif (v2 → v9m) dengan batch testing lintas genre lagu untuk memvalidasi tiap perubahan. Versi final **v9m** merupakan hasil ekstensi `vocalBoostHighHz` ke 16 kHz, dimotivasi oleh temuan diagnostik bahwa band treble memiliki `centerScoreBand` yang sebanding dengan band vocal-boost namun suppression yang jauh lebih rendah.

---

## Referensi

- Lachaux, J.-P., et al. (1999). *Measuring phase synchrony in brain signals.* — dasar konsep PLV
- Barry, D., et al. (2004). *ADRess* — Azimuth Discrimination and Resynthesis
- Yilmaz, Ö., & Rickard, S. (2004). *DUET* — Blind separation of speech mixtures via time-frequency masking
- Fitzgerald, D., et al. (2016). *PROJET*
- Rabiner, L. R. (1977). Pitch detection menggunakan autocorrelation
- Vincent, E., et al. (2006). *BSS Eval v3* — Performance measurement in blind audio source separation
- Zölzer, U. (2011). *DAFX: Digital Audio Effects*

---

## Lisensi & Konteks

Repositori ini didokumentasikan sebagai bagian dari laporan akhir Kerja Praktik. Model Simulink (jika ada) merupakan eksplorasi mandiri di luar arahan langsung pembimbing.
