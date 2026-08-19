function result = fit_fixed_delay_line_plus_remaining(p)
%FIT_FIXED_DELAY_LINE_PLUS_REMAINING
%
% Fit the original lumped two-port
%
%   series-RL -> shunt series-RC
%
% by
%
%   fixed-delay RLGC line + remaining series-RL/shunt-series-RC network.
%
% The reconstructed model is
%
%   Tnew = Tline * Trem
%
% or
%
%   Tnew = Trem * Tline
%
% depending on p.lineFirst.
%
% The transmission-line delay is fixed:
%
%   tau = communicationSteps * Ts
%
% and
%
%   sqrt(Lline*Cline) = tau.
%
% Therefore
%
%   Cline = tau^2/Lline.
%
% Independent optimisation variables:
%
%   Rline, Gline, Lline,
%   Rr, Lr, Rcr, Cr.
%
% No element-by-element parameter-conservation constraint is imposed.

%% 1. Input validation

if nargin ~= 1 || ~isstruct(p)
    error('Input must be one parameter structure p.');
end

requiredFields = { ...
    'R0', 'L0', 'Rc0', 'C0', ...
    'Ts', 'communicationSteps', 'f'};

for k = 1:numel(requiredFields)
    fieldName = requiredFields{k};
    if ~isfield(p, fieldName)
        error('Required field p.%s is missing.', fieldName);
    end
end

validateattributes(p.R0, ...
    {'numeric'}, {'scalar','real','finite','nonnegative'});

validateattributes(p.L0, ...
    {'numeric'}, {'scalar','real','finite','positive'});

validateattributes(p.Rc0, ...
    {'numeric'}, {'scalar','real','finite','nonnegative'});

validateattributes(p.C0, ...
    {'numeric'}, {'scalar','real','finite','positive'});

validateattributes(p.Ts, ...
    {'numeric'}, {'scalar','real','finite','positive'});

validateattributes(p.communicationSteps, ...
    {'numeric'}, {'scalar','real','finite','integer','positive'});

validateattributes(p.f, ...
    {'numeric'}, {'vector','real','finite','positive'});

if exist('lsqnonlin', 'file') ~= 2
    error('This function requires lsqnonlin from Optimization Toolbox.');
end

p.f = p.f(:);

%% 2. Optional settings

if ~isfield(p, 'Zbase') || isempty(p.Zbase)
    p.Zbase = sqrt(p.L0/p.C0);
end

if ~isfield(p, 'frequencyWeight') || isempty(p.frequencyWeight)
    p.frequencyWeight = ones(size(p.f));
end

if ~isfield(p, 'nStarts') || isempty(p.nStarts)
    p.nStarts = 50;
end

if ~isfield(p, 'randomSeed') || isempty(p.randomSeed)
    p.randomSeed = 43;
end

if ~isfield(p, 'display') || isempty(p.display)
    p.display = 'off';
end

if ~isfield(p, 'makePlot') || isempty(p.makePlot)
    p.makePlot = true;
end

if ~isfield(p, 'lineFirst') || isempty(p.lineFirst)
    p.lineFirst = true;
end

if ~isfield(p, 'directDelayFirst') || isempty(p.directDelayFirst)
    p.directDelayFirst = true;
end

if ~isfield(p, 'randomPerturbationStd') || isempty(p.randomPerturbationStd)
    p.randomPerturbationStd = 1.5;
end

if ~isfield(p, 'maxIterations') || isempty(p.maxIterations)
    p.maxIterations = 200;
end

if ~isfield(p, 'maxFunctionEvaluations') || isempty(p.maxFunctionEvaluations)
    p.maxFunctionEvaluations = 3e5;
end

if ~isfield(p, 'functionTolerance') || isempty(p.functionTolerance)
    p.functionTolerance = 1e-12;
end

if ~isfield(p, 'stepTolerance') || isempty(p.stepTolerance)
    p.stepTolerance = 1e-12;
end

if ~isfield(p, 'optimalityTolerance') || isempty(p.optimalityTolerance)
    p.optimalityTolerance = 1e-10;
end

if ~isfield(p, 'finiteDifferenceType') || isempty(p.finiteDifferenceType)
    p.finiteDifferenceType = 'central';
