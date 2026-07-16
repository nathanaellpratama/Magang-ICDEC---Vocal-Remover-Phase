classdef VocalRemoverAppRealtime < matlab.apps.AppBase

    properties (Access = public)
        UIFigure       matlab.ui.Figure
        LoadButton     matlab.ui.control.Button
        PlayButton     matlab.ui.control.Button
        PauseButton    matlab.ui.control.Button
        StopButton     matlab.ui.control.Button
        VocalToggle    matlab.ui.control.StateButton
        StatusLabel    matlab.ui.control.Label
        FileLabel      matlab.ui.control.Label
        AxesLive       matlab.ui.control.UIAxes
        AxesCompare    matlab.ui.control.UIAxes
    end

    properties (Access = private)
        mixAudio      % audio original (stereo), full di memory
        fs
        deviceWriter  % audioDeviceWriter
        streamState   % state dari metode3_v8_streaming_init
        isPlaying = false
        isPaused = false
        stopRequested = false
        hop = 512
        N = 2048
        plotBufL          % buffer kecil utk grafik live (output aktual yg diputar)
        plotBufOriginal   % buffer sejajar utk grafik perbandingan (dry, sebelum efek)
        plotBufProcessed  % buffer sejajar utk grafik perbandingan (wet, hasil efek)
        currentHop = 0    % posisi playback saat ini (dlm satuan index hop), utk pause/resume
        lineLive          % handle objek garis di AxesLive (dibuat sekali, diupdate via YData)
        lineCompareOrig   % handle garis "Original" di AxesCompare
        lineCompareProc   % handle garis "Non-Vocal" di AxesCompare
        timingLog         % array struct timing per-hop, utk profiling (direset tiap Play dari awal)
    end

    methods (Access = private)

        function LoadButtonPushed(app, ~)
            [file, path] = uigetfile({'*.wav;*.mp3;*.flac','Audio Files'}, 'Pilih file audio');
            if isequal(file, 0)
                return;
            end
            fullPath = fullfile(path, file);
            app.StatusLabel.Text = 'Memuat audio...';
            drawnow;

            try
                [app.mixAudio, app.fs] = audioread(fullPath);
                if size(app.mixAudio,2) == 1
                    app.mixAudio = [app.mixAudio, app.mixAudio];
                end
            catch ME
                app.StatusLabel.Text = ['Gagal load: ' ME.message];
                return;
            end

            app.FileLabel.Text = ['File: ' file];
            app.StatusLabel.Text = sprintf('Siap diputar (%.1f detik, %d Hz). Tekan Play.', ...
                size(app.mixAudio,1)/app.fs, app.fs);
            app.PlayButton.Enable = 'on';

            cla(app.AxesLive);
            title(app.AxesLive, 'Menunggu playback...');
        end

        function PlayButtonPushed(app, ~)
            if isempty(app.mixAudio)
                app.StatusLabel.Text = 'Load audio terlebih dahulu.';
                return;
            end
            if app.isPlaying && ~app.isPaused
                return; % sudah jalan
            end

            hopsPerBlock = 4;

            if app.isPaused
                app.isPaused = false;
                app.isPlaying = true;
            else
                app.isPlaying = true;
                app.currentHop = 0;
                app.deviceWriter = audioDeviceWriter('SampleRate', app.fs, ...
                    'BufferSize', app.hop * hopsPerBlock * 2);
                app.streamState = metode3_v8_streaming_init(app.fs, app.N);
                app.plotBufL = zeros(app.fs, 1);
                app.plotBufOriginal = zeros(app.fs, 1);
                app.plotBufProcessed = zeros(app.fs, 1);
                app.timingLog = [];

                cla(app.AxesLive);
                app.lineLive = plot(app.AxesLive, ...
                    linspace(0,1,numel(app.plotBufL)), app.plotBufL);
                ylim(app.AxesLive, [-1 1]);

                cla(app.AxesCompare);
                app.lineCompareOrig = plot(app.AxesCompare, ...
                    linspace(0,1,numel(app.plotBufOriginal)), app.plotBufOriginal);
                hold(app.AxesCompare, 'on');
                app.lineCompareProc = plot(app.AxesCompare, ...
                    linspace(0,1,numel(app.plotBufProcessed)), app.plotBufProcessed);
                hold(app.AxesCompare, 'off');
                ylim(app.AxesCompare, [-1 1]);
                legend(app.AxesCompare, {'Original','Non-Vocal'}, 'Location', 'northeast');
                title(app.AxesCompare, 'Perbandingan: Original vs Non-Vocal');
            end

            app.stopRequested = false;
            app.PlayButton.Enable = 'off';
            app.LoadButton.Enable = 'off';
            app.PauseButton.Enable = 'on';
            app.StopButton.Enable = 'on';

            numHops = floor(size(app.mixAudio,1) / app.hop);
            plotCounter = 0;

            i = app.currentHop + 1;
            while i <= numHops
                if app.stopRequested || app.isPaused
                    app.currentHop = i - 1;
                    break;
                end

                blockEndHop = min(i + hopsPerBlock - 1, numHops);
                actualHopsInBlock = blockEndHop - i + 1;
                blockOut = zeros(hopsPerBlock * app.hop, 2);   
                blockOrig = zeros(hopsPerBlock * app.hop, 1);
                blockProc = zeros(hopsPerBlock * app.hop, 1);
                writePos = 1;

                vocalOn = app.VocalToggle.Value; 

                for hh = i:blockEndHop
                    idx = (hh-1)*app.hop + (1:app.hop);
                    Lh = app.mixAudio(idx, 1);
                    Rh = app.mixAudio(idx, 2);

                    if vocalOn
                        [yLf, yRf, app.streamState, tm] = metode3_v8_streaming_frame(Lh, Rh, app.streamState);
                        outHop = [yLf, yRf];
                        procL = yLf;
                        if isempty(app.timingLog)
                            app.timingLog = tm;
                        else
                            app.timingLog(end+1) = tm; 
                        end
                    else
                        outHop = [Lh, Rh];
                        procL = Lh;
                    end

                    wIdx = writePos:(writePos+app.hop-1);
                    blockOut(wIdx, :) = outHop;
                    blockOrig(wIdx) = Lh;
                    blockProc(wIdx) = procL;
                    writePos = writePos + app.hop;
                end

                app.deviceWriter(blockOut);
                i = blockEndHop + 1;
                app.currentHop = blockEndHop;

                % --- update grafik ---
                nNew = size(blockOut,1);
                app.plotBufL = [app.plotBufL(nNew+1:end); blockOut(:,1)];
                app.plotBufOriginal = [app.plotBufOriginal(nNew+1:end); blockOrig];
                app.plotBufProcessed = [app.plotBufProcessed(nNew+1:end); blockProc];

                plotCounter = plotCounter + 1;
                if mod(plotCounter, 3) == 0
                    if vocalOn
                        statusTxt = 'Memutar (Vocal Remover: ON)...';
                    else
                        statusTxt = 'Memutar (Vocal Remover: OFF)...';
                    end
                    app.StatusLabel.Text = statusTxt;
                    app.lineLive.YData = app.plotBufL;
                    app.lineCompareOrig.YData = app.plotBufOriginal;
                    app.lineCompareProc.YData = app.plotBufProcessed;
                    title(app.AxesLive, statusTxt);
                    drawnow limitrate;
                end
            end

            app.isPlaying = false;
            if app.isPaused
                app.StatusLabel.Text = 'Dijeda (Pause). Tekan Play untuk lanjut.';
                app.PlayButton.Enable = 'on';
                app.PauseButton.Enable = 'off';
                app.LoadButton.Enable = 'off';
                app.StopButton.Enable = 'on';
                return;
            end

            release(app.deviceWriter);
            app.PlayButton.Enable = 'on';
            app.LoadButton.Enable = 'on';
            app.PauseButton.Enable = 'off';
            app.StopButton.Enable = 'off';
            if app.stopRequested
                app.StatusLabel.Text = 'Playback dihentikan (Stop). Tekan Play untuk mulai dari awal.';
            else
                app.StatusLabel.Text = 'Playback selesai.';
                app.currentHop = 0;
            end
            app.printTimingSummary();
        end

        function printTimingSummary(app)
            if isempty(app.timingLog)
                fprintf('\n[Timing] Tidak ada data (Vocal Remover tidak pernah ON selama playback).\n');
                return;
            end
            hopBudgetMs = (app.hop / app.fs) * 1000;
            fields = fieldnames(app.timingLog);
            fprintf('\n================== RINGKASAN TIMING PER-HOP ==================\n');
            fprintf('Jumlah hop terekam : %d\n', numel(app.timingLog));
            fprintf('Budget waktu/hop    : %.3f ms (real-time deadline)\n\n', hopBudgetMs);
            fprintf('%-24s %10s %10s %10s\n', 'Komponen', 'Rata2(ms)', 'Max(ms)', '% Budget');
            fprintf('%-24s %10s %10s %10s\n', repmat('-',1,24), repmat('-',1,10), repmat('-',1,10), repmat('-',1,10));
            for i = 1:numel(fields)
                fname = fields{i};
                vals = [app.timingLog.(fname)] * 1000; % ms
                fprintf('%-24s %10.4f %10.4f %9.1f%%\n', fname, mean(vals), max(vals), 100*mean(vals)/hopBudgetMs);
            end
            fprintf('================================================================\n');
            totalVals = [app.timingLog.total] * 1000;
            overBudgetCount = sum(totalVals > hopBudgetMs);
            if overBudgetCount > 0
                fprintf(2, 'PERINGATAN: %d dari %d hop (%.1f%%) MELEBIHI budget real-time!\n', ...
                    overBudgetCount, numel(totalVals), 100*overBudgetCount/numel(totalVals));
            else
                fprintf('Semua hop selesai dalam budget real-time. Rata-rata pemakaian: %.1f%% dari budget.\n', ...
                    100*mean(totalVals)/hopBudgetMs);
            end
            fprintf('================================================================\n\n');
        end

        function PauseButtonPushed(app, ~)
            if app.isPlaying
                app.isPaused = true; % loop akan berhenti di iterasi berikutnya & simpan currentHop
            end
        end

        function StopButtonPushed(app, ~)
            app.stopRequested = true;
            app.isPaused = false;
            app.currentHop = 0; % Stop = reset ke awal
            if ~isempty(app.deviceWriter)
                try
                    release(app.deviceWriter);
                catch
                end
            end
        end

        function VocalTogglePushed(app, ~)
            if app.VocalToggle.Value
                app.VocalToggle.Text = 'Vocal Remover: ON';
            else
                app.VocalToggle.Text = 'Vocal Remover: OFF';
            end
        end
    end

    methods (Access = public)
        function app = VocalRemoverAppRealtime
            createComponents(app)
        end

        function delete(app)
            app.stopRequested = true;
            if ~isempty(app.deviceWriter)
                try
                    release(app.deviceWriter);
                catch
                end
            end
            delete(app.UIFigure);
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name', 'Vocal Remover Phase - Real-Time Demo', 'Position', [100 100 900 700]);

            mainGrid = uigridlayout(app.UIFigure, [5, 1]);
            mainGrid.RowHeight = {22, 40, 22, '1x', '1x'};
            mainGrid.ColumnWidth = {'1x'};
            mainGrid.RowSpacing = 8;
            mainGrid.Padding = [15 15 15 15];

            app.FileLabel = uilabel(mainGrid, 'Text', 'Belum ada file dimuat.');
            app.FileLabel.Layout.Row = 1; app.FileLabel.Layout.Column = 1;

            btnGrid = uigridlayout(mainGrid, [1, 5]);
            btnGrid.Layout.Row = 2; btnGrid.Layout.Column = 1;
            btnGrid.ColumnWidth = {110, 90, 90, 90, 180};
            btnGrid.Padding = [0 0 0 0];
            btnGrid.ColumnSpacing = 10;

            app.LoadButton = uibutton(btnGrid, 'push', 'Text', 'Load Audio', ...
                'ButtonPushedFcn', @(btn,event) LoadButtonPushed(app, event));
            app.LoadButton.Layout.Row = 1; app.LoadButton.Layout.Column = 1;

            app.PlayButton = uibutton(btnGrid, 'push', 'Text', 'Play', 'Enable', 'off', ...
                'ButtonPushedFcn', @(btn,event) PlayButtonPushed(app, event));
            app.PlayButton.Layout.Row = 1; app.PlayButton.Layout.Column = 2;

            app.PauseButton = uibutton(btnGrid, 'push', 'Text', 'Pause', 'Enable', 'off', ...
                'ButtonPushedFcn', @(btn,event) PauseButtonPushed(app, event));
            app.PauseButton.Layout.Row = 1; app.PauseButton.Layout.Column = 3;

            app.StopButton = uibutton(btnGrid, 'push', 'Text', 'Stop', 'Enable', 'off', ...
                'ButtonPushedFcn', @(btn,event) StopButtonPushed(app, event));
            app.StopButton.Layout.Row = 1; app.StopButton.Layout.Column = 4;

            app.VocalToggle = uibutton(btnGrid, 'state', 'Text', 'Vocal Remover: OFF', ...
                'Value', false, ...
                'ValueChangedFcn', @(btn,event) VocalTogglePushed(app, event));
            app.VocalToggle.Layout.Row = 1; app.VocalToggle.Layout.Column = 5;

            app.StatusLabel = uilabel(mainGrid, 'Text', 'Status: menunggu file audio.', ...
                'FontColor', [0.3 0.3 0.3]);
            app.StatusLabel.Layout.Row = 3; app.StatusLabel.Layout.Column = 1;

            app.AxesLive = uiaxes(mainGrid);
            app.AxesLive.Layout.Row = 4; app.AxesLive.Layout.Column = 1;
            title(app.AxesLive, 'Live waveform - output aktual (1 detik terakhir)');

            app.AxesCompare = uiaxes(mainGrid);
            app.AxesCompare.Layout.Row = 5; app.AxesCompare.Layout.Column = 1;
            title(app.AxesCompare, 'Perbandingan: Original vs Non-Vocal');

            app.UIFigure.Visible = 'on';
        end
    end
end