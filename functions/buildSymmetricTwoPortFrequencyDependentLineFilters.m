function filterResult = buildSymmetricTwoPortFrequencyDependentLineFilters( ...
    lineResult, settings)
%BUILDSYMMETRICTWOPORTFREQUENCYDEPENDENTLINEFILTERS
%
% Fit the fixed-delay, frequency-dependent TLM quantities extracted from a
% symmetric reciprocal two-port:
%
%   Zc(s) = Zc_base_R + s*Zc_base_L + Zc_residual(s)
%   H(s) = exp(-s*tau) Hr(s)
%
% The high-frequency series RL asymptote of Zc is extracted before fitting
% so the discrete residual filter does not have to emulate an inductor at
% high frequency. The fixed communication delay is extracted only from the
% propagation term H, not from the characteristic impedance.

Ts = settings.Ts;
tau = lineResult.tau;
Zinf = lineResult.Zinf;

frequency = logspace( ...
    log10(settings.fMin), ...
    log10(settings.fMax), ...
    settings.nFrequency).';

omega = 2*pi*frequency;

response = symmetricLclTwoPortResponse( ...
    frequency, ...
    lineResult.commonSeries, ...
    lineResult.shunt, ...
    tau);

gammaExact = response.gamma;
ZcExact = response.Zc;
HExact = response.H;
HrExact = response.Hr;
ZcNormalisedExact = ZcExact/Zinf;
ZrExact = ZcExact - Zinf;

[ZcBaseR, ZcBaseL] = selectZcHighFrequencySeries( ...
    lineResult, ...
    settings);
ZcBaseExact = ZcBaseR + 1j*omega*ZcBaseL;
fitZcResidual = getLogicalSetting( ...
    settings, ...
    'fitZcResidualAfterHighFrequencySeries', ...
    true);

if fitZcResidual
    ZcFittedQuantityExact = ZcExact - ZcBaseExact;
    zcOutputQuantity = 'Zc_residual_ohm_plus_base_RL';
    zcFitLabel = 'Zc residual';
else
    ZcFittedQuantityExact = ZcExact;
    zcOutputQuantity = 'Zc_ohm';
    zcFitLabel = 'Zc';
end

lowFrequencyWeight = ...
    1 + settings.lowFrequencyWeight ./ ...
    (1 + (frequency/1000).^2);

relativeWeightFloor = getNumericSetting( ...
    settings, ...
    'relativeWeightFloor', ...
    1e-3);
zcFitScale = getNumericSetting(settings, 'zcFitScale', Zinf);

%% Fit Zc or residual Zc

validateStrictlyProperFitOrder( ...
    zcFitLabel, settings.orderZcNum, settings.orderZcDen);

if isfield(settings, 'zcFitMaxFrequency')
    zcFitMaxFrequency = settings.zcFitMaxFrequency;
else
    zcFitMaxFrequency = settings.fMax;
end

zcFitIndex = frequency <= zcFitMaxFrequency;

if nnz(zcFitIndex) < ...
        settings.orderZcNum + settings.orderZcDen + 5
    error('Not enough frequency samples to fit Zc up to %.6g Hz.', ...
        zcFitMaxFrequency);
end

zcOmega = omega(zcFitIndex);
zcWScale = sqrt(min(zcOmega)*max(zcOmega));
zcOmegaScaled = zcOmega/zcWScale;
zcFitWeight = lowFrequencyWeight(zcFitIndex);
ZcFitTarget = ZcFittedQuantityExact(zcFitIndex)/zcFitScale;

if getLogicalSetting(settings, 'relativeWeightZc', false)
    zcFitWeight = zcFitWeight ./ ...
        max(abs(ZcFittedQuantityExact(zcFitIndex)), relativeWeightFloor);
end

[ZcContinuousNormalised, ZcFitInfo] = fitContinuousResponse( ...
    ZcFitTarget, ...
    zcOmegaScaled, ...
    zcWScale, ...
    settings.orderZcNum, ...
    settings.orderZcDen, ...
    zcFitWeight, ...
    settings.iterationsZc);