end

p.frequencyWeight = p.frequencyWeight(:);

if numel(p.frequencyWeight) ~= numel(p.f)
    error('p.frequencyWeight must have the same length as p.f.');
end

if any(p.frequencyWeight < 0) || ~any(p.frequencyWeight > 0)
    error(['Frequency weights must be nonnegative and at least one ' ...
        'weight must be positive.']);
end

validateattributes(p.Zbase, ...
    {'numeric'}, {'scalar','real','finite','positive'});

validateattributes(p.nStarts, ...
    {'numeric'}, {'scalar','integer','positive'});

%% 3. Fixed delay and frequency points

tau = p.communicationSteps*p.Ts;

s = 1j*2*pi*p.f;
nFrequency = numel(s);

%% 4. Original lumped two-port

Toriginal = complex(zeros(2,2,nFrequency));

for k = 1:nFrequency
    sk = s(k);

    Zoriginal = p.R0 + sk*p.L0;

    Yoriginal = ...
        sk*p.C0/(1 + sk*p.Rc0*p.C0);

    Toriginal(:,:,k) = ...
        seriesABCD(Zoriginal)*shuntABCD(Yoriginal);
end

%% 5. Initial parameter values

parameterFloor = 1e-12;

Znominal = sqrt(p.L0/p.C0);

% Initial line parameters satisfying the prescribed delay.
Lline0 = tau*Znominal;

% Start with relatively small line losses.
Rline0 = max(0.1*p.R0, parameterFloor);
Gline0 = max(1e-8, parameterFloor);

% Remaining network starts near the original lumped network.
Rr0  = max(p.R0,  parameterFloor);
Lr0  = max(p.L0,  parameterFloor);
Rcr0 = max(p.Rc0, parameterFloor);
Cr0  = max(p.C0,  parameterFloor);

% Independent physical parameters:
%
% [Rline, Gline, Lline, Rr, Lr, Rcr, Cr]
nominalParameters = [ ...
    Rline0; ...
    Gline0; ...
    Lline0; ...
    Rr0; ...
    Lr0; ...
    Rcr0; ...
    Cr0];

% Logarithmic variables guarantee positive parameters.
xNominal = log(nominalParameters);

%% 6. Residual function

residualFunction = @(x) calculateResidual( ...
    x, ...
    s, ...
    tau, ...
    Toriginal, ...
    p.Zbase, ...
    p.frequencyWeight, ...
    p.lineFirst);

options = optimoptions( ...
    'lsqnonlin', ...
    'Display', p.display, ...
    'MaxIterations', p.maxIterations, ...
    'MaxFunctionEvaluations', p.maxFunctionEvaluations, ...
    'FunctionTolerance', p.functionTolerance, ...
    'StepTolerance', p.stepTolerance, ...
    'OptimalityTolerance', p.optimalityTolerance, ...
    'FiniteDifferenceType', p.finiteDifferenceType);

%% 7. Multi-start optimisation

rng(p.randomSeed, 'twister');

bestResnorm  = inf;
bestX        = [];
bestResidual = [];
bestExitflag = [];
bestOutput   = [];

fprintf('\n============================================================\n');
fprintf('Fixed-delay line plus remaining lumped network\n');
fprintf('============================================================\n');
fprintf('Delay tau       = %.9e s\n', tau);
fprintf('Frequency range = %.6g to %.6g Hz\n', min(p.f), max(p.f));
fprintf('Number of starts = %d\n\n', p.nStarts);

for startIndex = 1:p.nStarts

    if startIndex == 1
        x0 = xNominal;
    else
        % Random logarithmic perturbation.
        %
        % A standard deviation of 1.5 allows exploration over several
        % orders of magnitude without making most initial points extreme.
        x0 = xNominal + p.randomPerturbationStd*randn(size(xNominal));
    end

    try
        [xCandidate, resnormCandidate, residualCandidate, ...
            exitflagCandidate, outputCandidate] = ...
            lsqnonlin( ...
                residualFunction, ...
                x0, ...
                [], ...
                [], ...
                options);

        if isfinite(resnormCandidate) && ...
                resnormCandidate < bestResnorm

            bestResnorm  = resnormCandidate;
            bestX        = xCandidate;
            bestResidual = residualCandidate;
            bestExitflag = exitflagCandidate;
            bestOutput   = outputCandidate;
        end

        fprintf( ...
            'Start %3d/%3d: resnorm = %.6e\n', ...
            startIndex, p.nStarts, resnormCandidate);

    catch ME
        warning( ...
            'Optimisation start %d failed: %s', ...
            startIndex, ME.message);
    end
