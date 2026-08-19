function filterResult = buildFrequencyDependentLineFilters( ...
    lineResult, settings)
%BUILDFREQUENCYDEPENDENTLINEFILTERS
%
% Construct continuous and discrete rational approximations for
%
%   Zc(s) = Zinf * [1 + Zr(s)]
%
% and
%
%   H(s) = exp(-s*tau) * Hr(s).
%
% The physical communication channel implements exp(-s*tau).
% Only Zr(s) and Hr(s) are implemented using discrete IIR filters.

%% 1. Read optimised line parameters

Rline = lineResult.Rline;
Lline = lineResult.Lline;
Gline = lineResult.Gline;
Cline = lineResult.Cline;

tau  = lineResult.tau;
Zinf = lineResult.Zinf;

Ts = settings.Ts;

%% 2. Frequency grid

frequency = logspace( ...
    log10(settings.fMin), ...
    log10(settings.fMax), ...
    settings.nFrequency).';

omega = 2*pi*frequency;
s = 1j*omega;

%% 3. Exact frequency-dependent line quantities

Zseries = Rline + s*Lline;
Yshunt  = Gline + s*Cline;

gammaExact = sqrt(Zseries.*Yshunt);

% Select the passive branch frequency by frequency.
for k = 1:numel(gammaExact)

    if real(gammaExact(k)) < 0
        gammaExact(k) = -gammaExact(k);

    elseif abs(real(gammaExact(k))) < 1e-14 && ...
            imag(gammaExact(k)) < 0

        gammaExact(k) = -gammaExact(k);
    end
end

ZcExact = Zseries./gammaExact;

HExact = exp(-gammaExact);

%% 4. Extract high-frequency constant impedance and pure delay

ZrExact = ZcExact/Zinf - 1;

% H = exp(-s*tau) Hr
%
% Therefore
%
% Hr = H exp(+s*tau)
HrExact = exp(-gammaExact + s*tau);

%% 5. Frequency weighting

lowFrequencyWeight = ...
    1 + settings.lowFrequencyWeight ./ ...
    (1 + (frequency/1000).^2);

% invfreqs expects a real nonnegative weight vector.
weight = lowFrequencyWeight(:);

%% 6. Frequency scaling

% Fitting directly with rad/s values up to several hundred krad/s may
% produce badly conditioned polynomial coefficients. Use q=s/wScale.
wScale = sqrt(min(omega)*max(omega));

omegaScaled = omega/wScale;

%% 7. Fit Zr(q)

validateStrictlyProperFitOrder( ...
    'Zr', settings.orderZrNum, settings.orderZrDen);

[bZrQ, aZrQ] = invfreqs( ...
    ZrExact, ...
    omegaScaled, ...
    settings.orderZrNum, ...
    settings.orderZrDen, ...
    weight, ...
    settings.iterationsZr);

[bZrS, aZrS] = scaledPolynomialToPhysicalS( ...
    bZrQ, ...
    aZrQ, ...
    wScale);

ZrContinuous = tf(bZrS, aZrS);

%% 8. Fit Hr(q)

[bHrQ, aHrQ] = invfreqs( ...
    HrExact, ...
    omegaScaled, ...
    settings.orderHrNum, ...
    settings.orderHrDen, ...
    weight, ...
    settings.iterationsHr);

[bHrS, aHrS] = scaledPolynomialToPhysicalS( ...
    bHrQ, ...
    aHrQ, ...
    wScale);

HrContinuous = tf(bHrS, aHrS);

%% 9. Stabilise fitted continuous models if necessary

ZrContinuous = stabiliseContinuousTransferFunction(ZrContinuous);
HrContinuous = stabiliseContinuousTransferFunction(HrContinuous);

%% 10. Discretise

ZrDiscrete = c2d( ...
    ZrContinuous, ...
    Ts, ...
    settings.discretisationMethod);

HrDiscrete = c2d( ...
    HrContinuous, ...
    Ts, ...
    settings.discretisationMethod);

[bZrZ, aZrZ] = tfdata(ZrDiscrete, 'v');
[bHrZ, aHrZ] = tfdata(HrDiscrete, 'v');

% Normalise coefficients. Zr must be strictly causal because the Simulink
% characteristic-impedance subsystem adds the direct Zinf term separately.
[bZrZ, aZrZ] = normaliseStrictlyProperDiscreteCoefficients( ...
    bZrZ, aZrZ, 'Zr');

bHrZ = bHrZ/aHrZ(1);
aHrZ = aHrZ/aHrZ(1);

%% 11. Evaluate fitted responses

ZrContinuousFit = squeeze(freqresp( ...
    ZrContinuous, ...
    omega));

HrContinuousFit = squeeze(freqresp( ...
    HrContinuous, ...
    omega));

ZrDiscreteFit = squeeze(freqresp( ...
    ZrDiscrete, ...
    omega));

HrDiscreteFit = squeeze(freqresp( ...
    HrDiscrete, ...
    omega));

%% 12. Stability checks

continuousPolesZr = pole(ZrContinuous);
continuousPolesHr = pole(HrContinuous);

