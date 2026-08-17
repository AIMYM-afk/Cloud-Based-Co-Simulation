%% fit_non_heaviside_line.m
% Fit the characteristic impedance Zc(s)
% and propagation function H(s) of a non-Heaviside line.
%
% Required:
%   Signal Processing Toolbox: invfreqs
%   Control System Toolbox: tf, freqresp, impulse

clear;
clc;
close all;

projectDir = fileparts(mfilename('fullpath'));
addpath(fullfile(projectDir, 'functions'));

%% 1. Shared line and fitting parameters

[params, DPL, lineConfig] = unitlm_transmission_line_config();
fitConfig = unitlm_fit_config();

R = lineConfig.R;       % ohm/km
L = lineConfig.L;       % H/km
C = lineConfig.C;       % F/km
G = lineConfig.G;       % S/km

fMin = fitConfig.fMin;              % Hz
fMax = fitConfig.fMax;              % Hz
nFrequency = fitConfig.nFrequency;

orderZcDen = fitConfig.orderZcDen;  % denominator order
orderZcNum = fitConfig.orderZcNum;  % numerator order
orderHr = fitConfig.orderHr;
fitIterations = fitConfig.iterations;
Ts = params.sampleTime;             % s

if fMax >= 1/(2*Ts)
    error( ...
        ['fitConfig.fMax must be below the Nyquist frequency for direct ', ...
         'initialize_unitlm_microgrid validation. fMax = %.6e Hz, ', ...
         'Nyquist = %.6e Hz.'], ...
        fMax, ...
        1/(2*Ts));
end

f = logspace(log10(fMin), log10(fMax), nFrequency).';
w = 2*pi*f;
s = 1j*w;
%% 2. Prescribed interface delay
n = params.batchSteps;
delay = lineConfig.delay;           % s, fixed communication/interface delay

% High-frequency asymptotic propagation velocity
velocityHF = lineConfig.velocityHF;        % km/s

% Cable length corresponding to the prescribed delay
lineLength = lineConfig.delayEquivalentLength;   % km

% Equivalent expression:
% lineLength = delay/sqrt(L*C);

fprintf('Fixed interface delay = %.6e s = %.3f us\n', ...
    delay, delay*1e6);

fprintf('High-frequency velocity = %.6e km/s\n', ...
    velocityHF);

fprintf('Equivalent cable length = %.6e km = %.3f m\n', ...
    lineLength, lineLength*1000);

%% 3. Exact transmission-line functions

gammaExact = sqrt((R + s*L).*(G + s*C));

ZcExact = sqrt((R + s*L)./(G + s*C));

HExact = exp(-gammaExact*lineLength);

%% 4. Extract the prescribed interface delay

% The equivalent line length is selected such that:
%
%       delay = lineLength*sqrt(L*C)
%
% Decompose:
%
%       H(s) = exp(-s*delay)*Hr(s)

HrExact = HExact.*exp(s*delay);
%% 5. Normalize frequency before fitting
%
% Instead of directly fitting with very large angular frequencies,
% define:
%
%       q = s/wScale
%
% invfreqs therefore works over a better-conditioned frequency range.

wScale = sqrt(w(1)*w(end));

wNormalized = w/wScale;

%% 6. Fit characteristic impedance
%
% At high frequency:
%
%       Zc -> sqrt(L/C)
%
% Therefore, fit only the ohmic residual:
%
%       Zc = Zinf + Zr_ohm

Zinf = sqrt(L/C);

ZrOhmExact = ZcExact - Zinf;

% Keep the old relative weighting convention: weightFloorZc is interpreted
% as a fraction of Zinf when the residual is fitted in ohms.
weightZc = 1./max(abs(ZrOhmExact), fitConfig.weightFloorZc*Zinf);

[bZr, aZr] = invfreqs( ...
    ZrOhmExact, ...
    wNormalized, ...
    orderZcNum, ...
    orderZcDen, ...
    weightZc, ...
    fitIterations);

% Transfer function in normalized variable q = s/wScale
ZrOhmNormalized = tf(bZr, aZr);