end

if isempty(bestX)
    error('All optimisation starts failed.');
end

%% 8. Decode the optimum

q = exp(bestX(:));

Rline = q(1);
Gline = q(2);
Lline = q(3);

Rr  = q(4);
Lr  = q(5);
Rcr = q(6);
Cr  = q(7);

% Fixed-delay constraint.
Cline = tau^2/Lline;

Zinf = sqrt(Lline/Cline);

%% 9. Evaluate the final response

Tline       = complex(zeros(2,2,nFrequency));
Tremaining  = complex(zeros(2,2,nFrequency));
Tnew        = complex(zeros(2,2,nFrequency));
TdirectInterface = complex(zeros(2,2,nFrequency));
TdirectBaseline  = complex(zeros(2,2,nFrequency));

gammaResponse = complex(zeros(nFrequency,1));
ZcResponse    = complex(zeros(nFrequency,1));
HResponse     = complex(zeros(nFrequency,1));

relativeError       = zeros(nFrequency,1);
directRelativeError = zeros(nFrequency,1);

for k = 1:nFrequency
    sk = s(k);

    [Tline(:,:,k), gammaResponse(k), ZcResponse(k)] = ...
        lineABCD(sk, Rline, Lline, Gline, Cline);

    HResponse(k) = exp(-gammaResponse(k));

    Zremaining = Rr + sk*Lr;

    Yremaining = ...
        sk*Cr/(1 + sk*Rcr*Cr);

    Tremaining(:,:,k) = ...
        seriesABCD(Zremaining)*shuntABCD(Yremaining);

    if p.lineFirst
        Tnew(:,:,k) = ...
            Tline(:,:,k)*Tremaining(:,:,k);
    else
        Tnew(:,:,k) = ...
            Tremaining(:,:,k)*Tline(:,:,k);
    end

    % Conventional direct delayed V-I exchange:
    %
    %   V2(s) = exp(-s*tau) V1(s)
    %   I1(s) = exp(-s*tau) I2(s)
    %
    % Its apparent ABCD matrix is
    %
    %   Tdirect = diag(exp(+s*tau), exp(-s*tau)).
    %
    % The comparison baseline requested here is NOT the delay interface
    % alone. The original RL-RC network is retained unchanged and cascaded
    % with the direct delayed interface.
    delayFactor = exp(-sk*tau);

    TdirectInterface(:,:,k) = [ ...
        1/delayFactor, 0; ...
        0,             delayFactor];

    if p.directDelayFirst
        TdirectBaseline(:,:,k) = ...
            TdirectInterface(:,:,k)*Toriginal(:,:,k);
    else
        TdirectBaseline(:,:,k) = ...
            Toriginal(:,:,k)*TdirectInterface(:,:,k);
    end

    T0n = normaliseABCD( ...
        Toriginal(:,:,k), p.Zbase);

    Tnn = normaliseABCD( ...
        Tnew(:,:,k), p.Zbase);

    Tdn = normaliseABCD( ...
        TdirectBaseline(:,:,k), p.Zbase);

    relativeError(k) = ...
        norm(T0n - Tnn, 'fro') / ...
        max(norm(T0n, 'fro'), eps);

    directRelativeError(k) = ...
        norm(T0n - Tdn, 'fro') / ...
        max(norm(T0n, 'fro'), eps);
end

%% 10. Output structure

result = struct();

result.tau = tau;
result.Zinf = Zinf;

result.Rline = Rline;
result.Lline = Lline;
result.Gline = Gline;
result.Cline = Cline;

result.Rr  = Rr;
result.Lr  = Lr;
result.Rcr = Rcr;
result.Cr  = Cr;