ZcResidualContinuous = zcFitScale*ZcContinuousNormalised;
ZcFitInfo.responseScale = zcFitScale;
ZcFitInfo.fittedTarget = [zcFitLabel, '/responseScale'];
ZcFitInfo.outputQuantity = zcOutputQuantity;
ZcFitInfo.baseR = ZcBaseR;
ZcFitInfo.baseL = ZcBaseL;
ZcFitInfo.fitMaxFrequency = zcFitMaxFrequency;
ZcFitInfo.nFitSamples = nnz(zcFitIndex);

%% Fit residual propagation Hr

if isfield(settings, 'hrFitMaxFrequency')
    hrFitMaxFrequency = settings.hrFitMaxFrequency;
else
    hrFitMaxFrequency = settings.fMax;
end

hrFitIndex = frequency <= hrFitMaxFrequency;

if nnz(hrFitIndex) < ...
        settings.orderHrNum + settings.orderHrDen + 5
    error('Not enough frequency samples to fit Hr up to %.6g Hz.', ...
        hrFitMaxFrequency);
end

hrOmega = omega(hrFitIndex);
hrOmegaScaled = hrOmega/sqrt(min(hrOmega)*max(hrOmega));
hrWScale = sqrt(min(hrOmega)*max(hrOmega));
hrWeight = lowFrequencyWeight(hrFitIndex);

if getLogicalSetting(settings, 'relativeWeightHr', false)
    hrWeight = hrWeight ./ ...
        max(abs(HrExact(hrFitIndex)), relativeWeightFloor);
end

[HrContinuous, HrFitInfo] = fitContinuousResponse( ...
    HrExact(hrFitIndex), ...
    hrOmegaScaled, ...
    hrWScale, ...
    settings.orderHrNum, ...
    settings.orderHrDen, ...
    hrWeight, ...
    settings.iterationsHr);

HrFitInfo.fitMaxFrequency = hrFitMaxFrequency;
HrFitInfo.nFitSamples = nnz(hrFitIndex);

%% Stabilise continuous fits

ZcResidualContinuous = stabiliseContinuousTransferFunction( ...
    ZcResidualContinuous);
HrContinuous = stabiliseContinuousTransferFunction(HrContinuous);

%% Discretise

ZcResidualDiscrete = c2d( ...
    ZcResidualContinuous, ...
    Ts, ...
    settings.discretisationMethod);

HrDiscrete = c2d( ...
    HrContinuous, ...
    Ts, ...
    settings.discretisationMethod);

[bZcZ, aZcZ] = tfdata(ZcResidualDiscrete, 'v');
[bHrZ, aHrZ] = tfdata(HrDiscrete, 'v');

[bZcZ, aZcZ] = normaliseStrictlyProperDiscreteCoefficients( ...
    bZcZ, aZcZ, 'Zc');

if settings.orderHrNum < settings.orderHrDen
    [bHrZ, aHrZ] = normaliseStrictlyProperDiscreteCoefficients( ...
        bHrZ, aHrZ, 'Hr');
else
    bHrZ = bHrZ(:).'/aHrZ(1);
    aHrZ = aHrZ(:).'/aHrZ(1);
    bHrZ = realIfNumericallyReal(bHrZ);
    aHrZ = realIfNumericallyReal(aHrZ);
end

hrLowPass = designHrLowPass(settings, Ts);
HrLowPassDiscrete = tf(hrLowPass.b, hrLowPass.a, Ts);

%% Evaluate fitted responses

ZcResidualContinuousFit = squeeze(freqresp( ...
    ZcResidualContinuous, ...
    omega));

ZcContinuousFit = addZcBaseIfNeeded( ...
    ZcResidualContinuousFit(:), ...
    ZcBaseExact(:), ...
    fitZcResidual);

HrContinuousFit = squeeze(freqresp( ...
    HrContinuous, ...
    omega));

ZcResidualDiscreteFit = squeeze(freqresp( ...
    ZcResidualDiscrete, ...
    omega));

ZcDiscreteFit = addZcBaseIfNeeded( ...
    ZcResidualDiscreteFit(:), ...
    ZcBaseExact(:), ...
    fitZcResidual);