% Evaluate fitted ohmic residual at q = j*w/wScale
ZrOhmFit = squeeze(freqresp(ZrOhmNormalized, wNormalized));
ZrOhmFit = ZrOhmFit(:);

% Reconstruct characteristic impedance
ZcFit = Zinf + ZrOhmFit;

%% 7. Fit residual propagation function Hr(s)

weightHr = 1./max(abs(HrExact), 0.2);

[bHr, aHr] = invfreqs( ...
    HrExact, ...
    wNormalized, ...
    orderHr, ...
    orderHr, ...
    weightHr, ...
    fitIterations);

HrNormalized = tf(bHr, aHr);

HrFit = squeeze(freqresp(HrNormalized, wNormalized));
HrFit = HrFit(:);

% Restore the fixed delay
HFit = HrFit.*exp(-s*delay);

%% 8. Display fitted rational functions

fprintf('\n========================================\n');
fprintf('Characteristic impedance fitting\n');
fprintf('========================================\n');

fprintf('\nZinf = sqrt(L/C) = %.6f ohm\n', Zinf);

fprintf('\nZc(s) is represented as:\n');
fprintf('Zc(s) = Zinf + Zr_ohm(s/wScale)\n');

fprintf('\nwScale = %.6e rad/s\n', wScale);

fprintf('\nZr_ohm(q), q = s/wScale:\n');


fprintf('\n========================================\n');
fprintf('Propagation-function fitting\n');
fprintf('========================================\n');

fprintf('\nH(s) = exp(-s*delay)*Hr(s/wScale)\n');

fprintf('\nHr(q), q = s/wScale:\n');


%% 9. Fitting errors

ZcRelativeError = abs(ZcFit-ZcExact)./abs(ZcExact);

HRelativeError = abs(HFit-HExact) ...
    ./max(abs(HExact), 1e-10);

fprintf('\n========================================\n');
fprintf('Fitting errors\n');
fprintf('========================================\n');

fprintf('Zc RMS relative error = %.4e\n', ...
    sqrt(mean(ZcRelativeError.^2)));

fprintf('Zc maximum relative error = %.4e\n', ...
    max(ZcRelativeError));

fprintf('H RMS relative error = %.4e\n', ...
    sqrt(mean(HRelativeError.^2)));

fprintf('H maximum relative error = %.4e\n', ...
    max(HRelativeError));

%% 10. Bode comparison: Zc

figure;

subplot(3,1,1);

semilogx(f, 20*log10(abs(ZcExact)), ...
    'LineWidth', 1.4);

hold on;

semilogx(f, 20*log10(abs(ZcFit)), '--', ...
    'LineWidth', 1.4);

grid on;

ylabel('Magnitude (dB\Omega)');
title('Characteristic impedance Z_c');

legend('Exact', 'Rational fit', ...
    'Location', 'best');

subplot(3,1,2);

semilogx(f, unwrap(angle(ZcExact))*180/pi, ...
    'LineWidth', 1.4);

hold on;

semilogx(f, unwrap(angle(ZcFit))*180/pi, '--', ...
    'LineWidth', 1.4);

grid on;

ylabel('Phase (deg)');

subplot(3,1,3);

loglog(f, ZcRelativeError, ...
    'LineWidth', 1.4);

grid on;

xlabel('Frequency (Hz)');
ylabel('Relative error');

%% 11. Bode comparison: H

figure;

subplot(3,1,1);

semilogx(f, 20*log10(abs(HExact)), ...
    'LineWidth', 1.4);

hold on;

semilogx(f, 20*log10(abs(HFit)), '--', ...
    'LineWidth', 1.4);

grid on;

ylabel('Magnitude (dB)');
title('Propagation function H');

legend('Exact', 'Rational fit', ...
    'Location', 'best');

subplot(3,1,2);

semilogx(f, unwrap(angle(HExact))*180/pi, ...
    'LineWidth', 1.4);

hold on;

semilogx(f, unwrap(angle(HFit))*180/pi, '--', ...
    'LineWidth', 1.4);

grid on;

ylabel('Phase (deg)');

subplot(3,1,3);

loglog(f, HRelativeError, ...
    'LineWidth', 1.4);

grid on;

