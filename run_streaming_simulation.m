function y_out = run_streaming_simulation(x, fs)

if size(x,2) ~= 2
    error('Input harus stereo.');
end
L = x(:,1); R = x(:,2);

N = 2048; hop = N/4;
state = metode3_v8_streaming_init(fs, N);

numHops = floor(length(L) / hop);
yL = zeros(numHops*hop, 1);
yR = zeros(numHops*hop, 1);

for i = 1:numHops
    idx = (i-1)*hop + (1:hop);
    Lh = L(idx);
    Rh = R(idx);
    [yLf, yRf, state] = metode3_v8_streaming_frame(Lh, Rh, state);
    yL(idx) = yLf;
    yR(idx) = yRf;
end

y_out = [yL, yR];
y_out = y_out ./ (max(abs(y_out(:))) + eps) * 0.95;

end
