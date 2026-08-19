function result = build_symmetric_lcl_fixed_delay_line(p)
%BUILD_SYMMETRIC_LCL_FIXED_DELAY_LINE Build a generalized line from LCL data.
%
% The physical source network is:
%
%   inverter-side RL - shunt RC - network-side RL
%
% A passive common RL part is placed on both sides of a symmetric reciprocal
% two-port. The remaining positive RL terms are recorded as separated
% terminal branches.

microgrid = p.microgrid;
frequency = p.f(:);
fixedDelay = p.Ts*p.communicationSteps;

[commonSeries, separatedSeries, splitDecision] = ...
    splitPassiveSymmetricSeriesBranches( ...
        microgrid.inverterSide, ...
        microgrid.networkSide, ...
        microgrid.base.f);

response = symmetricLclTwoPortResponse( ...
    frequency, ...
    commonSeries, ...
    microgrid.shunt, ...
    fixedDelay);

filterFrequency = logspace( ...
    log10(p.filter.fMin), ...
    log10(p.filter.fMax), ...
    p.filter.nFrequency).';

filterBandResponse = symmetricLclTwoPortResponse( ...
    filterFrequency, ...
    commonSeries, ...
    microgrid.shunt, ...
    fixedDelay);

Zinf = selectCharacteristicImpedance( ...
    filterBandResponse.Zc, ...
    filterBandResponse.frequency);

originalResponse = asymmetricLclResponse( ...
    frequency, ...
    microgrid.inverterSide, ...
    microgrid.networkSide, ...
    microgrid.shunt);

reconstructedResponse = separatedSymmetricResponse( ...
    frequency, ...
    commonSeries, ...
    separatedSeries, ...
    microgrid.shunt);

reconstructionError = zeros(numel(frequency), 1);

for k = 1:numel(frequency)
    denominator = max(1, norm(originalResponse.T(:, :, k), 'fro'));
    reconstructionError(k) = ...
        norm( ...
            reconstructedResponse.T(:, :, k) - ...
            originalResponse.T(:, :, k), ...
            'fro')/denominator;
end

result = struct();
result.method = 'symmetric-lcl-fixed-delay-generalised-line';
result.microgrid = microgrid;
result.inverterSide = microgrid.inverterSide;
result.networkSide = microgrid.networkSide;
result.shunt = microgrid.shunt;
result.commonSeries = commonSeries;
result.separatedSeries = separatedSeries;
result.splitDecision = splitDecision;

result.Rline = commonSeries.R;
result.Lline = commonSeries.L;
result.Gline = 0;
result.Cline = microgrid.shunt.C;

result.Rr = separatedSeries.terminal1.R + separatedSeries.terminal2.R;
result.Lr = separatedSeries.terminal1.L + separatedSeries.terminal2.L;
result.R_remain_client = separatedSeries.terminal1.R;
result.L_remain_client = separatedSeries.terminal1.L;
result.R_remain_server = separatedSeries.terminal2.R;
result.L_remain_server = separatedSeries.terminal2.L;

% The shunt RC is now inside the generalized line. Keep a numerically mild
% near-open remaining RC branch for compatibility with the current LCTLM
% models, whose Simscape topology still contains this block.
result.Rcr = 1e6;
result.Cr = 1e-9;

result.tau = fixedDelay;
result.Ts = p.Ts;
result.communicationSteps = p.communicationSteps;
result.Zinf = Zinf;

result.frequency = frequency;
result.omega = response.omega;
result.gamma = response.gamma;
result.Zc = response.Zc;
result.H = response.H;
result.Hr = response.Hr;
result.Ttarget = response.T;
result.Toriginal = originalResponse.T;
result.Treconstructed = reconstructedResponse.T;
result.reciprocalError = response.reciprocalError;
result.symmetryError = response.symmetryError;
result.reconstructionError = reconstructionError;
result.stability = assessSymmetricLclResultStability(result);

printSymmetricLclSummary(result);

if p.makePlot
    plotSymmetricLclEquivalentResult(result);
end
end


function response = asymmetricLclResponse( ...
    frequency, terminal1, terminal2, shuntBranch)

frequency = frequency(:);
s = 1j*2*pi*frequency;

Zterminal1 = terminal1.R + s*terminal1.L;
Zterminal2 = terminal2.R + s*terminal2.L;
Yshunt = s*shuntBranch.C ./ ...
    (1 + s*shuntBranch.Rc*shuntBranch.C);

T = zeros(2, 2, numel(frequency));

for k = 1:numel(frequency)
    T(:, :, k) = ...
        seriesABCD(Zterminal1(k)) * ...
        shuntABCD(Yshunt(k)) * ...
        seriesABCD(Zterminal2(k));
end

response = struct('T', T);
end


function response = separatedSymmetricResponse( ...
    frequency, commonSeries, separatedSeries, shuntBranch)

frequency = frequency(:);
s = 1j*2*pi*frequency;

