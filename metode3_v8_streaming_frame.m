function [yL_frame, yR_frame, state, timing] = metode3_v8_streaming_frame(L_hop, R_hop, state)

doTiming = nargout >= 4;
if doTiming
    tStart = tic;
    timing = struct();
end

p = state.params;
cfg = state.cfg;
N = p.N; hop = p.hop;

%% --- BUFFER INPUT: geser buffer STFT-frame ---
state.dyn.inBufL = [state.dyn.inBufL(hop+1:end); L_hop(:)];
state.dyn.inBufR = [state.dyn.inBufR(hop+1:end); R_hop(:)];

%% --- PRE #1: DC OFFSET REMOVAL ---
a = state.dyn.R_dc;
[Lc, state.dyn.ziL] = filter([1 -1], [1 -a], L_hop(:), state.dyn.ziL);
[Rc, state.dyn.ziR] = filter([1 -1], [1 -a], R_hop(:), state.dyn.ziR);

%% --- PRE #2: KORELASI L-R RUNNING ---
alpha = cfg.corrLR_alpha;
state.dyn.corrLR_ELR = (1-alpha)*state.dyn.corrLR_ELR + alpha*mean(Lc.*Rc);
state.dyn.corrLR_EL2 = (1-alpha)*state.dyn.corrLR_EL2 + alpha*mean(Lc.^2);
state.dyn.corrLR_ER2 = (1-alpha)*state.dyn.corrLR_ER2 + alpha*mean(Rc.^2);
corrLR = state.dyn.corrLR_ELR / max(eps, sqrt(state.dyn.corrLR_EL2 * state.dyn.corrLR_ER2));
corrLR = max(-1, min(1, corrLR));

if doTiming, timing.dc_corr = toc(tStart); tSection = tic; end

depthScale = 1.0;
if corrLR > p.corrLRWarnThresh
    frac = (corrLR - p.corrLRWarnThresh) / max(eps, (p.corrLRHardThresh - p.corrLRWarnThresh));
    frac = min(1, max(0, frac));
    depthScale = 1.0 - frac * (1.0 - p.minDepthScale);
end
depthNow = p.depth * depthScale;
if corrLR > p.corrLRWarnThresh
    fracFloor = (corrLR - p.corrLRWarnThresh) / max(eps, (p.corrLRHardThresh - p.corrLRWarnThresh));
    fracFloor = min(1, max(0, fracFloor));
    gainFloor = p.gainFloorBase + fracFloor * (p.gainFloorMono - p.gainFloorBase);
else
    gainFloor = p.gainFloorBase;
end

%% --- STFT FRAME TUNGGAL ---
frameL = state.dyn.inBufL .* cfg.win;
frameR = state.dyn.inBufR .* cfg.win;
XL = fft(frameL, N);
XR = fft(frameR, N);

if doTiming, timing.stft = toc(tSection); tSection = tic; end

%% --- PRE #3: PITCH/HARMONICITY ---
mono = (state.dyn.inBufL + state.dyn.inBufR)/2;
frame = mono .* cfg.win;
frame = frame - mean(frame);
lagMax = cfg.lagMax; lagMin = cfg.lagMin;

frameLen = length(frame);
energy0 = sum(frame.^2) + eps; 
numLags = lagMax - lagMin + 1;
segment = zeros(numLags, 1);
for li = 1:numLags
    lag = lagMin + li - 1;
    if lag < frameLen
        a = frame(1:frameLen-lag);
        b = frame(1+lag:frameLen);
        segment(li) = sum(a .* b) / energy0;
    else
        segment(li) = 0;
    end
end

if isempty(segment) || all(segment==0)
    clarity = 0; bestLag = 0;
else
    [clarity, relLag] = max(segment);
    bestLag = lagMin + relLag - 1;
end
vlRaw = max(0, clarity);
if bestLag > 0
    f0 = cfg.fs / bestLag;
else
    f0 = 0;
end
if vlRaw < p.clarityFloor
    vlRaw = 0;
end

% Hold logic
if vlRaw > p.clarityFloor
    state.dyn.holdCounter = p.holdFrames;
elseif state.dyn.holdCounter > 0
    state.dyn.holdCounter = state.dyn.holdCounter - 1;
    vlRaw = max(vlRaw, p.holdLikelihoodValue);