HrDiscreteFitRaw = squeeze(freqresp( ...
    HrDiscrete, ...
    omega));
HrLowPassFit = squeeze(freqresp( ...
    HrLowPassDiscrete, ...
    omega));
HrDiscreteFit = HrDiscreteFitRaw(:).*HrLowPassFit(:);

%% Plot/evaluation-band responses

plotFrequency = buildPlotFrequency(settings, frequency);
plotOmega = 2*pi*plotFrequency;
plotResponse = symmetricLclTwoPortResponse( ...
    plotFrequency, ...
    lineResult.commonSeries, ...
    lineResult.shunt, ...
    tau);
plotZcBase = ZcBaseR + 1j*plotOmega*ZcBaseL;

plotZcResidualContinuousFit = squeeze(freqresp( ...
    ZcResidualContinuous, ...
    plotOmega));

plotZcContinuousFit = addZcBaseIfNeeded( ...
    plotZcResidualContinuousFit(:), ...
    plotZcBase(:), ...
    fitZcResidual);

plotHrContinuousFit = squeeze(freqresp( ...
    HrContinuous, ...
    plotOmega));

plotZcResidualDiscreteFit = squeeze(freqresp( ...
    ZcResidualDiscrete, ...
    plotOmega));

plotZcDiscreteFit = addZcBaseIfNeeded( ...
    plotZcResidualDiscreteFit(:), ...
    plotZcBase(:), ...
    fitZcResidual);

plotHrDiscreteFitRaw = squeeze(freqresp( ...
    HrDiscrete, ...
    plotOmega));
plotHrLowPassFit = squeeze(freqresp( ...
    HrLowPassDiscrete, ...
    plotOmega));
plotHrDiscreteFit = plotHrDiscreteFitRaw(:).*plotHrLowPassFit(:);

plotHContinuousFit = exp(-1j*plotOmega*tau).*plotHrContinuousFit(:);
plotHDiscreteFit = exp(-1j*plotOmega*tau).*plotHrDiscreteFit(:);

plotContinuousAbcdError = compareOriginalTwoPortFitError( ...
    lineResult, ...
    plotFrequency, ...
    plotZcContinuousFit(:), ...
    plotHContinuousFit(:));

plotDiscreteAbcdError = compareOriginalTwoPortFitError( ...
    lineResult, ...
    plotFrequency, ...
    plotZcDiscreteFit(:), ...
    plotHDiscreteFit(:));

%% Stability checks

continuousPolesZc = pole(ZcResidualContinuous);
continuousPolesHr = pole(HrContinuous);

discretePolesZc = pole(ZcResidualDiscrete);
discretePolesHr = pole(HrDiscrete);
discretePolesHrLowPass = roots(hrLowPass.a);

discretePolesZcFromCoefficients = roots(aZcZ);
discretePolesHrFromCoefficients = roots(aHrZ);

filterStability = struct();
filterStability.continuousZcStable = all(real(continuousPolesZc) < 0);
filterStability.continuousHrStable = all(real(continuousPolesHr) < 0);
filterStability.discreteZcStable = ...
    all(abs(discretePolesZcFromCoefficients) < 1);
filterStability.discreteHrStable = ...
    all(abs(discretePolesHrFromCoefficients) < 1);
filterStability.discreteHrLowPassStable = ...
    all(abs(discretePolesHrLowPass) < 1);
filterStability.zcStrictlyCausal = (bZcZ(1) == 0);
filterStability.hrStrictlyCausal = (bHrZ(1) == 0);
filterStability.zcDirectFeedthrough = bZcZ(1);
filterStability.hrDirectFeedthrough = bHrZ(1);
filterStability.maxAbsPoleZc = max(abs(discretePolesZcFromCoefficients));
filterStability.maxAbsPoleHr = max(abs(discretePolesHrFromCoefficients));
filterStability.maxAbsPoleHrLowPass = maxAbsOrZero( ...
    discretePolesHrLowPass);
