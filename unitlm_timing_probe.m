function result = unitlm_timing_probe(action, role, varargin)
%UNITLM_TIMING_PROBE Lightweight timing probe for two-PC uniTLM runs.
%
% The S-functions call this probe only when a model StartFcn has enabled it.
% StopFcn prints and saves a compact summary in result/unitlm_timing_*.mat/csv.

persistent store;

if nargin < 1 || isempty(action)
    action = 'report';
end

if nargin < 2 || isempty(role)
    role = 'unknown';
end

action = lower(char(action));
role = lower(char(role));
key = matlab.lang.makeValidName(role);
result = [];

switch action
    case 'start'
        modelName = getOptionalText(varargin, 1, '');
        stats = newStats(role, modelName);
        store.(key) = stats;
        fprintf('[uniTLM timing] %s probe started.\n', role);

    case 'enabled'
        result = isfieldOrFalse(store, key);

    case 'stepbegin'
        if ~isfieldOrFalse(store, key)
            return;
        end

        stats = store.(key);
        simTime = getOptionalDouble(varargin, 1, NaN);
        wallNow = toc(stats.wallTimer);

        if ~isnan(stats.lastStepWall)
            stats = addMetric(stats, 'stepWall', ...
                wallNow - stats.lastStepWall, simTime);
        end

        stats.lastStepWall = wallNow;
        stats.stepCount = stats.stepCount + 1;
        stats = updateSimTime(stats, simTime);
        store.(key) = stats;

    case 'updateend'
        if ~isfieldOrFalse(store, key)
            return;
        end

        stats = store.(key);
        simTime = getOptionalDouble(varargin, 1, NaN);
        elapsed = getOptionalDouble(varargin, 2, NaN);
        stats = addMetric(stats, 'update', elapsed, simTime);
        stats.updateCount = stats.updateCount + 1;
        stats = updateSimTime(stats, simTime);
        store.(key) = stats;

    case 'exchange'
        if ~isfieldOrFalse(store, key)
            return;
        end

        stats = store.(key);
        simTime = getOptionalDouble(varargin, 1, NaN);
        count = getOptionalDouble(varargin, 2, NaN);
        stats.exchangeCount = stats.exchangeCount + 1;
        stats.lastExchangeCount = count;
        stats = updateSimTime(stats, simTime);
        store.(key) = stats;

    case {'read', 'write', 'connect'}
        if ~isfieldOrFalse(store, key)
            return;
        end

        stats = store.(key);
        simTime = getOptionalDouble(varargin, 1, NaN);
        elapsed = getOptionalDouble(varargin, 2, NaN);
        count = getOptionalDouble(varargin, 3, NaN);
        ok = getOptionalLogical(varargin, 4, true);

        stats = addMetric(stats, action, elapsed, simTime);
        stats.lastExchangeCount = count;

        if strcmp(action, 'read') && ~ok
            stats.readFailureCount = stats.readFailureCount + 1;
        end

        stats = updateSimTime(stats, simTime);
        store.(key) = stats;

    case 'stop'
        if ~isfieldOrFalse(store, key)
            fprintf('[uniTLM timing] %s probe was not active.\n', role);
            return;
        end

        modelName = getOptionalText(varargin, 1, store.(key).modelName);
        stats = store.(key);
        if ~isempty(modelName)
            stats.modelName = modelName;
        end

        summary = makeSummary(stats);
        printSummary(summary);
        saveSummary(summary);

        assignin('base', sprintf('unitlm_%s_timing', role), summary);
        result = summary;
        store = rmfield(store, key);

    case 'reset'
        if isfieldOrFalse(store, key)
            store = rmfield(store, key);
        end

    otherwise
        error('unitlm_timing_probe:InvalidAction', ...
            'Unknown timing-probe action: %s.', action);
end
end

function stats = newStats(role, modelName)
stats = struct();
stats.role = role;
stats.modelName = modelName;
stats.startedAt = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
stats.wallTimer = tic;
stats.lastStepWall = NaN;
stats.stepCount = 0;
stats.updateCount = 0;
stats.exchangeCount = 0;
stats.readFailureCount = 0;
stats.lastExchangeCount = NaN;
stats.firstSimTime = NaN;
stats.lastSimTime = NaN;