end

% Causal moving-average smoothing utk vocalLikelihood
state.dyn.vlBuf = [state.dyn.vlBuf(2:end), vlRaw];
state.dyn.vlBufCount = min(p.vlSmoothFrames, state.dyn.vlBufCount + 1);
vocalLikelihood = sum(state.dyn.vlBuf(end-state.dyn.vlBufCount+1:end)) / state.dyn.vlBufCount;
vocalLikelihood = min(1, vocalLikelihood);
vocalLikelihood = max(p.vocalLikelihoodFloor, vocalLikelihood);

if doTiming, timing.pitch_autocorr = toc(tSection); tSection = tic; end

%% --- CORE: ENERGY-WEIGHTED PLV PER BAND (1 frame) ---
numBands = cfg.numBands;
unitPhasor = exp(1j*(angle(XL) - angle(XR)));
magWeight  = (abs(XL) + abs(XR))/2;
bandMeanPhasorRaw = zeros(numBands,1);
for b = 1:numBands
    idxBins = cfg.bandBins{b};
    if isempty(idxBins) || cfg.isProtectedBand(b)
        continue;
    end
    w  = magWeight(idxBins);
    wp = unitPhasor(idxBins) .* w;
    bandMeanPhasorRaw(b) = sum(wp) / (sum(w) + eps);
end

% Causal moving-average smoothing PLV 
state.dyn.bandPhasorBuf = [state.dyn.bandPhasorBuf(:,2:end), bandMeanPhasorRaw];
state.dyn.bandPhasorBufCount = min(p.timeSmoothFrames, state.dyn.bandPhasorBufCount + 1);
bandMeanPhasorSmooth = sum(state.dyn.bandPhasorBuf(:, end-state.dyn.bandPhasorBufCount+1:end), 2) / state.dyn.bandPhasorBufCount;

PLVband = abs(bandMeanPhasorSmooth);
IPDband = angle(bandMeanPhasorSmooth);

if doTiming, timing.plv_ipd = toc(tSection); tSection = tic; end

%% --- DETEKSI RISIKO PER-BAND ---
isHighPLVnow = double(PLVband > p.perBandRiskThresh);
ralpha = cfg.risk_alpha;
state.dyn.fracHighPLV_run = (1-ralpha)*state.dyn.fracHighPLV_run + ralpha*isHighPLVnow;
fracFramesHighPLV = state.dyn.fracHighPLV_run;

riskExcess = max(0, fracFramesHighPLV - p.perBandRiskMinFrac) ./ max(eps, 1 - p.perBandRiskMinFrac);
riskExcess = min(1, riskExcess);
isCandidateBand = (~cfg.boostMask) & (~cfg.isProtectedBand);
riskProtectFactor = ones(numBands,1);
riskProtectFactor(isCandidateBand) = 1 - riskExcess(isCandidateBand) * (1 - p.perBandRiskProtectMin);

depthProfile = depthNow * (1 + cfg.boostRamp * (p.vocalBoostFactor - 1));
depthProfile = min(1, depthProfile);
depthProfile = depthProfile .* riskProtectFactor;

PLVbandWarped = PLVband .^ p.plvGamma;
centerScoreBand = PLVbandWarped .* exp(-(IPDband.^2) ./ (2*cfg.sigmaIPDperBand.^2));
centerScoreBand(PLVband < p.plvFloor) = 0;

%% --- HARMONIC SUPPORT ---
harmonicSupport = 0;
if f0 > 0
    supportVals = nan(1, p.maxHarmonics);
    cnt = 0;
    fmax = cfg.fs/2;
    for k = 1:p.maxHarmonics
        fk = f0*k;
        if fk > fmax, break; end
        bIdx = find(cfg.bandEdges(1:end-1) <= fk & cfg.bandEdges(2:end) > fk, 1);
        if isempty(bIdx) || cfg.isProtectedBand(bIdx)
            continue;
        end
        bandWidth = cfg.bandEdges(bIdx+1) - cfg.bandEdges(bIdx);
        distFromEdge = min(fk - cfg.bandEdges(bIdx), cfg.bandEdges(bIdx+1) - fk);
        if distFromEdge >= p.harmonicTolFrac * bandWidth * 0.5
            cnt = cnt + 1;
            supportVals(cnt) = centerScoreBand(bIdx);
        end
    end
    if cnt > 0
        harmonicSupport = mean(supportVals(1:cnt));
    end
