function y_out = metode3_v8_sar_tuning(x, fs)

%%  PARAMETER ALGORITMA
N   = 2048;
hop = N/4;
fminBand        = 50;
formantLowHz    = 150;
formantHighHz   = 4500;
nBandsBass      = 6;
nBandsFormant   = 20;
nBandsTreble    = 8;
protectedBandHz     = 150;
protectedRampBands  = 5;      
sigmaIPD   = 0.8;
plvFloor   = 0.15;
plvGamma   = 0.22;
timeSmoothFrames = 11;        
depth            = 0.95;
vocalBoostLowHz  = 200;
vocalBoostHighHz = 4000;
vocalBoostFactor = 1.6;
rampWidthHz      = 150;
attackMs  = 20;
releaseMs = 200;              
fcDC = 15;
corrLRWarnThresh   = 0.88;
corrLRHardThresh   = 0.96;
minDepthScale      = 0.55;
pitchFmin    = 80;
pitchFmax    = 1000;
clarityFloor = 0.15;
vocalLikelihoodFloor = 0.10;
vlSmoothFrames = 5;
gatingStrength = 0.35;
holdFrames    = 8;
holdLikelihoodValue = 0.5;
maxHarmonics      = 5;
harmonicTolFrac   = 0.6;
harmonicBoostMax  = 0.4;
sigmaIPDRefFreq  = 300;
sigmaIPDMinScale = 0.5;
fluxPercentileProtect  = 85;
transientProtectAmount = 0.6;
gainFloorBase    = 0.0;
gainFloorMono    = 0.15;
postMedianFrames = 3;
perBandRiskThresh   = 0.70;
perBandRiskProtectMin  = 0.5;   
perBandRiskMinFrac  = 0.3;

%% --- VERIFIKASI STEREO INPUT ---
if size(x,2) ~= 2
    error('File input harus berformat stereo (2 channel).');
end
L = x(:,1);
R = x(:,2);

%% --- PRE #1: DC OFFSET REMOVAL ---
R_dc = exp(-2*pi*fcDC/fs);
L = filter([1 -1], [1 -R_dc], L);
R = filter([1 -1], [1 -R_dc], R);

%% --- PRE #2: KORELASI L-R GLOBAL + AUTO-ADAPT ---
corrLR = corr(L, R);
depthScale = 1.0;
if corrLR > corrLRWarnThresh
    frac = (corrLR - corrLRWarnThresh) / max(eps, (corrLRHardThresh - corrLRWarnThresh));
    frac = min(1, max(0, frac));
    depthScale = 1.0 - frac * (1.0 - minDepthScale);
end
depth = depth * depthScale;
if corrLR > corrLRWarnThresh
    fracFloor = (corrLR - corrLRWarnThresh) / max(eps, (corrLRHardThresh - corrLRWarnThresh));
    fracFloor = min(1, max(0, fracFloor));
    gainFloor = gainFloorBase + fracFloor * (gainFloorMono - gainFloorBase);
else
    gainFloor = gainFloorBase;
end