xlabel('Frequency (Hz)');
ylabel('Relative error');

%% 12. Convolution kernels of the rational residual functions
%
% Note:
% These kernels correspond to the normalized variable q = s/wScale.
%
% For an actual continuous-time implementation, convert the poles and
% coefficients from q-domain to s-domain, or implement the corresponding
% state equations with the state derivative multiplied by wScale.

tNormalized = linspace(0, 100, 3000).';

kernelZr = impulse(ZrOhmNormalized, tNormalized);
kernelHr = impulse(HrNormalized, tNormalized);

figure;

plot(tNormalized, kernelZr, ...
    'LineWidth', 1.3);

grid on;

xlabel('Normalized time, wScale t');
ylabel('Kernel amplitude');
title('Convolution kernel of Z_{r,ohm}');

figure;

plot(tNormalized, kernelHr, ...
    'LineWidth', 1.3);

grid on;

xlabel('Normalized time, wScale t');
ylabel('Kernel amplitude');
title('Convolution kernel of H_r');

%% -----------------------------------------------------------------%%
% ---------------------     FIR     ---------------------------------%
% -------------------------------------------------------------------%


%% 13. FIR implementation of the fitted rational models

% Number of FIR coefficients used for the rational residual parts
nFirZr = fitConfig.nFirZr;
nFirHr = fitConfig.nFirHr;

%% 13.1 Convert normalized q-domain models to physical s-domain models
%
% The fitted transfer functions use:
%
%       q = s/wScale
%
% If the normalized state-space model is:
%
%       dx/dtheta = Aq*x + Bq*u
%       y         = Cq*x + Dq*u
%
% where theta = wScale*t, then:
%
%       dx/dt = wScale*Aq*x + wScale*Bq*u

ZrSSNormalized = ss(ZrOhmNormalized);
HrSSNormalized = ss(HrNormalized);

% Extract the ABCD matrices in state space model
[AqZr, BqZr, CqZr, DqZr] = ssdata(ZrSSNormalized);
[AqHr, BqHr, CqHr, DqHr] = ssdata(HrSSNormalized);


ZrSSPhysical = ss( ...
    wScale*AqZr, ...
    wScale*BqZr, ...
    CqZr, ...
    DqZr);

HrSSPhysical = ss( ...
    wScale*AqHr, ...
    wScale*BqHr, ...
    CqHr, ...
    DqHr);

% Check the fitted continuous-time models
if ~isstable(ZrSSPhysical)
    warning('The fitted Zr model is unstable.');
end

if ~isstable(HrSSPhysical)
    warning('The fitted Hr model is unstable.');
end

%% 13.2 Discretize the fitted models

ZrDiscrete = c2d(ZrSSPhysical, Ts, fitConfig.discretizationMethod);
HrDiscrete = c2d(HrSSPhysical, Ts, fitConfig.discretizationMethod);

%% ----------------------------------------------------------------- %%
% ---------------------     IIR     --------------------------------- %
% ------------------------------------------------------------------- %

%% 13.3 Construct the complete discrete Zc model
%
% Zc(s) = Zinf + Zr_ohm(s)
%
% ZrDiscrete is the discrete model of Zr_ohm.
% The constant Zinf term is represented as a static gain.

unityDiscrete = ss([], [], [], 1, Ts);

ZcDiscrete = Zinf*unityDiscrete + ZrDiscrete;

%% 13.4 Convert discrete state-space models to IIR coefficients
%
% The discrete transfer functions have the form:
%
%                  b0 + b1 z^-1 + ... + bm z^-m
%       G(z) = ---------------------------------------
%                  a0 + a1 z^-1 + ... + an z^-n
%
% The denominator coefficients produce the recursive part.

[bZcD, aZcD] = tfdata(tf(ZcDiscrete), 'v');
[bHrD, aHrD] = tfdata(tf(HrDiscrete), 'v');

% Normalize coefficients so that a(1) = 1
bZcD = bZcD/aZcD(1);
aZcD = aZcD/aZcD(1);

bHrD = bHrD/aHrD(1);
aHrD = aHrD/aHrD(1);

fprintf('\n========================================\n');
fprintf('Discrete IIR coefficients\n');
fprintf('========================================\n');

