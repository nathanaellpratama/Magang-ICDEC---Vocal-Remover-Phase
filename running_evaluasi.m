clear; clc; close all;

% 1. PENGATURAN PATH
% TULIS PATH KE FOLDER 'test' HASIL UNZIP
datasetPath = 'E:\train'; 

% Membaca semua sub-folder lagu
folders = dir(datasetPath);
folders = folders([folders.isdir] & ~ismember({folders.name}, {'.', '..'}));
numTracks = 50;

if numTracks == 0
    error('Folder test kosong atau path salah! Periksa kembali datasetPath kamu.');
end

fprintf('Ditemukan %d lagu untuk dievaluasi.\n\n', numTracks);

% Array untuk menampung hasil skor tiap lagu
SDR_results = zeros(numTracks, 1);
SIR_results = zeros(numTracks, 1);
SAR_results = zeros(numTracks, 1);

% 2. LOOP PROCESSING & EVALUASI
tic; % Mulai hitung waktu
for i = 1:numTracks
    trackName = folders(i).name;
    trackPath = fullfile(datasetPath, trackName);

    % a. Load Audio (Mixture dan Vocals)
    [mix, fs]   = audioread(fullfile(trackPath, 'mixture.wav'));
    [vocals, ~] = audioread(fullfile(trackPath, 'vocals.wav'));

    % b. Ambil Ground Truth Accompaniment (Target Ideal = Musik Tanpa Vokal)
    target_accompaniment = mix - vocals; 

    % c. Jalankan Algoritma Vocal Remover Fasa Milikmu
    estimated_accompaniment = metode3_v8_sar_tuning(mix, fs);

    % d. Sinkronisasi Panjang Sinyal (Antisipasi efek STFT/Windowing)
    lenTarget = size(target_accompaniment, 1);
    lenEst = size(estimated_accompaniment, 1);
    minLength = min(lenTarget, lenEst);

    target_clean = target_accompaniment(1:minLength, :);
    estimated_clean = estimated_accompaniment(1:minLength, :);

    % e. Transpose Matriks ke [Channels x Samples] sesuai standar BSS_Eval
    se     = target_clean';
    se_hat = estimated_clean';

    % f. Hitung Metrik Menggunakan Fungsi BSS_Eval
    try
        [sdr, sir, sar, ~] = bss_eval_sources(se_hat, se);

        % Rata-ratakan nilai Channel Kiri (L) dan Kanan (R)
        SDR_results(i) = mean(sdr);
        SIR_results(i) = mean(sir);
        SAR_results(i) = mean(sar);

        fprintf('[%2d/%d] %s \n     -> SDR: %.2f dB | SIR: %.2f dB | SAR: %.2f dB\n', ...
            i, numTracks, trackName, SDR_results(i), SIR_results(i), SAR_results(i));
    catch ME
        fprintf('[%2d/%d] %s -> Gagal evaluasi: %s\n', i, numTracks, trackName, ME.message);
    end
end
waktu_total = toc;

% 3. REKAPITULASI HASIL AKHIR (STANDAR MEDIAN)
fprintf('\n==================================================\n');
fprintf('           HASIL EVALUASI AKHIR (%d LAGU)         \n', numTracks);
fprintf('==================================================\n');
fprintf('Median SDR : %.2f dB (Kualitas keseluruhan)\n', median(SDR_results));
fprintf('Median SIR : %.2f dB (Kebersihan penghilangan vokal)\n', median(SIR_results));
fprintf('Median SAR : %.2f dB (Tingkat distorsi/artefak fasa)\n', median(SAR_results));
fprintf('Total Waktu Eksekusi: %.2f detik\n', waktu_total);