win = 0.5 - 0.5*cos(2*pi*(0:N-1)'/N);
XL = my_stft(L, N, hop, win);
XR = my_stft(R, N, hop, win);
[~, numFrames] = size(XL);

%% --- PRE #3: PITCH/HARMONICITY GATE + CONTINUITY HYSTERESIS ---
mono = (L + R) / 2;
vocalLikelihoodRaw = zeros(1, numFrames);
f0Estimate         = zeros(1, numFrames);
lagMin = round(fs / pitchFmax);
lagMax = round(fs / pitchFmin);

for i = 1:numFrames
    idx = (i-1)*hop + (1:N);
    if idx(end) > length(mono)
        break;
    end
    frame = mono(idx) .* win;
    frame = frame - mean(frame);
    ac = xcorr(frame, lagMax, 'coeff');
    center = lagMax + 1;
    segment = ac(center+lagMin : center+lagMax);
    if isempty(segment) || all(segment == 0)
        clarity = 0; bestLag = 0;
    else
        [clarity, relLag] = max(segment);
        bestLag = lagMin + relLag - 1;
    end
    vocalLikelihoodRaw(i) = max(0, clarity);
    if bestLag > 0
        f0Estimate(i) = fs / bestLag;
    else
        f0Estimate(i) = 0;
    end
end

vocalLikelihoodRaw(vocalLikelihoodRaw < clarityFloor) = 0;
vocalLikelihoodHeld = vocalLikelihoodRaw;
holdCounter = 0;
for i = 1:numFrames
    if vocalLikelihoodRaw(i) > clarityFloor
        holdCounter = holdFrames;
    elseif holdCounter > 0
        holdCounter = holdCounter - 1;
        vocalLikelihoodHeld(i) = max(vocalLikelihoodHeld(i), holdLikelihoodValue);
    end
end
vocalLikelihoodRaw = vocalLikelihoodHeld;

if vlSmoothFrames > 1
    kernelVL = ones(1, vlSmoothFrames) / vlSmoothFrames;
    vocalLikelihood = conv(vocalLikelihoodRaw, kernelVL, 'same');
else
    vocalLikelihood = vocalLikelihoodRaw;
end
vocalLikelihood = min(1, vocalLikelihood);
vocalLikelihood = max(vocalLikelihoodFloor, vocalLikelihood);

%% --- ADAPTIVE SUB-BAND ALLOCATION ---
fmax = fs/2;
edgesBass    = logspace(log10(fminBand),    log10(formantLowHz),  nBandsBass+1);
edgesFormant = logspace(log10(formantLowHz),log10(formantHighHz), nBandsFormant+1);
edgesTreble  = logspace(log10(formantHighHz),log10(fmax),         nBandsTreble+1);
bandEdges = [edgesBass, edgesFormant(2:end), edgesTreble(2:end)];
bandEdges = unique(bandEdges, 'stable');
numBands  = length(bandEdges) - 1;

freqAxis   = (0:N-1)' * (fs/N);
freqFolded = min(freqAxis, fs - freqAxis);
bandIdx = discretize(freqFolded, bandEdges);
bandIdx(freqFolded < fminBand) = 1;
bandIdx(isnan(bandIdx)) = numBands;

bandBins = cell(numBands,1);
for b = 1:numBands
    bandBins{b} = find(bandIdx == b);
end

isProtectedBand = false(numBands,1);
for b = 1:numBands
    if bandEdges(b+1) <= protectedBandHz
        isProtectedBand(b) = true;
    end
end

protectGain = ones(numBands,1);
firstUnprotected = find(~isProtectedBand, 1, 'first');
for r = 1:protectedRampBands
    idxB = firstUnprotected + r - 1;
    if idxB <= numBands
        protectGain(idxB) = r / (protectedRampBands+1);
    end
end

%% --- DEPTH PROFILE DENGAN TRANSISI GRADUAL ---
bandCenterFreq = sqrt(bandEdges(1:end-1) .* bandEdges(2:end));
boostRamp = zeros(numBands,1);
for b = 1:numBands
    f = bandCenterFreq(b);
    if f < vocalBoostLowHz - rampWidthHz || f > vocalBoostHighHz + rampWidthHz
        boostRamp(b) = 0;
    elseif f >= vocalBoostLowHz && f <= vocalBoostHighHz
        boostRamp(b) = 1;
    elseif f < vocalBoostLowHz
        boostRamp(b) = (f - (vocalBoostLowHz - rampWidthHz)) / rampWidthHz;
    else
        boostRamp(b) = 1 - (f - vocalBoostHighHz) / rampWidthHz;
    end
end
boostRamp = max(0, min(1, boostRamp));
depthProfile = depth * (1 + boostRamp * (vocalBoostFactor - 1));
depthProfile = min(1, depthProfile);
boostMask = boostRamp > 0.5;

%% --- ADAPTIVE sigmaIPD PER BAND ---
sigmaIPDperBand = sigmaIPD * min(1, sigmaIPDRefFreq ./ max(sigmaIPDRefFreq, bandCenterFreq'));
sigmaIPDperBand = max(sigmaIPD * sigmaIPDMinScale, sigmaIPDperBand);
sigmaIPDperBand = sigmaIPDperBand(:);

%% --- CORE: ENERGY-WEIGHTED PLV ---
unitPhasor = exp(1j * (angle(XL) - angle(XR)));
magWeight  = (abs(XL) + abs(XR)) / 2;
bandMeanPhasor = zeros(numBands, numFrames);

for b = 1:numBands
    idxBins = bandBins{b};
    if isempty(idxBins) || isProtectedBand(b)
        continue;
    end
    w  = magWeight(idxBins,:);
    wp = unitPhasor(idxBins,:) .* w;
    bandMeanPhasor(b,:) = sum(wp, 1) ./ (sum(w, 1) + eps);
end

if timeSmoothFrames > 1
    kernel = ones(1, timeSmoothFrames) / timeSmoothFrames;
    bandMeanPhasorSmooth = conv2(bandMeanPhasor, kernel, 'same');
else
    bandMeanPhasorSmooth = bandMeanPhasor;
end

PLVband = abs(bandMeanPhasorSmooth);
IPDband = angle(bandMeanPhasorSmooth);

%% [v8] DETEKSI RISIKO KORELASI PER-BAND -- GRADED, bukan binary switch
fracFramesHighPLV = mean(PLVband > perBandRiskThresh, 2);
riskExcess = max(0, fracFramesHighPLV - perBandRiskMinFrac) ./ max(eps, 1 - perBandRiskMinFrac);
riskExcess = min(1, riskExcess);
isCandidateBand = (~boostMask) & (~isProtectedBand);
riskProtectFactor = ones(numBands, 1);
riskProtectFactor(isCandidateBand) = 1 - riskExcess(isCandidateBand) * (1 - perBandRiskProtectMin);

% Terapkan proteksi tambahan ke depthProfile pada band berisiko
depthProfile = depthProfile .* riskProtectFactor;

PLVbandWarped = PLVband .^ plvGamma;
centerScoreBand = PLVbandWarped .* exp(-(IPDband.^2) ./ (2*sigmaIPDperBand.^2));
centerScoreBand(PLVband < plvFloor) = 0;

%% --- CROSS-BAND HARMONIC CONSISTENCY ---
harmonicSupport = zeros(1, numFrames);
for i = 1:numFrames
    f0 = f0Estimate(i);
    if f0 <= 0
        continue;
    end
    supportVals = nan(1, maxHarmonics);
    cnt = 0;
    for k = 1:maxHarmonics
        fk = f0 * k;
        if fk > fmax
            break;
        end
        bIdx = find(bandEdges(1:end-1) <= fk & bandEdges(2:end) > fk, 1);
        if isempty(bIdx) || isProtectedBand(bIdx)
            continue;
        end
        bandWidth = bandEdges(bIdx+1) - bandEdges(bIdx);
        distFromEdge = min(fk - bandEdges(bIdx), bandEdges(bIdx+1) - fk);
        if distFromEdge >= harmonicTolFrac * bandWidth * 0.5
            cnt = cnt + 1;
            supportVals(cnt) = centerScoreBand(bIdx, i);
        end
    end
    if cnt > 0
        harmonicSupport(i) = mean(supportVals(1:cnt));
    end
end
vocalLikelihood = min(1, vocalLikelihood + harmonicBoostMax * harmonicSupport);

%% --- PRE-GATE APPLICATION ---
vlBlend = (1 - gatingStrength) + gatingStrength * vocalLikelihood;
centerScoreBand = centerScoreBand .* repmat(vlBlend, numBands, 1);
gainBandRaw = 1 - depthProfile .* centerScoreBand;

%% --- POST #1: TRANSIENT PROTECTION ---
magSum = sum(abs(XL) + abs(XR), 1);
flux = [0, max(0, diff(magSum))];
fluxThresh = prctile(flux, fluxPercentileProtect);
isTransient = flux > fluxThresh;
gainBandRaw = gainBandRaw + (1 - gainBandRaw) .* repmat(transientProtectAmount * isTransient, numBands, 1);

%% --- CORE: ATTACK/RELEASE ---
frameRate   = fs / hop;
attackCoef  = exp(-1 / (attackMs/1000 * frameRate));
releaseCoef = exp(-1 / (releaseMs/1000 * frameRate));
gainBand = zeros(numBands, numFrames);
gainBand(:,1) = gainBandRaw(:,1);

for t = 2:numFrames
    for b = 1:numBands
        if gainBandRaw(b,t) < gainBand(b,t-1)
            coef = attackCoef;
        else
            coef = releaseCoef;
        end
        gainBand(b,t) = coef*gainBand(b,t-1) + (1-coef)*gainBandRaw(b,t);
    end
end
gainBand = max(gainFloor, gainBand);

if postMedianFrames > 1
    gainBandPost = zeros(size(gainBand));
    for b = 1:numBands
        gainBandPost(b,:) = medfilt1(gainBand(b,:), postMedianFrames);
    end
    gainBand = gainBandPost;
end

%% --- PETAKAN GAIN & TERAPKAN ---
gainMap = ones(N, numFrames);
for b = 1:numBands
    idxBins = bandBins{b};
    if isempty(idxBins) || isProtectedBand(b)
        continue;
    end
    effectiveGain = protectGain(b) * gainBand(b,:) + (1 - protectGain(b)) * 1;
    gainMap(idxBins, :) = repmat(effectiveGain, length(idxBins), 1);
end

YL = XL .* gainMap;
YR = XR .* gainMap;

yL = my_istft(YL, hop, win); yL = matchLength(yL, length(L));
yR = my_istft(YR, hop, win); yR = matchLength(yR, length(R));

% Output akhir stereo instrumen
y_out = [yL, yR];
y_out = y_out ./ (max(abs(y_out(:))) + eps) * 0.95;

end % function metode3_v8_sar_tuning

%% =========================================================================
%%  LOCAL FUNCTIONS (STFT / ISTFT / MATCHLENGTH)
%% =========================================================================
function X = my_stft(x, N, hop, win)
    x = x(:);
    numFrames = floor((length(x) - N) / hop) + 1;
    X = zeros(N, numFrames);
    for i = 1:numFrames
        idx = (i-1)*hop + (1:N);
        frame = x(idx) .* win;
        X(:,i) = fft(frame, N);
    end
end

function x = my_istft(X, hop, win)
    [N, numFrames] = size(X);
    outLen = (numFrames-1)*hop + N;
    x = zeros(outLen, 1);
    winSum = zeros(outLen, 1);
    for i = 1:numFrames
        idx = (i-1)*hop + (1:N);
        frame = real(ifft(X(:,i)));
        frame = frame .* win;
        x(idx) = x(idx) + frame;
        winSum(idx) = winSum(idx) + win.^2;
    end
    winSum(winSum < 1e-8) = 1;
    x = x ./ winSum;
end

function y = matchLength(y, targetLen)
    y = y(:);
    if length(y) < targetLen
        y(end+1:targetLen, 1) = 0;
    else
        y = y(1:targetLen);
    end
end
