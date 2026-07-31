function [y_aligned, estimatedDelay] = align_streaming_output(y_out, x_original, fs, maxDelayMs)

if nargin < 4
    maxDelayMs = 200;
end
maxDelaySamples = round(maxDelayMs/1000 * fs);

refCh = x_original(:,1);
outCh = y_out(:,1);

% Cross-correlation utk cari delay yg memaksimalkan korelasi
[c, lags] = xcorr(outCh, refCh, maxDelaySamples);
[~, idxMax] = max(abs(c));
estimatedDelay = lags(idxMax);

fprintf('[Align] Delay terdeteksi: %d sample (%.2f ms)\n', ...
    estimatedDelay, estimatedDelay/fs*1000);

% Jika estimatedDelay > 0, artinya y_out "telat" -> geser mundur (buang awal)
% Jika estimatedDelay < 0, artinya y_out "lebih cepat" -> tambah silence di awal
N = size(y_out,1);
if estimatedDelay > 0
    y_aligned = [y_out(estimatedDelay+1:end, :); zeros(estimatedDelay, size(y_out,2))];
elseif estimatedDelay < 0
    d = abs(estimatedDelay);
    y_aligned = [zeros(d, size(y_out,2)); y_out(1:end-d, :)];
else
    y_aligned = y_out;
end
y_aligned = y_aligned(1:N, :); % pastikan panjang tetap sama

end
