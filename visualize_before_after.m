clear; clc; close all;

%% 1. PENGATURAN -- edit sesuai kebutuhan
inputFile = 'E:\coba\mixture.wav';  % GANTI sesuai lagu
outputFolder = 'D:\Nathanael\Telkom University\Semester 6\Kerja Praktek\ICDEC\Vocal Remover Phase MATLAB\Visualisasi';
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

%% 2. LOAD & PROSES AUDIO
fprintf('Memuat: %s\n', inputFile);
[mix, fs] = audioread(inputFile);
if size(mix,2) == 1
    mix = [mix, mix];
end

fprintf('Menjalankan algoritma v9m...\n');
y_out = metode3_v9m_treble_boost_16k(mix, fs);

% Pakai channel L saja utk visualisasi (biar tidak dobel/rumit)
mixMono = mix(:,1);
outMono = y_out(:,1);
minLen = min(length(mixMono), length(outMono));
mixMono = mixMono(1:minLen);
outMono = outMono(1:minLen);
t = (0:minLen-1) / fs;

%% 3. PARAMETER SPECTROGRAM
winLen = 2048;
overlap = round(winLen * 0.75);
nfft = 2048;

%% FIGURE 1: WAVEFORM PERBANDINGAN (domain waktu)
fig1 = figure('Position', [50 50 1200 500], 'Color', 'w');

subplot(2,1,1);
plot(t, mixMono, 'Color', [0.2 0.4 0.8]);
title('Waveform Asli (Mixture)');
xlabel('Waktu (detik)'); ylabel('Amplitudo');
xlim([0 t(end)]); ylim([-1 1]); grid on;

subplot(2,1,2);
plot(t, outMono, 'Color', [0.8 0.3 0.2]);
title('Waveform Output (Non-Vocal, v9m)');
xlabel('Waktu (detik)'); ylabel('Amplitudo');
xlim([0 t(end)]); ylim([-1 1]); grid on;

sgtitle('Perbandingan Waveform: Sebelum vs Sesudah Vocal Removal', 'FontWeight', 'bold');
saveas(fig1, fullfile(outputFolder, '1_waveform_comparison.png'));
fprintf('Tersimpan: 1_waveform_comparison.png\n');

%% FIGURE 2: SPEKTRUM FREKUENSI (rata-rata keseluruhan, domain frekuensi)
fig2 = figure('Position', [50 50 1200 500], 'Color', 'w');

N_fft = 2^nextpow2(minLen);
freqAxis = (0:N_fft/2-1) * (fs / N_fft);

MixSpec = abs(fft(mixMono, N_fft));
OutSpec = abs(fft(outMono, N_fft));
MixSpecDb = 20*log10(MixSpec(1:N_fft/2) + eps);
OutSpecDb = 20*log10(OutSpec(1:N_fft/2) + eps);

semilogx(freqAxis, MixSpecDb, 'Color', [0.2 0.4 0.8], 'LineWidth', 1.2); hold on;
semilogx(freqAxis, OutSpecDb, 'Color', [0.8 0.3 0.2], 'LineWidth', 1.2);
xlabel('Frekuensi (Hz)'); ylabel('Magnitude (dB)');
title('Perbandingan Spektrum Frekuensi: Mixture vs Output');
legend('Mixture (Asli)', 'Output (Non-Vocal)', 'Location', 'southwest');
xlim([20 fs/2]); grid on;
hold off;

saveas(fig2, fullfile(outputFolder, '2_frequency_spectrum.png'));
fprintf('Tersimpan: 2_frequency_spectrum.png\n');

%% FIGURE 3: SPECTROGRAM PERBANDINGAN (waktu-frekuensi)
fig3 = figure('Position', [50 50 1300 700], 'Color', 'w');

subplot(2,1,1);
spectrogram(mixMono, hamming(winLen), overlap, nfft, fs, 'yaxis');
title('Spectrogram Mixture (Asli)');
colormap(gca, 'jet');
c1 = colorbar; c1.Label.String = 'Magnitude (dB)';
ylim([0 fs/2/1000]);

subplot(2,1,2);
spectrogram(outMono, hamming(winLen), overlap, nfft, fs, 'yaxis');
title('Spectrogram Output (Non-Vocal, v9m)');
colormap(gca, 'jet');
c2 = colorbar; c2.Label.String = 'Magnitude (dB)';
ylim([0 fs/2/1000]);

sgtitle('Perbandingan Spectrogram: Sebelum vs Sesudah Vocal Removal', 'FontWeight', 'bold');
saveas(fig3, fullfile(outputFolder, '3_spectrogram_comparison.png'));
fprintf('Tersimpan: 3_spectrogram_comparison.png\n');

%% FIGURE 4: PETA GAIN/REDAMAN -- SELISIH spectrogram (yang paling jelas
%% menunjukkan "mana yang diredam")
fig4 = figure('Position', [50 50 1300 500], 'Color', 'w');

[S_mix, F, T] = spectrogram(mixMono, hamming(winLen), overlap, nfft, fs);
[S_out, ~, ~] = spectrogram(outMono, hamming(winLen), overlap, nfft, fs);

magMixDb = 20*log10(abs(S_mix) + eps);
magOutDb = 20*log10(abs(S_out) + eps);

% Selisih = seberapa banyak diredam (nilai negatif = diredam, 0 = tidak berubah)
diffDb = magOutDb - magMixDb;
diffDb(diffDb > 0) = 0;   % clip: fokus hanya pada REDAMAN, bukan penguatan
diffDb(diffDb < -40) = -40; % batasi skala biar visual tidak terlalu ekstrem

imagesc(T, F/1000, diffDb);
axis xy;
colormap(gca, flipud(hot));   % warna gelap/merah = diredam banyak
c3 = colorbar;
c3.Label.String = 'Reduksi Level (dB) -- semakin negatif = semakin diredam';
clim([-40 0]);
xlabel('Waktu (detik)'); ylabel('Frekuensi (kHz)');
title('Peta Reduksi/Redaman -- Area yang Ditekan oleh Algoritma (Vokal)');
ylim([0 fs/2/1000]);

saveas(fig4, fullfile(outputFolder, '4_reduction_map.png'));
fprintf('Tersimpan: 4_reduction_map.png\n');

fprintf('\n==================================================\n');
fprintf('SEMUA GRAFIK TERSIMPAN DI: %s\n', outputFolder);
fprintf('==================================================\n');
fprintf('1_waveform_comparison.png   -> domain waktu, sebelum vs sesudah\n');
fprintf('2_frequency_spectrum.png    -> domain frekuensi (rata-rata), sebelum vs sesudah\n');
fprintf('3_spectrogram_comparison.png -> spectrogram waktu-frekuensi, sebelum vs sesudah\n');
fprintf('4_reduction_map.png         -> peta area yang diredam (paling jelas utk mentor)\n');
