clear p result microgridInitialParameters;
clc;

projectDir = fileparts(mfilename('fullpath'));
addpath(fullfile(projectDir, 'functions'));

%% ========================================================================
% Input parameters
% ========================================================================

microgridInitialParameters = readMicrogridSymmetricLclParameters();
config = optimised_tlm_interface_config();

p.microgrid = microgridInitialParameters;

% All optimisation and filter-fitting settings are shared with
% initialise_optimised_tlm_interface through optimised_tlm_interface_config.
%% Shared optimisation settings

p.Ts = config.sampleTime;
p.communicationSteps = config.communicationSteps;

p.filter = config.filter;
p.filter.Ts = p.Ts;

p.f = config.lineRemainder.frequency;
p.frequencyWeight = config.lineRemainder.frequencyWeight;

p.nStarts = config.lineRemainder.numberOfStarts;
p.randomSeed = config.lineRemainder.randomSeed;
p.randomPerturbationStd = config.lineRemainder.randomPerturbationStd;
p.maxIterations = config.lineRemainder.maxIterations;
p.maxFunctionEvaluations = config.lineRemainder.maxFunctionEvaluations;
p.functionTolerance = config.lineRemainder.functionTolerance;
p.stepTolerance = config.lineRemainder.stepTolerance;
p.optimalityTolerance = config.lineRemainder.optimalityTolerance;
p.finiteDifferenceType = config.lineRemainder.finiteDifferenceType;
p.lineFirst = config.lineRemainder.lineFirst;
p.directDelayFirst = config.lineRemainder.directDelayFirst;

p.display = config.analysis.display;
p.makePlot = config.analysis.makePlot;

result = build_symmetric_lcl_fixed_delay_line(p);

%% ========================================================================
% Generate frequency-dependent transmission-line filters
% ========================================================================

filterResult = buildSymmetricTwoPortFrequencyDependentLineFilters( ...
    result, ...
    p.filter);

result.filter = filterResult;

save( ...
    p.filter.saveFile, ...
    'result', ...
    'filterResult', ...
    '-v7.3');

fprintf('\nFrequency-dependent line filters saved to:\n%s\n\n', ...
    p.filter.saveFile);



