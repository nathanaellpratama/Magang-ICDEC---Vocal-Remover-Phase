function state = metode3_v9m_streaming_init(fs, N)

%% PARAMETER 
state.params.N   = N;
state.params.hop = N/4;
state.params.fminBand        = 50;
state.params.formantLowHz    = 150;
state.params.formantHighHz   = 4500;
state.params.nBandsBass      = 6;
state.params.nBandsFormant   = 20;
state.params.nBandsTreble    = 8;
state.params.protectedBandHz     = 150;
state.params.protectedRampBands  = 5;
state.params.sigmaIPD   = 0.8;
state.params.plvFloor   = 0.15;
state.params.plvGamma   = 0.22;
state.params.timeSmoothFrames = 11;   
state.params.depth            = 0.95;
state.params.vocalBoostLowHz  = 200;
state.params.vocalBoostHighHz = 16000;  
state.params.vocalBoostFactor = 1.6;
state.params.rampWidthHz      = 150;
state.params.attackMs  = 20;
state.params.releaseMs = 200;
state.params.fcDC = 15;
state.params.corrLRWarnThresh   = 0.88;
state.params.corrLRHardThresh   = 0.96;
state.params.minDepthScale      = 0.55;
state.params.pitchFmin    = 80;
state.params.pitchFmax    = 1000;
state.params.clarityFloor = 0.15;
state.params.vocalLikelihoodFloor = 0.10;
state.params.vlSmoothFrames = 5;      % causal window
state.params.gatingStrength = 0.35;
state.params.holdFrames    = 8;
state.params.holdLikelihoodValue = 0.5;
state.params.maxHarmonics      = 5;
state.params.harmonicTolFrac   = 0.6;
state.params.harmonicBoostMax  = 0.4;
state.params.sigmaIPDRefFreq  = 300;
state.params.sigmaIPDMinScale = 0.5;
state.params.transientProtectAmount = 0.6;
state.params.transientKStd = 1.0;     
state.params.corrLR_tauSec  = 1.5;    
state.params.flux_tauSec    = 2.0;    
state.params.gainFloorBase    = 0.0;
state.params.gainFloorMono    = 0.15;
state.params.postMedianFrames = 3;    
state.params.perBandRiskThresh   = 0.70;
state.params.perBandRiskProtectMin  = 0.5;
state.params.perBandRiskMinFrac  = 0.3;
state.params.riskEstTauSec = 3.0;     

fs_ = fs;
N_  = N;
hop_ = state.params.hop;
frameRate = fs_ / hop_;

%% --- SUB-BAND ALLOCATION ---
fmax = fs_/2;
edgesBass    = logspace(log10(state.params.fminBand),    log10(state.params.formantLowHz),  state.params.nBandsBass+1);
edgesFormant = logspace(log10(state.params.formantLowHz),log10(state.params.formantHighHz), state.params.nBandsFormant+1);
edgesTreble  = logspace(log10(state.params.formantHighHz),log10(fmax),         state.params.nBandsTreble+1);
bandEdges = [edgesBass, edgesFormant(2:end), edgesTreble(2:end)];
bandEdges = unique(bandEdges, 'stable');
numBands  = length(bandEdges) - 1;

freqAxis   = (0:N_-1)' * (fs_/N_);
freqFolded = min(freqAxis, fs_ - freqAxis);
bandIdx = discretize(freqFolded, bandEdges);
bandIdx(freqFolded < state.params.fminBand) = 1;
bandIdx(isnan(bandIdx)) = numBands;

bandBins = cell(numBands,1);
for b = 1:numBands
    bandBins{b} = find(bandIdx == b);
end

isProtectedBand = false(numBands,1);
for b = 1:numBands
    if bandEdges(b+1) <= state.params.protectedBandHz
        isProtectedBand(b) = true;
    end
end

protectGain = ones(numBands,1);
firstUnprotected = find(~isProtectedBand, 1, 'first');
for r = 1:state.params.protectedRampBands
    idxB = firstUnprotected + r - 1;
    if idxB <= numBands
        protectGain(idxB) = r / (state.params.protectedRampBands+1);
    end
end

