clear; close all;

datasetPath = 'E:\train';
folders = dir(datasetPath);
folders = folders([folders.isdir] & ~ismember({folders.name}, {'.', '..'}));
numTracks = min(100   , length(folders));

if numTracks == 0
    error('Folder test kosong atau path salah! Periksa kembali datasetPath.');
end
fprintf('Ditemukan %d lagu untuk dievaluasi.\n\n', numTracks);

SDR_results = nan(numTracks, 1);
SIR_results = nan(numTracks, 1);
SAR_results = nan(numTracks, 1);

tic;
for i = 1:numTracks
    trackName = folders(i).name;
    trackPath = fullfile(datasetPath, trackName);

    % a. Load audio
    [mix, fs]   = audioread(fullfile(trackPath, 'mixture.wav'));
    [vocals, ~] = audioread(fullfile(trackPath, 'vocals.wav'));

    % b. Ground truth accompaniment
    target_accompaniment = mix - vocals;

    % c. Jalankan algoritma
    estimated_accompaniment = metode3_v9m_treble_boost_16k(mix, fs);

    % c2. Kompensasi delay sistematis streaming
    estimated_accompaniment = align_streaming_output(estimated_accompaniment, mix, fs);

    % d. Sinkronisasi panjang
    minLength = min([size(mix,1), size(vocals,1), size(estimated_accompaniment,1)]);
    mix_c    = mix(1:minLength, :);
    vocals_c = vocals(1:minLength, :);
    target_c = target_accompaniment(1:minLength, :);
    est_c    = estimated_accompaniment(1:minLength, :);

    % Estimasi vokal (residual): apa yang "dihilangkan" oleh algoritma
    % dari mixture -- inilah yg dipakai sbg interferer di evaluasi
    est_vocal_c = mix_c - est_c;

    try
        % ---- CHANNEL L: accompaniment vs vocal ----
        se_L     = [target_c(:,1)'; vocals_c(:,1)'];
        se_hat_L = [est_c(:,1)';    est_vocal_c(:,1)'];
        [sdrL, sirL, sarL, ~] = bss_eval_sources(se_hat_L, se_L);

        % ---- CHANNEL R: accompaniment vs vocal ----
        se_R     = [target_c(:,2)'; vocals_c(:,2)'];
        se_hat_R = [est_c(:,2)';    est_vocal_c(:,2)'];
        [sdrR, sirR, sarR, ~] = bss_eval_sources(se_hat_R, se_R);

        SDR_results(i) = mean([sdrL(1), sdrR(1)]);
        SIR_results(i) = mean([sirL(1), sirR(1)]);
        SAR_results(i) = mean([sarL(1), sarR(1)]);

        fprintf('[%2d/%d] %s\n     -> SDR: %.2f dB | SIR: %.2f dB | SAR: %.2f dB\n', ...
            i, numTracks, trackName, SDR_results(i), SIR_results(i), SAR_results(i));
    catch ME
        fprintf('[%2d/%d] %s -> Gagal evaluasi: %s\n', i, numTracks, trackName, ME.message);
    end
end
waktu_total = toc;

fprintf('\n==================================================\n');
fprintf('     HASIL EVALUASI AKHIR TERVERIFIKASI (%d LAGU)\n', numTracks);
fprintf('==================================================\n');
fprintf('Median SDR : %.2f dB (Kualitas keseluruhan)\n', median(SDR_results, 'omitnan'));
fprintf('Median SIR : %.2f dB (Kebersihan dari BOCORAN VOKAL sesungguhnya)\n', median(SIR_results, 'omitnan'));
fprintf('Median SAR : %.2f dB (Tingkat distorsi/artefak fasa)\n', median(SAR_results, 'omitnan'));
fprintf('Total Waktu Eksekusi: %.2f detik\n', waktu_total);
fprintf('Jumlah lagu berhasil dievaluasi: %d / %d\n', sum(~isnan(SDR_results)), numTracks);