result.frequency = p.f;
result.s = s;

result.Toriginal   = Toriginal;
result.Tline       = Tline;
result.Tremaining  = Tremaining;
result.Tnew        = Tnew;
result.TdirectInterface = TdirectInterface;
result.TdirectBaseline  = TdirectBaseline;
result.directDelayFirst = p.directDelayFirst;

result.gamma = gammaResponse;
result.Zc    = ZcResponse;
result.H     = HResponse;

result.relativeError = relativeError;
result.meanError = mean(relativeError);
result.rmsError  = sqrt(mean(relativeError.^2));
result.maxError  = max(relativeError);

result.directRelativeError = directRelativeError;
result.directMeanError = mean(directRelativeError);
result.directRmsError  = sqrt(mean(directRelativeError.^2));
result.directMaxError  = max(directRelativeError);

result.resnorm  = bestResnorm;
result.residual = bestResidual;
result.exitflag = bestExitflag;
result.output   = bestOutput;

result.Zbase    = p.Zbase;
result.lineFirst = p.lineFirst;

result.originalParameters = struct( ...
    'R0',  p.R0, ...
    'L0',  p.L0, ...
    'Rc0', p.Rc0, ...
    'C0',  p.C0);

result.stability = assessOptimisedResultStability(result);

%% 11. Print result

fprintf('\n============================================================\n');
fprintf('Optimised reconstructed model\n');
fprintf('============================================================\n');

fprintf('Fixed propagation delay\n');
fprintf('  tau                 = %.9e s\n', tau);
fprintf('\n');

fprintf('Transmission-line parameters\n');
fprintf('  Rline               = %.9e ohm\n', Rline);
fprintf('  Lline               = %.9e H\n',   Lline);
fprintf('  Gline               = %.9e S\n',   Gline);
fprintf('  Cline               = %.9e F\n',   Cline);
fprintf('  sqrt(Lline*Cline)   = %.9e s\n',   sqrt(Lline*Cline));
fprintf('  Zinf                = %.9e ohm\n', Zinf);
fprintf('\n');

fprintf('Remaining lumped parameters\n');
fprintf('  Rr                  = %.9e ohm\n', Rr);
fprintf('  Lr                  = %.9e H\n',   Lr);
fprintf('  Rcr                 = %.9e ohm\n', Rcr);
fprintf('  Cr                  = %.9e F\n',   Cr);
fprintf('\n');

fprintf('Comparison with original parameter sums\n');
fprintf('  Lline + Lr         = %.9e H\n', Lline + Lr);
fprintf('  Original L0        = %.9e H\n', p.L0);
fprintf('  Cline + Cr         = %.9e F\n', Cline + Cr);
fprintf('  Original C0        = %.9e F\n', p.C0);
fprintf('\n');

fprintf('Stability checks\n');
fprintf('  Physical parameters positive: %s\n', ...
    passFailText(result.stability.physicalParametersPositive));
fprintf('  Remaining RC pole stable:    %s\n', ...
    passFailText(result.stability.remainingPoleStable));
fprintf('  min real(gamma):             %.9e\n', ...
    result.stability.minRealGamma);
fprintf('  max |H|:                     %.9e\n', ...
    result.stability.maxAbsH);
fprintf('  Overall:                     %s\n', ...
    passFailText(result.stability.isStable));
fprintf('\n');

if ~result.stability.isStable
    warning('The optimised reconstructed model failed the stability checks.');
end

fprintf('Fit quality\n');
fprintf('  residual norm       = %.9e\n', bestResnorm);
fprintf('  mean relative error = %.9e\n', result.meanError);
fprintf('  RMS relative error  = %.9e\n', result.rmsError);
fprintf('  max relative error  = %.9e\n', result.maxError);
fprintf('\n');

fprintf('Original RL-RC + direct delayed V-I interface error\n');
fprintf('  mean relative error = %.9e\n', result.directMeanError);
fprintf('  RMS relative error  = %.9e\n', result.directRmsError);
fprintf('  max relative error  = %.9e\n', result.directMaxError);

fprintf('============================================================\n\n');

%% 12. Plot

if p.makePlot
    plotResult(result);
end

end


