clear; clc; close all;
% =========================================================================
% GENERATE OUTPUT AUDIO (.wav) -- METODE3_V9M_TREBLE_BOOST_16K
%
% Script ini memproses satu atau beberapa file audio, menjalankan
% algoritma v9m (vocalBoostHighHz=16000, versi OFFLINE -- kualitas
% terbaik, dipakai untuk keperluan dokumentasi/deliverable), lalu
% menyimpan hasilnya sebagai file .wav baru.
%
% CATATAN: pakai versi OFFLINE (metode3_v9m_treble_boost_16k), BUKAN
% streaming, karena untuk file output/dokumentasi kita mau kualitas
% terbaik -- causal constraint streaming tidak relevan di sini karena
% tidak ada kebutuhan real-time processing utk keperluan ini.
% =========================================================================

%% 1. PENGATURAN -- edit sesuai kebutuhan
% Mode 'single'  : proses 1 file saja (isi inputFile)
% Mode 'folder'  : proses semua file .wav di dalam folder (isi inputFolder)
% Mode 'dataset' : proses lagu-lagu dari struktur dataset MUSDB (folder
%                  per-lagu berisi mixture.wav)
mode = 'single';   % ganti ke 'folder' atau 'dataset' sesuai kebutuhan

% --- untuk mode 'single' ---
inputFile = 'E:\coba\mixture.wav';   % ganti sesuai file kamu
outputName = 'careless_neffex_v9m_output.wav';        % nama file output

% % --- untuk mode 'folder' ---
% inputFolder = 'E:\lagu_bebas';   % folder isi file2 .wav biasa (bukan dataset)
% 
% % --- untuk mode 'dataset' ---
% datasetPath = 'E:\test';
% tracksToProcess = {'Punkdisco - Oral Hygiene', 'Carlos Gonzalez - A Place For Us'};
% % (isi nama folder lagu yang mau diproses, boleh 1 atau beberapa)

% --- lokasi simpan hasil (semua mode) ---
outputFolder = 'E:\output_v9m';
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

%% 2. PROSES SESUAI MODE
switch mode
    case 'single'
        fprintf('Memproses 1 file: %s\n', inputFile);
        [mix, fs] = audioread(inputFile);
        if size(mix,2) == 1
            mix = [mix, mix]; % mono -> stereo
        end
        y_out = metode3_v9m_treble_boost_16k(mix, fs);
        outPath = fullfile(outputFolder, outputName);
        audiowrite(outPath, y_out, fs);
        fprintf('Selesai! Tersimpan di: %s\n', outPath);

    case 'folder'
        files = dir(fullfile(inputFolder, '*.wav'));
        fprintf('Ditemukan %d file .wav di folder.\n\n', length(files));
        for i = 1:length(files)
            inPath = fullfile(inputFolder, files(i).name);
            fprintf('[%d/%d] Memproses: %s\n', i, length(files), files(i).name);

            [mix, fs] = audioread(inPath);
            if size(mix,2) == 1
                mix = [mix, mix];
            end
            y_out = metode3_v9m_treble_boost_16k(mix, fs);

            [~, baseName, ~] = fileparts(files(i).name);
            outPath = fullfile(outputFolder, [baseName '_v9m_output.wav']);
            audiowrite(outPath, y_out, fs);
            fprintf('   -> Tersimpan: %s\n\n', outPath);
        end
        fprintf('Semua file selesai diproses.\n');

    case 'dataset'
        fprintf('Memproses %d lagu dari dataset.\n\n', length(tracksToProcess));
        for i = 1:length(tracksToProcess)
            trackName = tracksToProcess{i};
            trackPath = fullfile(datasetPath, trackName, 'mixture.wav');
            fprintf('[%d/%d] Memproses: %s\n', i, length(tracksToProcess), trackName);

            [mix, fs] = audioread(trackPath);
            y_out = metode3_v9m_treble_boost_16k(mix, fs);

            % Bersihkan nama file dari karakter yang tidak valid utk nama file
            safeName = regexprep(trackName, '[^\w\-]', '_');
            outPath = fullfile(outputFolder, [safeName '_v9m_output.wav']);
            audiowrite(outPath, y_out, fs);
            fprintf('   -> Tersimpan: %s\n\n', outPath);
        end
        fprintf('Semua lagu selesai diproses.\n');

    otherwise
        error('Mode tidak dikenali. Gunakan ''single'', ''folder'', atau ''dataset''.');
end

fprintf('\n==================================================\n');
fprintf('SEMUA OUTPUT TERSIMPAN DI: %s\n', outputFolder);
fprintf('==================================================\n');