filterStability.minRealZcDiscretePlot = min(real(plotZcDiscreteFit));
filterStability.maxAbsHrExact = max(abs(HrExact));
filterStability.minRealGamma = min(real(gammaExact));
filterStability.twoPortReciprocal = ...
    max(response.reciprocalError) < 1e-6;
filterStability.twoPortSymmetric = ...
    max(response.symmetryError) < 1e-7;
filterStability.isStable = ...
    filterStability.continuousZcStable && ...
    filterStability.continuousHrStable && ...
    filterStability.discreteZcStable && ...
    filterStability.discreteHrStable && ...
    filterStability.discreteHrLowPassStable && ...
    filterStability.zcStrictlyCausal && ...
    (settings.orderHrNum >= settings.orderHrDen || ...
        filterStability.hrStrictlyCausal) && ...
    filterStability.twoPortReciprocal && ...
    filterStability.twoPortSymmetric && ...
    filterStability.maxAbsHrExact <= 1 + 1e-9 && ...
    filterStability.minRealGamma >= -1e-9;

if ~filterStability.continuousZcStable
    error(['The fitted continuous ', zcFitLabel, ...
        ' filter contains unstable poles.']);
end

if ~filterStability.continuousHrStable
    error('The fitted continuous Hr filter contains unstable poles.');
end

if ~filterStability.discreteZcStable
    error(['The discrete ', zcFitLabel, ' filter is unstable: ', ...
        'max |pole| = %.12e.'], filterStability.maxAbsPoleZc);
end

if ~filterStability.discreteHrStable
    error(['The discrete Hr filter is unstable: ', ...
        'max |pole| = %.12e.'], filterStability.maxAbsPoleHr);
end

if ~filterStability.discreteHrLowPassStable
    error(['The discrete Hr low-pass filter is unstable: ', ...
        'max |pole| = %.12e.'], ...
        filterStability.maxAbsPoleHrLowPass);
end

%% Store results

filterResult = struct();
filterResult.method = ...
    'symmetric-two-port-fixed-delay-frequency-dependent-tlm-zc-residual';
filterResult.zcFitQuantity = zcOutputQuantity;
filterResult.zcFitScale = zcFitScale;
filterResult.fitZcResidualAfterHighFrequencySeries = fitZcResidual;
filterResult.ZcBaseR = ZcBaseR;
filterResult.ZcBaseL = ZcBaseL;
filterResult.tau = tau;
filterResult.Zinf = Zinf;
filterResult.Ts = Ts;

filterResult.frequency = frequency;
filterResult.omega = omega;
filterResult.gammaExact = gammaExact;
filterResult.ZcExact = ZcExact;
filterResult.HExact = HExact;
filterResult.HrExact = HrExact;
filterResult.ZcNormalisedExact = ZcNormalisedExact;
filterResult.ZrExact = ZrExact;
filterResult.ZcBaseExact = ZcBaseExact;
filterResult.ZcResidualExact = ZcFittedQuantityExact;

filterResult.ZcContinuous = ZcResidualContinuous;
filterResult.HrContinuous = HrContinuous;
filterResult.ZcDiscrete = ZcResidualDiscrete;
filterResult.HrDiscrete = HrDiscrete;
filterResult.HrLowPassDiscrete = HrLowPassDiscrete;
filterResult.hrLowPass = hrLowPass;

filterResult.bZc = bZcZ;
filterResult.aZc = aZcZ;
filterResult.bHr = bHrZ;
filterResult.aHr = aHrZ;
filterResult.bHrLowPass = hrLowPass.b;
filterResult.aHrLowPass = hrLowPass.a;

filterResult.ZcContinuousFit = ZcContinuousFit;
filterResult.ZcResidualContinuousFit = ZcResidualContinuousFit;
filterResult.HrContinuousFit = HrContinuousFit;
filterResult.ZcDiscreteFit = ZcDiscreteFit;
filterResult.ZcResidualDiscreteFit = ZcResidualDiscreteFit;
filterResult.HrDiscreteFitRaw = HrDiscreteFitRaw;
filterResult.HrLowPassFit = HrLowPassFit;
filterResult.HrDiscreteFit = HrDiscreteFit;
filterResult.zcFitIndex = zcFitIndex;
filterResult.zcFitMaxFrequency = zcFitMaxFrequency;
filterResult.hrFitIndex = hrFitIndex;
filterResult.hrFitMaxFrequency = hrFitMaxFrequency;