fprintf('\nZc numerator coefficients bZcD:\n');
disp(bZcD);

fprintf('Zc denominator coefficients aZcD:\n');
disp(aZcD);

fprintf('\nHr numerator coefficients bHrD:\n');
disp(bHrD);

fprintf('Hr denominator coefficients aHrD:\n');
disp(aHrD);

%% 13.5 Check discrete-time stability

if ~isstable(ZcDiscrete)
    warning('The discrete Zc IIR model is unstable.');
end

if ~isstable(HrDiscrete)
    warning('The discrete Hr IIR model is unstable.');
end

fprintf('\nMaximum discrete Zc pole magnitude = %.6f\n', ...
    max(abs(pole(ZcDiscrete))));

fprintf('Maximum discrete Hr pole magnitude = %.6f\n', ...
    max(abs(pole(HrDiscrete))));

%% 13.6 Time-domain IIR implementation

% Example time vector
tTest = (0:Ts:2e-3).';

% Example current input
currentInput = ...
    sin(2*pi*1000*tTest) ...
    + 0.2*sin(2*pi*10000*tTest);

% Example travelling-wave input
waveInput = currentInput;

% Apply the complete characteristic-impedance IIR model
zcOutputIIR = filter( ...
    bZcD, ...
    aZcD, ...
    currentInput);

% Apply the residual propagation-function IIR model
hrOutputIIR = filter( ...
    bHrD, ...
    aHrD, ...
    waveInput);

%% 13.7 Add the explicit fixed propagation delay

nDelay = round(delay/Ts);

delayImplemented = nDelay*Ts;

if abs(delayImplemented-delay) > 1e-12
    warning( ...
        ['The requested delay is not an integer multiple of Ts. ' ...
         'Requested delay = %.6e s; implemented delay = %.6e s.'], ...
        delay, ...
        delayImplemented);
end

% Apply the pure delay after Hr filtering
hOutputIIR = zeros(size(hrOutputIIR));

if nDelay == 0

    hOutputIIR = hrOutputIIR;

elseif nDelay < length(hrOutputIIR)

    hOutputIIR(nDelay+1:end) = ...
        hrOutputIIR(1:end-nDelay);

end

fprintf('\nRequested delay   = %.6e s\n', delay);
fprintf('Delay samples     = %d\n', nDelay);
fprintf('Implemented delay = %.6e s\n', delayImplemented);

%% 13.8 Plot the time-domain IIR outputs

figure;

subplot(2,1,1);

plot( ...
    tTest*1e3, ...
    currentInput, ...
    'LineWidth', 1.2);

hold on;

plot( ...
    tTest*1e3, ...
    zcOutputIIR, ...
    'LineWidth', 1.2);

grid on;

xlabel('Time (ms)');
ylabel('Amplitude');

title('Time-domain characteristic-impedance IIR operation');

legend( ...
    'Current input', ...
    'Z_c IIR output', ...
    'Location', ...
    'best');

subplot(2,1,2);

plot( ...
    tTest*1e3, ...
    waveInput, ...
    'LineWidth', 1.2);

hold on;

plot( ...
    tTest*1e3, ...
    hOutputIIR, ...
    'LineWidth', 1.2);

grid on;

xlabel('Time (ms)');
ylabel('Amplitude');

title('Time-domain propagation-function IIR operation');

legend( ...
    'Wave input', ...
    'H IIR output', ...
    'Location', ...
    'best');

%% 13.9 Evaluate IIR responses at the original fitting frequencies

fs = 1/Ts;

if fMax > fs/2
    error( ...
        ['The fitting maximum frequency exceeds the Nyquist frequency. ' ...
         'fMax = %.6e Hz, Nyquist frequency = %.6e Hz.'], ...
        fMax, ...
        fs/2);
end

% Complete characteristic-impedance IIR response
ZcIIRResponse = freqz( ...
    bZcD, ...
    aZcD, ...
    f, ...
    fs);

% Residual propagation-function IIR response
HrIIRResponse = freqz( ...
    bHrD, ...
    aHrD, ...
    f, ...
    fs);

