function p = readMicrogridSymmetricLclParameters()
%READMICROGRIDSYMMETRICLCLPARAMETERS Read the Microgrid LCL/transformer data.
%
% The optimised LCTLM interface is built from this asymmetric lumped path:
%
%   series RL (inverter side) - shunt RC - series RL (grid/transformer side)
%
% The transformer low-voltage winding is used with the LCL output branch.
% The high-voltage winding is kept as a separate physical branch in the
% LCTLM server model.

requiredBaseVariables = { ...
    'Vline', ...
    'Vhv', ...
    'Sxfmr', ...
    'f', ...
    'Rf', ...
    'Lc', ...
    'Lf2', ...
    'Rdamp', ...
    'Cf'};

if ~baseHasVariables(requiredBaseVariables)
    fprintf(['Microgrid initialization variables were not found. ', ...
        'Running initialize_unitlm_microgrid once...\n']);
    initializeOutput = evalc('initialize_unitlm_microgrid(''skipLineFit'');'); %#ok<NASGU>
end

baseParameters = readBaseVariables(requiredBaseVariables);
transformer = readMicrogridTransformerParameters();

referenceVoltage = baseParameters.Vline;
omegaBase = 2*pi*transformer.frequency;

windingRReferred = zeros(size(transformer.windings, 1), 1);
windingLReferred = zeros(size(transformer.windings, 1), 1);
windingZbase = zeros(size(transformer.windings, 1), 1);

for k = 1:size(transformer.windings, 1)
    windingVoltage = transformer.windings(k, 1);
    windingResistancePu = transformer.windings(k, 2);
    windingReactancePu = transformer.windings(k, 3);

    windingZbase(k) = windingVoltage^2/transformer.nominalPower;
    sideScale = (referenceVoltage/windingVoltage)^2;

    windingRReferred(k) = ...
        windingResistancePu*windingZbase(k)*sideScale;
    windingLReferred(k) = ...
        windingReactancePu*windingZbase(k)/omegaBase*sideScale;
end

lowVoltageWindingIndex = 2;

p = struct();
p.base = baseParameters;
p.transformer = transformer;
p.referenceVoltage = referenceVoltage;
p.lowVoltageWindingIndex = lowVoltageWindingIndex;
p.windingRReferred = windingRReferred;
p.windingLReferred = windingLReferred;
p.windingZbase = windingZbase;

p.inverterSide = struct( ...
    'R', baseParameters.Rf, ...
    'L', baseParameters.Lc);

p.networkSide = struct( ...
    'R', baseParameters.Rf + windingRReferred(lowVoltageWindingIndex), ...
    'L', baseParameters.Lf2 + windingLReferred(lowVoltageWindingIndex));

p.shunt = struct( ...
    'Rc', baseParameters.Rdamp, ...
    'C', baseParameters.Cf);

fprintf('\nSymmetric LCL equivalent source parameters from Microgrid\n');
fprintf('------------------------------------------------------------\n');
fprintf('Reference voltage:                       %.9e V line-line RMS\n', ...
    referenceVoltage);
fprintf('Transformer winding R referred to %.6g V side:\n', ...
    referenceVoltage);
for k = 1:numel(windingRReferred)
    fprintf('  Winding %d:                             %.9e ohm\n', ...
        k, windingRReferred(k));
end
fprintf('Transformer winding L referred to %.6g V side:\n', ...
    referenceVoltage);
for k = 1:numel(windingLReferred)
    fprintf('  Winding %d:                             %.9e H\n', ...
        k, windingLReferred(k));
end
fprintf('Using winding %d as transformer low-voltage series branch.\n', ...
    lowVoltageWindingIndex);
fprintf('Inverter-side series R:                  %.9e ohm\n', ...
    p.inverterSide.R);
fprintf('Inverter-side series L:                  %.9e H\n', ...
    p.inverterSide.L);
fprintf('Network-side series R:                   %.9e ohm\n', ...
    p.networkSide.R);
fprintf('Network-side series L:                   %.9e H\n', ...
    p.networkSide.L);
fprintf('Shunt damping R:                         %.9e ohm\n', ...
    p.shunt.Rc);
fprintf('Shunt capacitor C:                       %.9e F\n\n', ...
    p.shunt.C);
end