filterResult.plot = struct( ...
    'frequency', plotFrequency, ...
    'omega', plotOmega, ...
    'ZcExact', plotResponse.Zc, ...
    'ZcBase', plotZcBase, ...
    'ZcResidualExact', plotResponse.Zc(:) - plotZcBase(:), ...
    'HrExact', plotResponse.Hr, ...
    'HExact', plotResponse.H, ...
    'ZcContinuousFit', plotZcContinuousFit, ...
    'ZcResidualContinuousFit', plotZcResidualContinuousFit, ...
    'HrContinuousFit', plotHrContinuousFit, ...
    'HContinuousFit', plotHContinuousFit, ...
    'ZcDiscreteFit', plotZcDiscreteFit, ...
    'ZcResidualDiscreteFit', plotZcResidualDiscreteFit, ...
    'HrDiscreteFitRaw', plotHrDiscreteFitRaw, ...
    'HrLowPassFit', plotHrLowPassFit, ...
    'HrDiscreteFit', plotHrDiscreteFit, ...
    'HDiscreteFit', plotHDiscreteFit, ...
    'continuousAbcdError', plotContinuousAbcdError, ...
    'discreteAbcdError', plotDiscreteAbcdError);

filterResult.continuousPolesZc = continuousPolesZc;
filterResult.continuousPolesHr = continuousPolesHr;
filterResult.discretePolesZc = discretePolesZc;
filterResult.discretePolesHr = discretePolesHr;
filterResult.discretePolesHrLowPass = discretePolesHrLowPass;
filterResult.discretePolesZcFromCoefficients = ...
    discretePolesZcFromCoefficients;
filterResult.discretePolesHrFromCoefficients = ...
    discretePolesHrFromCoefficients;
filterResult.stability = filterStability;
filterResult.fitInfo = struct( ...
    'Zc', ZcFitInfo, ...
    'Hr', HrFitInfo);
filterResult.settings = settings;

printSymmetricFilterSummary(filterResult);

if settings.makePlot
    plotFrequencyDependentFilterFits(filterResult);
end
end


function [baseR, baseL] = selectZcHighFrequencySeries(lineResult, settings)

if isfield(settings, 'zcHighFrequencySeriesR') && ...
        isfield(settings, 'zcHighFrequencySeriesL')
    baseR = settings.zcHighFrequencySeriesR;
    baseL = settings.zcHighFrequencySeriesL;
    return;
end

source = 'commonSeries';

if isfield(settings, 'zcHighFrequencySeriesSource')
    source = settings.zcHighFrequencySeriesSource;
end

switch source
    case 'commonSeries'
        baseR = lineResult.commonSeries.R;
        baseL = lineResult.commonSeries.L;
    otherwise
        error('Unsupported Zc high-frequency series source: %s.', source);
end
end


function totalZc = addZcBaseIfNeeded(fittedQuantity, baseQuantity, useBase)

fittedQuantity = fittedQuantity(:);

if useBase
    totalZc = baseQuantity(:) + fittedQuantity;
else
    totalZc = fittedQuantity;
end
end


function hrLowPass = designHrLowPass(settings, Ts)

hrLowPass = struct( ...
    'enabled', false, ...
    'design', 'unity', ...
    'order', 0, ...
    'cutoffFrequency', Inf, ...
    'sampleTime', Ts, ...
    'b', 1, ...
    'a', 1);

if ~isfield(settings, 'hrLowPass') || ...
        ~getLogicalSetting(settings.hrLowPass, 'enabled', false)
    return;
end

order = round(getNumericSetting(settings.hrLowPass, 'order', 2));
cutoffFrequency = getNumericSetting( ...
    settings.hrLowPass, ...
    'cutoffFrequency', ...
    NaN);
nyquistFrequency = 0.5/Ts;

if order < 1 || ~isfinite(order)
    error('Hr low-pass Butterworth order must be a positive integer.');