stats.params = struct();
try
    if evalin('base', 'exist(''params'', ''var'')') == 1
        stats.params = evalin('base', 'params');
    end
catch
end

metricNames = {'stepWall', 'update', 'read', 'write', 'connect'};
for k = 1:numel(metricNames)
    stats.metrics.(metricNames{k}) = emptyMetric();
end
end

function metric = emptyMetric()
metric = struct();
metric.count = 0;
metric.sum = 0;
metric.min = Inf;
metric.max = 0;
metric.maxAtSimTime = NaN;
end

function tf = isfieldOrFalse(store, key)
tf = ~isempty(store) && isfield(store, key);
end

function stats = updateSimTime(stats, simTime)
if ~isfinite(simTime)
    return;
end

if isnan(stats.firstSimTime)
    stats.firstSimTime = simTime;
end

stats.lastSimTime = simTime;
end

function stats = addMetric(stats, name, value, simTime)
if ~isfinite(value) || value < 0
    return;
end

metric = stats.metrics.(name);
metric.count = metric.count + 1;
metric.sum = metric.sum + value;
metric.min = min(metric.min, value);

if value >= metric.max
    metric.max = value;
    metric.maxAtSimTime = simTime;
end

stats.metrics.(name) = metric;
end

function summary = makeSummary(stats)
totalWall = toc(stats.wallTimer);
simDuration = stats.lastSimTime - stats.firstSimTime;
if ~isfinite(simDuration) || simDuration < 0
    simDuration = NaN;
end

summary = struct();
summary.role = stats.role;
summary.modelName = stats.modelName;
summary.startedAt = stats.startedAt;
summary.finishedAt = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
summary.params = stats.params;

summary.totalWall_s = totalWall;
summary.simDuration_s = simDuration;
summary.realTimeFactor = safeDivide(simDuration, totalWall);

summary.stepCount = stats.stepCount;
summary.updateCount = stats.updateCount;
summary.exchangeCount = stats.exchangeCount;
summary.readFailureCount = stats.readFailureCount;

summary.avgStepWall_s = metricAverage(stats.metrics.stepWall);
summary.maxStepWall_s = stats.metrics.stepWall.max;
summary.maxStepWallAtSimTime_s = stats.metrics.stepWall.maxAtSimTime;

summary.totalSFunctionUpdate_s = stats.metrics.update.sum;
summary.avgSFunctionUpdate_s = metricAverage(stats.metrics.update);
summary.maxSFunctionUpdate_s = stats.metrics.update.max;
summary.maxSFunctionUpdateAtSimTime_s = stats.metrics.update.maxAtSimTime;

summary.totalTcpReadWait_s = stats.metrics.read.sum;
summary.avgTcpReadWait_s = metricAverage(stats.metrics.read);
summary.maxTcpReadWait_s = stats.metrics.read.max;
summary.maxTcpReadWaitAtSimTime_s = stats.metrics.read.maxAtSimTime;

summary.totalTcpWrite_s = stats.metrics.write.sum;
summary.avgTcpWrite_s = metricAverage(stats.metrics.write);
summary.maxTcpWrite_s = stats.metrics.write.max;
summary.maxTcpWriteAtSimTime_s = stats.metrics.write.maxAtSimTime;

summary.totalConnectCheck_s = stats.metrics.connect.sum;
summary.maxConnectCheck_s = stats.metrics.connect.max;
summary.maxConnectCheckAtSimTime_s = stats.metrics.connect.maxAtSimTime;

summary.tcpReadFractionOfWall = safeDivide( ...
    summary.totalTcpReadWait_s, totalWall);
summary.tcpReadFractionOfSFunctionUpdate = safeDivide( ...
    summary.totalTcpReadWait_s, summary.totalSFunctionUpdate_s);
summary.sFunctionUpdateFractionOfWall = safeDivide( ...
    summary.totalSFunctionUpdate_s, totalWall);
end

function value = metricAverage(metric)
value = safeDivide(metric.sum, metric.count);
end

function value = safeDivide(a, b)
if ~isfinite(a) || ~isfinite(b) || b == 0
    value = NaN;
else
    value = a/b;
end
end