end
vocalLikelihood = min(1, vocalLikelihood + p.harmonicBoostMax * harmonicSupport);

%% --- GATE + GAIN MENTAH ---
vlBlend = (1 - p.gatingStrength) + p.gatingStrength * vocalLikelihood;
centerScoreBand = centerScoreBand * vlBlend;
gainBandRaw = 1 - depthProfile .* centerScoreBand;

if doTiming, timing.risk_harmonic_gate = toc(tSection); tSection = tic; end

%% --- TRANSIENT PROTECTION ---
magSumNow = sum(abs(XL) + abs(XR));
flux = max(0, magSumNow - state.dyn.magSumPrev);
state.dyn.magSumPrev = magSumNow;

falpha = cfg.flux_alpha;
prevMean = state.dyn.fluxMean;
state.dyn.fluxMean = (1-falpha)*prevMean + falpha*flux;
state.dyn.fluxVar  = (1-falpha)*state.dyn.fluxVar + falpha*(flux-prevMean)^2;
fluxStd = sqrt(max(0,state.dyn.fluxVar));
fluxThresh = state.dyn.fluxMean + p.transientKStd * fluxStd;
isTransient = flux > fluxThresh;

gainBandRaw = gainBandRaw + (1-gainBandRaw) * (p.transientProtectAmount * isTransient);

%% --- ATTACK/RELEASE ---
gainBandNow = zeros(numBands,1);
for b = 1:numBands
    if gainBandRaw(b) < state.dyn.gainBandPrev(b)
        coef = cfg.attackCoef;
    else
        coef = cfg.releaseCoef;
    end
    gainBandNow(b) = coef*state.dyn.gainBandPrev(b) + (1-coef)*gainBandRaw(b);
end
gainBandNow = max(gainFloor, gainBandNow);
state.dyn.gainBandPrev = gainBandNow;

% Causal median filter
state.dyn.gainMedianBuf = [state.dyn.gainMedianBuf(:,2:end), gainBandNow];
gainBandPost = median(state.dyn.gainMedianBuf, 2);

if doTiming, timing.transient_ar_median = toc(tSection); tSection = tic; end

%% --- PETAKAN GAIN & TERAPKAN ---
gainMap = ones(N,1);
for b = 1:numBands
    idxBins = cfg.bandBins{b};
    if isempty(idxBins) || cfg.isProtectedBand(b)
        continue;
    end
    effectiveGain = cfg.protectGain(b)*gainBandPost(b) + (1-cfg.protectGain(b))*1;
    gainMap(idxBins) = effectiveGain;
end

YL = XL .* gainMap;
YR = XR .* gainMap;

frameOutL = real(ifft(YL)) .* cfg.win;
frameOutR = real(ifft(YR)) .* cfg.win;

%% --- OVERLAP-ADD OUTPUT (causal, buffer window sum utk normalisasi) ---
state.dyn.outBufL = state.dyn.outBufL + frameOutL;
state.dyn.outBufR = state.dyn.outBufR + frameOutR;
state.dyn.winSumBuf = state.dyn.winSumBuf + cfg.win.^2;

% Ambil hop-length pertama sebagai output final 
wsOut = state.dyn.winSumBuf(1:hop);
wsOut(wsOut < 1e-8) = 1;
yL_frame = state.dyn.outBufL(1:hop) ./ wsOut;
yR_frame = state.dyn.outBufR(1:hop) ./ wsOut;

% Geser buffer output & winSum utk frame berikutnya
state.dyn.outBufL = [state.dyn.outBufL(hop+1:end); zeros(hop,1)];
state.dyn.outBufR = [state.dyn.outBufR(hop+1:end); zeros(hop,1)];
state.dyn.winSumBuf = [state.dyn.winSumBuf(hop+1:end); zeros(hop,1)];

if doTiming
    timing.gainmap_istft_ola = toc(tSection);
    timing.total = toc(tStart);
end

end