Zcommon = commonSeries.R + s*commonSeries.L;
Zterminal1 = separatedSeries.terminal1.R + ...
    s*separatedSeries.terminal1.L;
Zterminal2 = separatedSeries.terminal2.R + ...
    s*separatedSeries.terminal2.L;
Yshunt = s*shuntBranch.C ./ ...
    (1 + s*shuntBranch.Rc*shuntBranch.C);

T = zeros(2, 2, numel(frequency));

for k = 1:numel(frequency)
    T(:, :, k) = ...
        seriesABCD(Zterminal1(k)) * ...
        seriesABCD(Zcommon(k)) * ...
        shuntABCD(Yshunt(k)) * ...
        seriesABCD(Zcommon(k)) * ...
        seriesABCD(Zterminal2(k));
end

response = struct('T', T);
end


function stability = assessSymmetricLclResultStability(result)

tolerance = 1e-9;

physicalParametersPositive = ...
    result.commonSeries.R >= 0 && ...
    result.commonSeries.L > 0 && ...
    result.shunt.Rc >= 0 && ...
    result.shunt.C > 0 && ...
    result.separatedSeries.terminal1.R >= 0 && ...
    result.separatedSeries.terminal1.L >= 0 && ...
    result.separatedSeries.terminal2.R >= 0 && ...
    result.separatedSeries.terminal2.L >= 0 && ...
    result.Rcr > 0 && ...
    result.Cr > 0;

linePropagationPassive = ...
    min(real(result.gamma)) >= -tolerance && ...
    max(abs(result.H)) <= 1 + tolerance && ...
    max(abs(result.Hr)) <= 1 + tolerance;

twoPortWellDefined = ...
    max(result.reciprocalError) < 1e-7 && ...
    max(result.symmetryError) < 1e-7 && ...
    max(result.reconstructionError) < 1e-7;

stability = struct();
stability.physicalParametersPositive = physicalParametersPositive;
stability.minRealGamma = min(real(result.gamma));
stability.maxAbsH = max(abs(result.H));
stability.maxAbsHr = max(abs(result.Hr));
stability.maxReciprocalError = max(result.reciprocalError);
stability.maxSymmetryError = max(result.symmetryError);
stability.maxReconstructionError = max(result.reconstructionError);
stability.linePropagationPassive = linePropagationPassive;
stability.twoPortWellDefined = twoPortWellDefined;
stability.isStable = ...
    physicalParametersPositive && ...
    linePropagationPassive && ...
    twoPortWellDefined;
end


function printSymmetricLclSummary(result)

fprintf('\n============================================================\n');
fprintf('Symmetric LCL fixed-delay generalized line\n');
fprintf('============================================================\n');
fprintf('Split mode:                %s\n', ...
    result.splitDecision.splitMode);
fprintf('Common series R:           %.12e ohm\n', ...
    result.commonSeries.R);
fprintf('Common series L:           %.12e H\n', ...
    result.commonSeries.L);
fprintf('Separated terminal 1 R:    %.12e ohm\n', ...
    result.separatedSeries.terminal1.R);
fprintf('Separated terminal 1 L:    %.12e H\n', ...
    result.separatedSeries.terminal1.L);
fprintf('Separated terminal 2 R:    %.12e ohm\n', ...
    result.separatedSeries.terminal2.R);
fprintf('Separated terminal 2 L:    %.12e H\n', ...
    result.separatedSeries.terminal2.L);
fprintf('Shunt R:                   %.12e ohm\n', ...
    result.shunt.Rc);
fprintf('Shunt C:                   %.12e F\n', ...
    result.shunt.C);
fprintf('Fixed delay tau:           %.12e s\n', result.tau);
fprintf('Selected Zinf:             %.12e ohm\n', result.Zinf);
fprintf('Max reciprocal error:      %.12e\n', ...
    result.stability.maxReciprocalError);
fprintf('Max symmetry error:        %.12e\n', ...
    result.stability.maxSymmetryError);
fprintf('Max reconstruction error:  %.12e\n', ...
    result.stability.maxReconstructionError);
fprintf('Line stability:            %s\n', ...
    passFailText(result.stability.isStable));
fprintf('============================================================\n\n');
end


function plotSymmetricLclEquivalentResult(result)

figure('Name', 'Symmetric LCL equivalent two-port');

subplot(2, 1, 1);
semilogx( ...
    result.frequency, ...
    abs(result.Zc), ...
    'LineWidth', 1.3);
grid on;
xlabel('Frequency (Hz)');
ylabel('|Z_c| (ohm)');
title('Extracted characteristic impedance');

subplot(2, 1, 2);
semilogx( ...
    result.frequency, ...
    unwrap(angle(result.Hr))*180/pi, ...
    'LineWidth', 1.3);
grid on;
xlabel('Frequency (Hz)');
ylabel('Phase (deg)');
title('Residual propagation H_r after fixed delay extraction');
end
