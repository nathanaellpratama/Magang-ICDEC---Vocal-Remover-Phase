function y_out = run_streaming_simulation_v9e(x, fs)
% RUN_STREAMING_SIMULATION_V9E
% Sama seperti run_streaming_simulation.m, tapi pakai
% metode3_v9e_streaming_init/_frame (vocalBoostHighHz=8000).
% Untuk simulasi offline / batch compare kalau diperlukan.

if size(x,2) ~= 2
    error('Input harus stereo.');
end
L = x(:,1); R = x(:,2);

N = 2048; hop = N/4;
state = metode3_v9e_streaming_init(fs, N);

numHops = floor(length(L) / hop);
yL = zeros(numHops*hop, 1);
yR = zeros(numHops*hop, 1);

for i = 1:numHops
    idx = (i-1)*hop + (1:hop);
    Lh = L(idx);
    Rh = R(idx);
    [yLf, yRf, state] = metode3_v9e_streaming_frame(Lh, Rh, state);
    yL(idx) = yLf;
    yR(idx) = yRf;
end

y_out = [yL, yR];
y_out = y_out ./ (max(abs(y_out(:))) + eps) * 0.95;

end