end

if cutoffFrequency <= 0 || cutoffFrequency >= nyquistFrequency || ...
        ~isfinite(cutoffFrequency)
    error(['Hr low-pass cutoff frequency %.12e Hz must be between 0 ', ...
        'and Nyquist %.12e Hz.'], ...
        cutoffFrequency, nyquistFrequency);
end

[b, a] = butter(order, cutoffFrequency/nyquistFrequency, 'low');

b = b(:).'/a(1);
a = a(:).'/a(1);
b = realIfNumericallyReal(b);
a = realIfNumericallyReal(a);

hrLowPass = struct( ...
    'enabled', true, ...
    'design', 'butterworth', ...
    'order', order, ...
    'cutoffFrequency', cutoffFrequency, ...
    'normalisedCutoff', cutoffFrequency/nyquistFrequency, ...
    'nyquistFrequency', nyquistFrequency, ...
    'sampleTime', Ts, ...
    'b', b, ...
    'a', a);
end


function [continuousSystem, fitInfo] = fitContinuousResponse( ...
    exactResponse, omegaScaled, wScale, numeratorOrder, denominatorOrder, ...
    weight, iterations)

[bQ, aQ] = invfreqs( ...
    exactResponse, ...
    omegaScaled, ...
    numeratorOrder, ...
    denominatorOrder, ...
    weight, ...
    iterations);

[bS, aS] = scaledPolynomialToPhysicalS(bQ, aQ, wScale);

continuousSystem = tf(bS, aS);
fitInfo = struct( ...
    'bQ', bQ, ...
    'aQ', aQ, ...
    'bS', bS, ...
    'aS', aS, ...
    'numeratorOrder', numeratorOrder, ...
    'denominatorOrder', denominatorOrder, ...
    'iterations', iterations);
end


function value = getLogicalSetting(settings, fieldName, defaultValue)

if isfield(settings, fieldName)
    value = logical(settings.(fieldName));
else
    value = defaultValue;
end
end


function value = getNumericSetting(settings, fieldName, defaultValue)

if isfield(settings, fieldName)
    value = settings.(fieldName);
else
    value = defaultValue;
end
end


function frequency = buildPlotFrequency(settings, fitFrequency)

if isfield(settings, 'plotFrequency')
    frequency = settings.plotFrequency(:);
    return;
end

if isfield(settings, 'plotFMax')
    plotFMin = getNumericSetting(settings, 'plotFMin', settings.fMin);
    plotFMax = settings.plotFMax;
    plotNFrequency = round(getNumericSetting( ...
        settings, ...
        'plotNFrequency', ...
        numel(fitFrequency)));

    frequency = logspace( ...
        log10(plotFMin), ...
        log10(plotFMax), ...
        plotNFrequency).';
else
    frequency = fitFrequency(:);
end
end


function errorValue = compareOriginalTwoPortFitError( ...
    lineResult, frequency, ZcFit, Hfit)

frequency = frequency(:);
s = 1j*2*pi*frequency;
ZcFit = ZcFit(:);
Hfit = Hfit(:);
zbase = lineResult.Zinf;
errorValue = zeros(numel(frequency), 1);

for k = 1:numel(frequency)
    Tfit = reconstructSeparatedFittedTwoPort( ...
        lineResult, ...
        s(k), ...
        ZcFit(k), ...
        Hfit(k));

    Toriginal = originalAsymmetricTwoPort( ...
        lineResult, ...
        s(k));

    errorValue(k) = norm( ...
        normaliseABCD(Tfit, zbase) - ...
        normaliseABCD(Toriginal, zbase), ...
        'fro') / ...
        max(1, norm(normaliseABCD(Toriginal, zbase), 'fro'));
end
end


function T = reconstructSeparatedFittedTwoPort(lineResult, s, Zc, H)

H = protectSmallComplexValue(H, 1e-300);
Zc = protectSmallComplexValue(Zc, 1e-300);

A = 0.5*(H + 1/H);
sinhGamma = 0.5*(1/H - H);
Tline = [A, Zc*sinhGamma; sinhGamma/Zc, A];