function printSummary(summary)
fprintf('\nuniTLM timing summary [%s]\n', summary.role);
fprintf('----------------------------------------\n');
fprintf('Model:                    %s\n', summary.modelName);
fprintf('Steps seen by S-function:  %d\n', summary.stepCount);
fprintf('TCP exchanges:             %d\n', summary.exchangeCount);
fprintf('Total wall time:           %.6f s\n', summary.totalWall_s);
fprintf('Simulated duration:        %.6f s\n', summary.simDuration_s);
fprintf('Real-time factor:          %.6g\n', summary.realTimeFactor);
fprintf('Avg wall per step:         %.6g s\n', summary.avgStepWall_s);
fprintf('Max wall per step:         %.6g s at t=%.9g s\n', ...
    summary.maxStepWall_s, summary.maxStepWallAtSimTime_s);
fprintf('Total S-function update:   %.6f s (%.2f%% wall)\n', ...
    summary.totalSFunctionUpdate_s, ...
    100*summary.sFunctionUpdateFractionOfWall);
fprintf('Total TCP read wait:       %.6f s (%.2f%% wall, %.2f%% S-fcn)\n', ...
    summary.totalTcpReadWait_s, ...
    100*summary.tcpReadFractionOfWall, ...
    100*summary.tcpReadFractionOfSFunctionUpdate);
fprintf('Avg TCP read wait:         %.6g s\n', summary.avgTcpReadWait_s);
fprintf('Max TCP read wait:         %.6g s at t=%.9g s\n', ...
    summary.maxTcpReadWait_s, summary.maxTcpReadWaitAtSimTime_s);
fprintf('Total TCP write:           %.6f s\n', summary.totalTcpWrite_s);
fprintf('Max TCP write:             %.6g s at t=%.9g s\n', ...
    summary.maxTcpWrite_s, summary.maxTcpWriteAtSimTime_s);
fprintf('Read failures/timeouts:    %d\n\n', summary.readFailureCount);
end

function saveSummary(summary)
try
    modelDir = pwd;
    if ~isempty(summary.modelName) && bdIsLoaded(summary.modelName)
        modelFile = get_param(summary.modelName, 'FileName');
        if ~isempty(modelFile)
            modelDir = fileparts(modelFile);
        end
    end

    resultDir = fullfile(modelDir, 'result');
    if ~exist(resultDir, 'dir')
        mkdir(resultDir);
    end

    timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
    baseName = sprintf('unitlm_timing_%s_%s', summary.role, timestamp);
    matPath = fullfile(resultDir, [baseName, '.mat']);
    csvPath = fullfile(resultDir, [baseName, '.csv']);

    timingSummary = summary; %#ok<NASGU>
    save(matPath, 'timingSummary');

    tableData = struct2table(flattenSummary(summary));
    writetable(tableData, csvPath);

    fprintf('[uniTLM timing] saved MAT: %s\n', matPath);
    fprintf('[uniTLM timing] saved CSV: %s\n', csvPath);
catch ME
    warning('unitlm_timing_probe:SaveFailed', ...
        'Could not save timing summary: %s', ME.message);
end
end

function flat = flattenSummary(summary)
flat = rmfield(summary, 'params');

flatNames = fieldnames(flat);
for k = 1:numel(flatNames)
    name = flatNames{k};
    if ischar(flat.(name))
        flat.(name) = {flat.(name)};
    end
end

if isfield(summary, 'params')
    names = fieldnames(summary.params);
    for k = 1:numel(names)
        name = names{k};
        value = summary.params.(name);
        if isnumeric(value) && isscalar(value)
            flat.(['params_', name]) = value;
        elseif ischar(value)
            flat.(['params_', name]) = {value};
        end
    end
end
end

function text = getOptionalText(values, index, defaultValue)
text = defaultValue;
if numel(values) >= index && ~isempty(values{index})
    text = char(values{index});
end
end

function value = getOptionalDouble(values, index, defaultValue)
value = defaultValue;
if numel(values) >= index && ~isempty(values{index})
    value = double(values{index});
end
end

function value = getOptionalLogical(values, index, defaultValue)
value = defaultValue;
if numel(values) >= index && ~isempty(values{index})
    value = logical(values{index});
end
end