bandCenterFreq = sqrt(bandEdges(1:end-1) .* bandEdges(2:end));
boostRamp = zeros(numBands,1);
for b = 1:numBands
    f = bandCenterFreq(b);
    if f < state.params.vocalBoostLowHz - state.params.rampWidthHz || f > state.params.vocalBoostHighHz + state.params.rampWidthHz
        boostRamp(b) = 0;
    elseif f >= state.params.vocalBoostLowHz && f <= state.params.vocalBoostHighHz
        boostRamp(b) = 1;
    elseif f < state.params.vocalBoostLowHz
        boostRamp(b) = (f - (state.params.vocalBoostLowHz - state.params.rampWidthHz)) / state.params.rampWidthHz;
    else
        boostRamp(b) = 1 - (f - state.params.vocalBoostHighHz) / state.params.rampWidthHz;
    end
end
boostRamp = max(0, min(1, boostRamp));
boostMask = boostRamp > 0.5;

sigmaIPDperBand = state.params.sigmaIPD * min(1, state.params.sigmaIPDRefFreq ./ max(state.params.sigmaIPDRefFreq, bandCenterFreq'));
sigmaIPDperBand = max(state.params.sigmaIPD * state.params.sigmaIPDMinScale, sigmaIPDperBand);
sigmaIPDperBand = sigmaIPDperBand(:);

state.cfg.fs = fs_;
state.cfg.numBands = numBands;
state.cfg.bandEdges = bandEdges;
state.cfg.bandBins = bandBins;
state.cfg.isProtectedBand = isProtectedBand;
state.cfg.protectGain = protectGain;
state.cfg.boostRamp = boostRamp;
state.cfg.boostMask = boostMask;
state.cfg.sigmaIPDperBand = sigmaIPDperBand;
state.cfg.win = 0.5 - 0.5*cos(2*pi*(0:N_-1)'/N_);
state.cfg.frameRate = frameRate;
state.cfg.attackCoef  = exp(-1 / (state.params.attackMs/1000 * frameRate));
state.cfg.releaseCoef = exp(-1 / (state.params.releaseMs/1000 * frameRate));
state.cfg.corrLR_alpha = 1 - exp(-1/(state.params.corrLR_tauSec * frameRate));
state.cfg.flux_alpha   = 1 - exp(-1/(state.params.flux_tauSec   * frameRate));
state.cfg.risk_alpha   = 1 - exp(-1/(state.params.riskEstTauSec * frameRate));

%% --- RUNNING/DYNAMIC STATE ---
state.dyn.dcL_prev_in = 0; state.dyn.dcL_prev_out = 0; 
state.dyn.dcR_prev_in = 0; state.dyn.dcR_prev_out = 0;
state.dyn.R_dc = exp(-2*pi*state.params.fcDC/fs_);
state.dyn.ziL = 0; % filter state utk DC removal vectorized (filter 1 pole, 1 zero -> 1 elemen)
state.dyn.ziR = 0;

state.dyn.corrLR_ELR = 0;   % EMA of L*R
state.dyn.corrLR_EL2 = eps; % EMA of L^2
state.dyn.corrLR_ER2 = eps; % EMA of R^2

state.dyn.fluxMean = 0;
state.dyn.fluxVar  = 0;

state.dyn.bandPhasorBuf = zeros(numBands, state.params.timeSmoothFrames); % causal ring buffer
state.dyn.bandPhasorBufCount = 0;

state.dyn.vlBuf = zeros(1, state.params.vlSmoothFrames); % causal ring buffer
state.dyn.vlBufCount = 0;

state.dyn.gainBandPrev = ones(numBands,1); % utk attack/release

state.dyn.gainMedianBuf = ones(numBands, state.params.postMedianFrames); % causal median buffer

state.dyn.fracHighPLV_run = zeros(numBands,1); % EMA fracFramesHighPLV

state.dyn.holdCounter = 0;

state.dyn.inBufL = zeros(N_,1);
state.dyn.inBufR = zeros(N_,1);
state.dyn.outBufL = zeros(N_,1);
state.dyn.outBufR = zeros(N_,1);
state.dyn.winSumBuf = zeros(N_,1);
state.dyn.magSumPrev = 0;

lagMin = round(fs_ / state.params.pitchFmax);
lagMax = round(fs_ / state.params.pitchFmin);
state.cfg.lagMin = lagMin;
state.cfg.lagMax = lagMax;
pitchWinLen = N_; 
state.dyn.monoHistBuf = zeros(pitchWinLen, 1);

end