discretePolesZr = pole(ZrDiscrete);
discretePolesHr = pole(HrDiscrete);

discretePolesZrFromCoefficients = roots(aZrZ);
discretePolesHrFromCoefficients = roots(aHrZ);

filterStability = struct();
filterStability.continuousZrStable = all(real(continuousPolesZr) < 0);
filterStability.continuousHrStable = all(real(continuousPolesHr) < 0);
filterStability.discreteZrStable = ...
    all(abs(discretePolesZrFromCoefficients) < 1);
filterStability.discreteHrStable = ...
    all(abs(discretePolesHrFromCoefficients) < 1);
filterStability.zrStrictlyCausal = (bZrZ(1) == 0);
filterStability.zrDirectFeedthrough = bZrZ(1);
filterStability.maxAbsPoleZr = max(abs(discretePolesZrFromCoefficients));
filterStability.maxAbsPoleHr = max(abs(discretePolesHrFromCoefficients));
filterStability.isStable = ...
    filterStability.continuousZrStable && ...
    filterStability.continuousHrStable && ...
    filterStability.discreteZrStable && ...
    filterStability.discreteHrStable && ...
    filterStability.zrStrictlyCausal;

if ~filterStability.continuousZrStable
    error('The fitted continuous Zr filter contains unstable poles.');
end

if ~filterStability.continuousHrStable
    error('The fitted continuous Hr filter contains unstable poles.');
end

if ~filterStability.discreteZrStable
    error(['The discrete Zr filter is unstable: ', ...
        'max |pole| = %.12e.'], filterStability.maxAbsPoleZr);
end

if ~filterStability.zrStrictlyCausal
    error(['The discrete Zr filter has direct feedthrough: ', ...
        '|b(1)| = %.12e.'], abs(filterStability.zrDirectFeedthrough));
end

if ~filterStability.discreteHrStable
    error(['The discrete Hr filter is unstable: ', ...
        'max |pole| = %.12e.'], filterStability.maxAbsPoleHr);
end

%% 13. Store results

filterResult = struct();

filterResult.Rline = Rline;
filterResult.Lline = Lline;
filterResult.Gline = Gline;
filterResult.Cline = Cline;

filterResult.tau  = tau;
filterResult.Zinf = Zinf;
filterResult.Ts   = Ts;

filterResult.frequency = frequency;
filterResult.omega = omega;

filterResult.gammaExact = gammaExact;
filterResult.ZcExact = ZcExact;
filterResult.HExact = HExact;

filterResult.ZrExact = ZrExact;
filterResult.HrExact = HrExact;

filterResult.ZrContinuous = ZrContinuous;
filterResult.HrContinuous = HrContinuous;

filterResult.ZrDiscrete = ZrDiscrete;
filterResult.HrDiscrete = HrDiscrete;

filterResult.bZr = bZrZ;
filterResult.aZr = aZrZ;

filterResult.bHr = bHrZ;
filterResult.aHr = aHrZ;

filterResult.ZrContinuousFit = ZrContinuousFit;
filterResult.HrContinuousFit = HrContinuousFit;

filterResult.ZrDiscreteFit = ZrDiscreteFit;
filterResult.HrDiscreteFit = HrDiscreteFit;

filterResult.continuousPolesZr = continuousPolesZr;
filterResult.continuousPolesHr = continuousPolesHr;

filterResult.discretePolesZr = discretePolesZr;
filterResult.discretePolesHr = discretePolesHr;
filterResult.discretePolesZrFromCoefficients = ...
    discretePolesZrFromCoefficients;
filterResult.discretePolesHrFromCoefficients = ...
    discretePolesHrFromCoefficients;
filterResult.stability = filterStability;

filterResult.settings = settings;

%% 14. Print coefficients

fprintf('\n============================================================\n');
fprintf('Frequency-dependent line filter generation\n');
fprintf('============================================================\n');

fprintf('Zinf = %.12e ohm\n', Zinf);
fprintf('tau  = %.12e s\n', tau);
fprintf('Ts   = %.12e s\n\n', Ts);

fprintf('Discrete Zr numerator:\n');
disp(bZrZ);

fprintf('Discrete Zr denominator:\n');
disp(aZrZ);

fprintf('Discrete Hr numerator:\n');
disp(bHrZ);

fprintf('Discrete Hr denominator:\n');
disp(aHrZ);

fprintf('Maximum |pole(Zr)| = %.12e\n', ...
    filterStability.maxAbsPoleZr);

fprintf('Maximum |pole(Hr)| = %.12e\n', ...
    filterStability.maxAbsPoleHr);

fprintf('Discrete Zr stability: %s\n', ...
    passFailText(filterStability.discreteZrStable));

fprintf('Discrete Hr stability: %s\n', ...
    passFailText(filterStability.discreteHrStable));

fprintf('Discrete Zr strictly causal: %s\n', ...
    passFailText(filterStability.zrStrictlyCausal));

fprintf('============================================================\n\n');

%% 15. Plot fits

if settings.makePlot
    plotFrequencyDependentFilterFits(filterResult);
end

end


