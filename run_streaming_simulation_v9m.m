function y_out = run_streaming_simulation_v9m(x, fs)

if size(x,2) ~= 2
    error('Input harus stereo.');
end
L = x(:,1); R = x(:,2);

N = 2048; hop = N/4;
state = metode3_v9m_streaming_init(fs, N);

numHops = floor(length(L) / hop);
yL = zeros(numHops*hop, 1);
yR = zeros(numHops*hop, 1);

for i = 1:numHops
    idx = (i-1)*hop + (1:hop);
    Lh = L(idx);
    Rh = R(idx);
    [yLf, yRf, state] = metode3_v9m_streaming_frame(Lh, Rh, state);
    yL(idx) = yLf;
    yR(idx) = yRf;
end

y_out = [yL, yR];

% --- PROSES SOFT-LIMITER (Menahan Amplitudo Ekstrem secara Halus) ---
thresh = 0.95;
idx_clip = abs(y_out) > thresh;

% Sampel di atas 0.90 ditekan dengan fungsi tanh agar melengkung halus ke arah 1.0
if any(idx_clip(:))
    y_out(idx_clip) = sign(y_out(idx_clip)) .* (thresh + (1 - thresh) * tanh((abs(y_out(idx_clip)) - thresh) / (1 - thresh)));
end

% Batas absolut terakhir demi keamanan digital sebelum audiowrite
y_out = max(-0.99, min(0.99, y_out));

end