function p = readMicrogridHeavisideParameters()
%READMICROGRIDHEAVISIDEPARAMETERS Build the lumped RL-RC values from Microgrid.

requiredBaseVariables = { ...
    'Vline', ...
    'Vhv', ...
    'Sxfmr', ...
    'f', ...
    'Rf', ...
    'Lf2', ...
    'Rdamp', ...
    'Cf'};

if ~baseHasVariables(requiredBaseVariables)
    fprintf(['Microgrid initialization variables were not found. ', ...
        'Running initialize_unitlm_microgrid once...\n']);
    initializeOutput = evalc('initialize_unitlm_microgrid();'); %#ok<NASGU>
end

baseParameters = readBaseVariables(requiredBaseVariables);
transformer = readMicrogridTransformerParameters();

secondaryVoltage = baseParameters.Vline;
omegaBase = 2*pi*transformer.frequency;

windingRReferred = zeros(size(transformer.windings, 1), 1);
windingLReferred = zeros(size(transformer.windings, 1), 1);

for k = 1:size(transformer.windings, 1)
    windingVoltage = transformer.windings(k, 1);
    windingResistancePu = transformer.windings(k, 2);
    windingReactancePu = transformer.windings(k, 3);

    windingZbase = windingVoltage^2/transformer.nominalPower;
    sideScale = (secondaryVoltage/windingVoltage)^2;

    windingRReferred(k) = windingResistancePu*windingZbase*sideScale;
    windingLReferred(k) = ...
        windingReactancePu*windingZbase/omegaBase*sideScale;
end

transformerR = sum(windingRReferred);
transformerL = sum(windingLReferred);

p.R0  = transformerR + baseParameters.Rf;
p.L0  = transformerL + baseParameters.Lf2;
p.Rc0 = baseParameters.Rdamp;
p.C0  = baseParameters.Cf;

fprintf('\nHeaviside equivalent parameters from Microgrid initialization\n');
fprintf('------------------------------------------------------------\n');
fprintf('Transformer winding R referred to %.6g V side:\n', ...
    secondaryVoltage);
fprintf('  Winding 1:                             %.9e ohm\n', ...
    windingRReferred(1));
fprintf('  Winding 2:                             %.9e ohm\n', ...
    windingRReferred(2));
fprintf('  Sum:                                   %.9e ohm\n', ...
    transformerR);
fprintf('Transformer winding L referred to %.6g V side:\n', ...
    secondaryVoltage);
fprintf('  Winding 1:                             %.9e H\n', ...
    windingLReferred(1));
fprintf('  Winding 2:                             %.9e H\n', ...
    windingLReferred(2));
fprintf('  Sum:                                   %.9e H\n', ...
    transformerL);
fprintf('LCL grid-side R:                         %.9e ohm\n', ...
    baseParameters.Rf);
fprintf('LCL grid-side L:                         %.9e H\n', ...
    baseParameters.Lf2);
fprintf('p.R0:                                    %.9e ohm\n', p.R0);
fprintf('p.L0:                                    %.9e H\n', p.L0);
fprintf('p.Rc0:                                   %.9e ohm\n', p.Rc0);
fprintf('p.C0:                                    %.9e F\n\n', p.C0);
end