% Restore the fixed pure delay
HIIRResponse = HrIIRResponse ...
             .* exp(-1j*2*pi*f*delayImplemented);

ZcIIRResponse = ZcIIRResponse(:);
HrIIRResponse = HrIIRResponse(:);
HIIRResponse = HIIRResponse(:);

%% 13.10 Calculate continuous-to-discrete IIR errors

ZcIIRError = ...
    abs(ZcIIRResponse-ZcFit) ...
    ./ max(abs(ZcFit),1e-12);

HIIRError = ...
    abs(HIIRResponse-HFit) ...
    ./ max(abs(HFit),1e-12);

fprintf('\n========================================\n');
fprintf('Continuous rational fit vs discrete IIR\n');
fprintf('========================================\n');

fprintf('Zc IIR RMS relative error = %.4e\n', ...
    sqrt(mean(ZcIIRError.^2)));

fprintf('Zc IIR maximum relative error = %.4e\n', ...
    max(ZcIIRError));

fprintf('H IIR RMS relative error = %.4e\n', ...
    sqrt(mean(HIIRError.^2)));

fprintf('H IIR maximum relative error = %.4e\n', ...
    max(HIIRError));

%% 13.11 Plot Zc: exact, continuous fit and discrete IIR

figure;

subplot(3,1,1);

semilogx( ...
    f, ...
    20*log10(abs(ZcExact)), ...
    'LineWidth', 1.3);

hold on;

semilogx( ...
    f, ...
    20*log10(abs(ZcFit)), ...
    '--', ...
    'LineWidth', 1.3);

semilogx( ...
    f, ...
    20*log10(abs(ZcIIRResponse)), ...
    ':', ...
    'LineWidth', 1.5);

grid on;

ylabel('Magnitude (dB\Omega)');
title('Characteristic impedance Z_c');

legend( ...
    'Exact line model', ...
    'Continuous rational fit', ...
    'Discrete IIR model', ...
    'Location', ...
    'best');

subplot(3,1,2);

semilogx( ...
    f, ...
    unwrap(angle(ZcExact))*180/pi, ...
    'LineWidth', 1.3);

hold on;

semilogx( ...
    f, ...
    unwrap(angle(ZcFit))*180/pi, ...
    '--', ...
    'LineWidth', 1.3);

semilogx( ...
    f, ...
    unwrap(angle(ZcIIRResponse))*180/pi, ...
    ':', ...
    'LineWidth', 1.5);

grid on;

ylabel('Phase (deg)');

subplot(3,1,3);

loglog( ...
    f, ...
    ZcIIRError, ...
    'LineWidth', 1.3);

grid on;

xlabel('Frequency (Hz)');
ylabel('IIR relative error');

%% 13.12 Plot H: exact, continuous fit and discrete IIR

figure;

subplot(3,1,1);

semilogx( ...
    f, ...
    20*log10(abs(HExact)), ...
    'LineWidth', 1.3);

hold on;

semilogx( ...
    f, ...
    20*log10(abs(HFit)), ...
    '--', ...
    'LineWidth', 1.3);

semilogx( ...
    f, ...
    20*log10(abs(HIIRResponse)), ...
    ':', ...
    'LineWidth', 1.5);

grid on;

ylabel('Magnitude (dB)');
title('Propagation function H');

legend( ...
    'Exact line model', ...
    'Continuous rational fit', ...
    'Discrete IIR model', ...
    'Location', ...
    'best');

subplot(3,1,2);

semilogx( ...
    f, ...
    unwrap(angle(HExact))*180/pi, ...
    'LineWidth', 1.3);

hold on;

semilogx( ...
    f, ...
    unwrap(angle(HFit))*180/pi, ...
    '--', ...
    'LineWidth', 1.3);

semilogx( ...
    f, ...
    unwrap(angle(HIIRResponse))*180/pi, ...
    ':', ...
    'LineWidth', 1.5);

grid on;

ylabel('Phase (deg)');

subplot(3,1,3);

loglog( ...
    f, ...
    HIIRError, ...
    'LineWidth', 1.3);

grid on;

xlabel('Frequency (Hz)');
ylabel('IIR relative error');
