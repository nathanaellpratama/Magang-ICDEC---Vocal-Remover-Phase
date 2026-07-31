function cfgData = precompute_cfg(fs, N)

p = struct();
p.N = N; p.hop = N/4;
p.fminBand = 50; p.formantLowHz = 150; p.formantHighHz = 4500;
p.nBandsBass = 6; p.nBandsFormant = 20; p.nBandsTreble = 8;
p.protectedBandHz = 150; p.protectedRampBands = 5;
p.sigmaIPD = 0.8; p.plvFloor = 0.15; p.plvGamma = 0.22;
p.timeSmoothFrames = 11; p.depth = 0.95;
p.vocalBoostLowHz = 200; p.vocalBoostHighHz = 4000; p.vocalBoostFactor = 1.6;
p.rampWidthHz = 150; p.attackMs = 20; p.releaseMs = 200; p.fcDC = 15;
p.corrLRWarnThresh = 0.88; p.corrLRHardThresh = 0.96; p.minDepthScale = 0.55;
p.pitchFmin = 80; p.pitchFmax = 1000; p.clarityFloor = 0.15;
p.vocalLikelihoodFloor = 0.10; p.vlSmoothFrames = 5;
p.gatingStrength = 0.35; p.holdFrames = 8; p.holdLikelihoodValue = 0.5;
p.maxHarmonics = 5; p.harmonicTolFrac = 0.6; p.harmonicBoostMax = 0.4;
p.sigmaIPDRefFreq = 300; p.sigmaIPDMinScale = 0.5;
p.transientProtectAmount = 0.6; p.transientKStd = 1.0;
p.corrLR_tauSec = 1.5; p.flux_tauSec = 2.0;
p.gainFloorBase = 0.0; p.gainFloorMono = 0.15;
p.postMedianFrames = 3;
p.perBandRiskThresh = 0.70; p.perBandRiskProtectMin = 0.5; p.perBandRiskMinFrac = 0.3;
p.riskEstTauSec = 3.0;

hop = p.hop;
frameRate = fs / hop;

%% --- Sub-band allocation (fungsi non-codegen HANYA di sini) ---
fmax = fs/2;
edgesBass    = logspace(log10(p.fminBand),     log10(p.formantLowHz),  p.nBandsBass+1);
edgesFormant = logspace(log10(p.formantLowHz), log10(p.formantHighHz), p.nBandsFormant+1);
edgesTreble  = logspace(log10(p.formantHighHz),log10(fmax),            p.nBandsTreble+1);
bandEdges = [edgesBass, edgesFormant(2:end), edgesTreble(2:end)];
bandEdges = unique(bandEdges, 'stable');           % <- non-codegen, aman di sini
numBands  = length(bandEdges) - 1;

freqAxis   = (0:N-1)' * (fs/N);
freqFolded = min(freqAxis, fs - freqAxis);
bandIdx = discretize(freqFolded, bandEdges);        % <- non-codegen, aman di sini
bandIdx(freqFolded < p.fminBand) = 1;
bandIdx(isnan(bandIdx)) = numBands;

% Ganti cell array bandBins{b} -> matriks mask N x numBands.
bandMask = false(N, numBands);
for b = 1:numBands
    bandMask(:,b) = (bandIdx == b);
end
% simpan juga sebagai double supaya bisa langsung dipakai perkalian matriks
bandMaskD = double(bandMask);

isProtectedBand = false(numBands,1);
for b = 1:numBands
    if bandEdges(b+1) <= p.protectedBandHz
        isProtectedBand(b) = true;
    end
end

protectGain = ones(numBands,1);
firstUnprotected = find(~isProtectedBand, 1, 'first');
for r = 1:p.protectedRampBands
    idxB = firstUnprotected + r - 1;
    if idxB <= numBands
        protectGain(idxB) = r / (p.protectedRampBands+1);
    end
end

bandCenterFreq = sqrt(bandEdges(1:end-1) .* bandEdges(2:end));
boostRamp = zeros(numBands,1);
for b = 1:numBands
    f = bandCenterFreq(b);
    if f < p.vocalBoostLowHz - p.rampWidthHz || f > p.vocalBoostHighHz + p.rampWidthHz
        boostRamp(b) = 0;
    elseif f >= p.vocalBoostLowHz && f <= p.vocalBoostHighHz
        boostRamp(b) = 1;
    elseif f < p.vocalBoostLowHz
        boostRamp(b) = (f - (p.vocalBoostLowHz - p.rampWidthHz)) / p.rampWidthHz;
    else
        boostRamp(b) = 1 - (f - p.vocalBoostHighHz) / p.rampWidthHz;
    end
end
boostRamp = max(0, min(1, boostRamp));
boostMask = boostRamp > 0.5;

sigmaIPDperBand = p.sigmaIPD * min(1, p.sigmaIPDRefFreq ./ max(p.sigmaIPDRefFreq, bandCenterFreq'));
sigmaIPDperBand = max(p.sigmaIPD * p.sigmaIPDMinScale, sigmaIPDperBand);
sigmaIPDperBand = sigmaIPDperBand(:);

win = 0.5 - 0.5*cos(2*pi*(0:N-1)'/N);

lagMin = round(fs / p.pitchFmax);
lagMax = round(fs / p.pitchFmin);

%% --- Susun cfgData: SEMUA numerik, TIDAK ADA cell array ---
cfgData = struct();
cfgData.fs = fs;
cfgData.N  = N;
cfgData.hop = hop;
cfgData.numBands = numBands;
cfgData.bandEdges = bandEdges(:);          % (numBands+1) x 1
cfgData.bandMask  = bandMaskD;             % N x numBands  (double, 0/1)
cfgData.isProtectedBand = double(isProtectedBand); % numBands x 1 (0/1, hindari logical di bus)
cfgData.protectGain = protectGain;
cfgData.boostRamp = boostRamp;
cfgData.boostMask = double(boostMask);
cfgData.sigmaIPDperBand = sigmaIPDperBand;
cfgData.win = win;
cfgData.frameRate = frameRate;
cfgData.attackCoef  = exp(-1 / (p.attackMs/1000 * frameRate));
cfgData.releaseCoef = exp(-1 / (p.releaseMs/1000 * frameRate));
cfgData.corrLR_alpha = 1 - exp(-1/(p.corrLR_tauSec * frameRate));
cfgData.flux_alpha   = 1 - exp(-1/(p.flux_tauSec   * frameRate));
cfgData.risk_alpha   = 1 - exp(-1/(p.riskEstTauSec * frameRate));
cfgData.lagMin = lagMin;
cfgData.lagMax = lagMax;
cfgData.R_dc = exp(-2*pi*p.fcDC/fs);

% Simpan juga parameter skalar yang dipakai langsung di fcn_vocal_remover_rt
fn = fieldnames(p);
for i = 1:numel(fn)
    cfgData.(['p_' fn{i}]) = p.(fn{i});
end

end