T = ...
    seriesABCD(lineResult.separatedSeries.terminal1.R + ...
        s*lineResult.separatedSeries.terminal1.L) * ...
    Tline * ...
    seriesABCD(lineResult.separatedSeries.terminal2.R + ...
        s*lineResult.separatedSeries.terminal2.L);
end


function T = originalAsymmetricTwoPort(lineResult, s)

Zterminal1 = lineResult.inverterSide.R + ...
    s*lineResult.inverterSide.L;
Zterminal2 = lineResult.networkSide.R + ...
    s*lineResult.networkSide.L;
Yshunt = s*lineResult.shunt.C ./ ...
    (1 + s*lineResult.shunt.Rc*lineResult.shunt.C);

T = ...
    seriesABCD(Zterminal1) * ...
    shuntABCD(Yshunt) * ...
    seriesABCD(Zterminal2);
end


function value = protectSmallComplexValue(value, floorValue)

if abs(value) >= floorValue
    return;
end

angleValue = angle(value);

if ~isfinite(angleValue)
    angleValue = 0;
end

value = floorValue*exp(1j*angleValue);
end


function value = maxAbsOrZero(values)

if isempty(values)
    value = 0;
else
    value = max(abs(values));
end
end


function printSymmetricFilterSummary(filterResult)

fprintf('\n============================================================\n');
fprintf('Symmetric two-port frequency-dependent filter generation\n');
fprintf('============================================================\n');
fprintf('Zinf = %.12e ohm\n', filterResult.Zinf);
fprintf('Zc base R = %.12e ohm\n', filterResult.ZcBaseR);
fprintf('Zc base L = %.12e H\n', filterResult.ZcBaseL);
fprintf('tau  = %.12e s\n', filterResult.tau);
fprintf('Ts   = %.12e s\n\n', filterResult.Ts);

fprintf('Discrete residual Zc numerator (ohm):\n');
disp(filterResult.bZc);

fprintf('Discrete residual Zc denominator:\n');
disp(filterResult.aZc);

fprintf('Discrete Hr numerator:\n');
disp(filterResult.bHr);

fprintf('Discrete Hr denominator:\n');
disp(filterResult.aHr);

if isfield(filterResult, 'hrLowPass') && filterResult.hrLowPass.enabled
    fprintf('Discrete Hr Butterworth numerator hr_lp_b:\n');
    disp(filterResult.bHrLowPass);

    fprintf('Discrete Hr Butterworth denominator hr_lp_a:\n');
    disp(filterResult.aHrLowPass);

    fprintf('Hr Butterworth cutoff frequency = %.12e Hz\n', ...
        filterResult.hrLowPass.cutoffFrequency);
    fprintf('Maximum |pole(Hr low-pass)| = %.12e\n', ...
        filterResult.stability.maxAbsPoleHrLowPass);
end

fprintf('Maximum |pole(Zc)|      = %.12e\n', ...
    filterResult.stability.maxAbsPoleZc);
fprintf('Maximum |pole(Hr)|      = %.12e\n', ...
    filterResult.stability.maxAbsPoleHr);
fprintf('Minimum Re(total discrete Zc in plot band) = %.12e\n', ...
    filterResult.stability.minRealZcDiscretePlot);
fprintf('Discrete Zc stability:       %s\n', ...
    passFailText(filterResult.stability.discreteZcStable));
fprintf('Discrete Hr stability:      %s\n', ...
    passFailText(filterResult.stability.discreteHrStable));
if isfield(filterResult.stability, 'discreteHrLowPassStable')
    fprintf('Discrete Hr LP stability:   %s\n', ...
        passFailText(filterResult.stability.discreteHrLowPassStable));
end
fprintf('Discrete Zc causal:          %s\n', ...
    passFailText(filterResult.stability.zcStrictlyCausal));
fprintf('Discrete Hr causal:         %s\n', ...
    passFailText(filterResult.stability.hrStrictlyCausal));
fprintf('Overall filter stability:   %s\n', ...
    passFailText(filterResult.stability.isStable));
fprintf('============================================================\n\n');
end
