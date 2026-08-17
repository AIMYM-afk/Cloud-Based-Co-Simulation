function [sys, x0, str, ts] = Client_co_TLM(t, x, u, flag)
%CLIENT_CO_TLM_BATCH Batched TCP client S-function for a TLM interface.
%
% Each Simulink sample:
%   1) Collect one local n-value vector.
%   2) Output one vector from the previously received batch.
%
% Every batchSteps samples:
%   1) Send n*batchSteps doubles in one TCP write.
%   2) Receive n*batchSteps doubles in one TCP read.
%   3) Use the received batch during the next batchSteps samples.
%
% Data ordering in each TCP packet:
%   [sample_1(:); sample_2(:); ...; sample_batchSteps(:)]
%
% IMPORTANT:
%   The client must use the same n, batchSteps, sampleTime, ports, and
%   packet ordering.

switch flag
    case 0
        [sys, x0, str, ts] = mdlInitializeSizes();

    case 2
        sys = mdlUpdate(t, x, u);

    case 3
        sys = mdlOutputs();

    case 9
        sys = mdlTerminate();

    case {1, 4}
        sys = [];

    otherwise
        error('Client_co_TLM_Batch:UnhandledFlag', ...
            'Unhandled flag = %d.', flag);
end
end


%% ========================================================================
function [sys, x0, str, ts] = mdlInitializeSizes()
params = loadClientTlmParameters(true);

sizes = simsizes;
sizes.NumContStates  = 0;
sizes.NumDiscStates  = 1;
sizes.NumOutputs     = params.n;
sizes.NumInputs      = params.n;
% The output is the previously received remote sample. The current input is
% consumed in mdlUpdate, so the block must not advertise direct feedthrough.
sizes.DirFeedthrough = 0;
sizes.NumSampleTimes = 1;

sys = simsizes(sizes);
x0  = 0;
str = [];

% The block still executes every base communication/sample step.
% Batching only changes how often TCP communication occurs.
ts = [params.sampleTime, 0];

batchState('reset', params);
clientConnectionState('reset');
end


%% ========================================================================
function sys = mdlOutputs()
params = loadClientTlmParameters();

n = params.n;
state = batchState('get', params);

% Output the corresponding sample from the previously received batch.
% During the first batch, receiveBuffer contains the configured initial value.
sys = sanitizeOutput(state.receiveBuffer(:, state.index), n);
end


%% ========================================================================
function sys = mdlUpdate(t, x, u)
params = loadClientTlmParameters();
timingEnabled = unitlm_timing_probe('enabled', 'client');

if timingEnabled
    unitlm_timing_probe('stepBegin', 'client', t);
    updateTimer = tic;
end

n = params.n;
N = params.batchSteps;

payload = validatePayload(u, n, 'Client_co_TLM input');
state = batchState('get', params);

% Store the current local sample in the outgoing batch.
state.sendBuffer(:, state.index) = payload;

if state.index < N
    % Continue collecting the current batch.
    state.index = state.index + 1;
else
    % The current batch is complete: exchange all N samples at once.
    expectedCount = n * N;

    if timingEnabled
        unitlm_timing_probe('exchange', 'client', t, expectedCount);
        connectTimer = tic;
    end

    ensureClientConnection();

    if timingEnabled
        unitlm_timing_probe('connect', 'client', ...
            t, toc(connectTimer), expectedCount, true);
    end

    sendVector = state.sendBuffer(:);

    if timingEnabled
        writeTimer = tic;
    end
    writeBatch(sendVector, expectedCount);
    if timingEnabled
        unitlm_timing_probe('write', 'client', ...
            t, toc(writeTimer), expectedCount, true);
    end

    if timingEnabled
        readTimer = tic;
    end
    [receivedVector, ok] = readNDoubles( ...
        getReceiveObject(), expectedCount);
    if timingEnabled
        unitlm_timing_probe('read', 'client', ...
            t, toc(readTimer), expectedCount, ok);
    end

    if ~ok
        error('Client_co_TLM_Batch:ReadTimeout', ...
            ['TLM client timed out at model time %.9g s while waiting for ', ...
             '%d values (%d signals x %d buffered steps). ', ...
             'Check that the server uses the same n and batchSteps, ', ...
             'and that both simulations are still running.'], ...
             t, expectedCount, n, N);
    end

    % Each column is one simulation-step vector.
    state.receiveBuffer = reshape(receivedVector, n, N);

    % Start collecting the next outgoing batch.
    state.sendBuffer(:) = 0;
    state.index = 1;
end

batchState('set', state);
if timingEnabled
    unitlm_timing_probe('updateEnd', 'client', t, toc(updateTimer));
end
sys = x;
end


%% ========================================================================
function sys = mdlTerminate()
global t_tlm_client_receive t_tlm_client_send;

batchState('clear');
clientConnectionState('reset');

closeTcpObject(t_tlm_client_receive);
closeTcpObject(t_tlm_client_send);

t_tlm_client_receive = [];
t_tlm_client_send = [];

sys = [];
end


%% ========================================================================
function writeBatch(sendVector, expectedCount)
global t_tlm_client_send;

if numel(sendVector) ~= expectedCount
    error('Client_co_TLM_Batch:InternalPacketLength', ...
        'Outgoing packet contains %d values; expected %d.', ...
        numel(sendVector), expectedCount);
end

try
    fwrite(t_tlm_client_send, sendVector, 'double');

catch ME
    clientConnectionState('reset');
    error('Client_co_TLM_Batch:WriteFailed', ...
        ['TLM client batch write failed. Stop both simulations and restart ', ...
         'the client after starting the server and then restart the client. Details: %s'], ME.message);
end
end


%% ========================================================================
function obj = getReceiveObject()
global t_tlm_client_receive;
obj = t_tlm_client_receive;
end


%% ========================================================================
function ensureClientConnection()
global t_tlm_client_receive t_tlm_client_send;

if clientConnectionState('isopen')
    return;
end

params = loadClientTlmParameters();
serverIp = params.serverIp;

if isTcpOpen(t_tlm_client_receive) && isTcpOpen(t_tlm_client_send)
    clientConnectionState('setopen');
    return;
end

closeTcpObject(t_tlm_client_send);
closeTcpObject(t_tlm_client_receive);

t_tlm_client_send = [];
t_tlm_client_receive = [];

cleanupStaleTcpObjects(params.ports);

requiredBytes = 8 * params.n * params.batchSteps;
bufferSize = max(params.bufferSize, 2 * requiredBytes);

fprintf('Initializing batched TLM TCP client for server %s...\n', serverIp);

t_tlm_client_send = tcpip( ...
    serverIp, ...
    params.clientToServerPort, ...
    'NetworkRole', 'client');

t_tlm_client_receive = tcpip( ...
    serverIp, ...
    params.serverToClientPort, ...
    'NetworkRole', 'client');

set(t_tlm_client_send, ...
    'OutputBufferSize', bufferSize, ...
    'Timeout', params.timeoutSeconds);

set(t_tlm_client_receive, ...
    'InputBufferSize', bufferSize, ...
    'Timeout', params.timeoutSeconds);

try
    openTcpClient( ...
        t_tlm_client_send, ...
        serverIp, ...
        params.clientToServerPort, ...
        'client send channel -> server receive channel');

    openTcpClient( ...
        t_tlm_client_receive, ...
        serverIp, ...
        params.serverToClientPort, ...
        'client receive channel <- server send channel');

catch ME
    clientConnectionState('reset');
    closeTcpObject(t_tlm_client_send);
    closeTcpObject(t_tlm_client_receive);

    t_tlm_client_send = [];
    t_tlm_client_receive = [];

    error('Client_co_TLM_Batch:ConnectionFailed', ...
        ['Client_co_TLM_Batch could not connect to the server. Start the ', ...
         'server model first and wait until it is listening on ports %d ', ...
         'and %d. Also check network reachability and Windows Firewall. ', ...
         'Details: %s'], ...
         params.clientToServerPort, ...
         params.serverToClientPort, ...
         ME.message);
end

clientConnectionState('setopen');
fprintf(['Client_co_TLM_Batch initialized: n = %d, batchSteps = %d, ', ...
         'sampleTime = %.12g s, batch interval = %.12g s.\n'], ...
         params.n, params.batchSteps, params.sampleTime, ...
         params.batchSteps * params.sampleTime);
end


%% ========================================================================
function result = clientConnectionState(action)
persistent knownOpen;

if isempty(knownOpen)
    knownOpen = false;
end

switch lower(action)
    case 'isopen'
        result = knownOpen;

    case 'setopen'
        knownOpen = true;
        result = knownOpen;

    case 'reset'
        knownOpen = false;
        result = knownOpen;

    otherwise
        error('Client_co_TLM_Batch:InvalidConnectionStateAction', ...
            'Unknown client connection-state action: %s.', action);
end
end


function params = loadClientTlmParameters(forceReload)
persistent cachedParams;

if nargin < 1
    forceReload = false;
end

if ~forceReload && ~isempty(cachedParams)
    params = cachedParams;
    return;
end

% Read shared co-simulation parameters from the base workspace
if evalin('base', 'exist(''params'', ''var'')') ~= 1
    error('Client_co_TLM:MissingBaseParams', ...
        ['Variable "params" was not found in the base workspace. ' ...
         'Run the model initialization function before starting simulation.']);
end

baseParams = evalin('base', 'params');

requiredFields = {'sampleTime', 'n', 'batchSteps'};

for k = 1:numel(requiredFields)
    fieldName = requiredFields{k};

    if ~isfield(baseParams, fieldName)
        error('Client_co_TLM:MissingParameterField', ...
            'Base-workspace params is missing field "%s".', ...
            fieldName);
    end
end

params.serverIp = '100.72.6.122';
params.listenAddress = '0.0.0.0';

% Shared parameters from model initialization
params.sampleTime = baseParams.sampleTime;
params.n          = baseParams.n;
params.batchSteps = baseParams.batchSteps;

params.timeoutSeconds = 30;
params.clientToServerPort = 30011;
params.serverToClientPort = 30010;
params.bufferSize = 20000;

params.initialOutput = 0;

params.waveformFolderName = 'tlm_waveforms';
params.ports = [ ...
    params.clientToServerPort, ...
    params.serverToClientPort];

validateBatchParameters(params);
cachedParams = params;
end


%% ========================================================================
function validateBatchParameters(params)
if ~isscalar(params.n) || params.n < 1 || params.n ~= floor(params.n)
    error('Client_co_TLM_Batch:InvalidN', ...
        'params.n must be a positive integer.');
end

if ~isscalar(params.batchSteps) || ...
        params.batchSteps < 1 || ...
        params.batchSteps ~= floor(params.batchSteps)
    error('Client_co_TLM_Batch:InvalidBatchSteps', ...
        'params.batchSteps must be a positive integer.');
end

if ~isscalar(params.sampleTime) || ...
        ~isfinite(params.sampleTime) || ...
        params.sampleTime <= 0
    error('Client_co_TLM_Batch:InvalidSampleTime', ...
        'params.sampleTime must be a positive finite scalar.');
end

initialOutput = params.initialOutput(:);
if ~(isscalar(initialOutput) || numel(initialOutput) == params.n)
    error('Client_co_TLM_Batch:InvalidInitialOutput', ...
        'params.initialOutput must be scalar or contain exactly %d values.', ...
        params.n);
end
end


%% ========================================================================
function result = batchState(action, varargin)
persistent state;
result = [];

switch lower(action)
    case 'reset'
        params = varargin{1};

        initialOutput = params.initialOutput(:);
        if isscalar(initialOutput)
            initialOutput = repmat(double(initialOutput), params.n, 1);
        else
            initialOutput = double(initialOutput);
        end

        state = struct();
        state.n = params.n;
        state.batchSteps = params.batchSteps;
        state.index = 1;
        state.sendBuffer = zeros(params.n, params.batchSteps);
        state.receiveBuffer = repmat(initialOutput, 1, params.batchSteps);

    case 'get'
        params = varargin{1};

        if isempty(state) || ...
                state.n ~= params.n || ...
                state.batchSteps ~= params.batchSteps
            batchState('reset', params);
        end

        result = state;

    case 'set'
        state = varargin{1};

    case 'clear'
        state = [];

    otherwise
        error('Client_co_TLM_Batch:InvalidStateAction', ...
            'Unknown batch-state action: %s.', action);
end
end


%% ========================================================================
function [data, ok] = readNDoubles(obj, count)
data = zeros(count, 1);
ok = false;

try
    received = fread(obj, count, 'double');

    if numel(received) == count
        data = received(:);
        ok = true;
    else
        clientConnectionState('reset');
    end

catch
    clientConnectionState('reset');
    ok = false;
end
end


%% ========================================================================
function payload = validatePayload(u, n, signalName)
payload = u(:);

if numel(payload) ~= n
    error('Client_co_TLM_Batch:InvalidPayloadLength', ...
        '%s must contain exactly %d values, but got %d.', ...
        signalName, n, numel(payload));
end

if ~isreal(payload)
    error('Client_co_TLM_Batch:ComplexPayload', ...
        ['%s must be real-valued. Convert complex phasors before ', ...
         'TCP transmission.'], signalName);
end

if any(~isfinite(payload))
    error('Client_co_TLM_Batch:NonfinitePayload', ...
        '%s contains NaN or Inf.', signalName);
end

payload = double(payload);
end


%% ========================================================================
function y = sanitizeOutput(x, n)
y = x(:);

if numel(y) ~= n || ~isreal(y) || any(~isfinite(y))
    y = zeros(n, 1);
end
end


%% ========================================================================
function result = tlmWaveformLog(action, role, varargin)
persistent logs;
result = [];
role = lower(role);

if isempty(logs)
    logs = struct();
end

switch lower(action)
    case 'reset'
        params = varargin{1};

        log = struct();
        log.role = role;
        log.runId = char(datetime('now', ...
            'Format', 'yyyyMMdd_HHmmss_SSS'));
        log.startedAt = char(datetime('now', ...
            'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
        log.sampleTime = params.sampleTime;
        log.n = params.n;
        log.batchSteps = params.batchSteps;
        log.count = 0;

        capacity = 10000;
        log.time = zeros(capacity, 1);
        log.local = zeros(capacity, params.n);
        log.remote = zeros(capacity, params.n);

        logs.(role) = log;

    case 'record'
        t = varargin{1};
        localSignal = varargin{2};
        remoteSignal = varargin{3};
        params = varargin{4};

        if ~isfield(logs, role)
            tlmWaveformLog('reset', role, params);
        end

        log = logs.(role);

        if log.count >= size(log.time, 1)
            newCapacity = max(2 * size(log.time, 1), log.count + 1);
            log.time(newCapacity, 1) = 0;
            log.local(newCapacity, params.n) = 0;
            log.remote(newCapacity, params.n) = 0;
        end

        log.count = log.count + 1;
        log.time(log.count, 1) = double(t);
        log.local(log.count, :) = reshape(double(localSignal), 1, []);
        log.remote(log.count, :) = reshape(double(remoteSignal), 1, []);

        logs.(role) = log;

    case 'save'
        params = varargin{1};

        if ~isfield(logs, role)
            return;
        end

        log = logs.(role);

        if log.count == 0
            logs = rmfield(logs, role);
            return;
        end

        try
            folderPath = fullfile( ...
                fileparts(mfilename('fullpath')), ...
                params.waveformFolderName);

            if ~exist(folderPath, 'dir')
                mkdir(folderPath);
            end

            time = log.time(1:log.count, :);
            localSignal = log.local(1:log.count, :);
            remoteSignal = log.remote(1:log.count, :);

            waveform = buildTlmWaveformStruct( ...
                role, log, time, localSignal, remoteSignal, params);

            baseName = makeUniqueTlmBaseName( ...
                folderPath, role, log, params);

            matPath = fullfile(folderPath, [baseName, '.mat']);
            csvPath = fullfile(folderPath, [baseName, '.csv']);

            save(matPath, 'waveform');

            tableData = makeTlmWaveformTable(waveform, params.n);
            writetable(tableData, csvPath);

            fprintf('TLM %s waveform saved to MAT: %s\n', role, matPath);
            fprintf('TLM %s waveform saved to CSV: %s\n', role, csvPath);

        catch ME
            warning('Client_co_TLM_Batch:WaveformSaveFailed', ...
                'Could not save TLM %s waveform: %s', ...
                role, ME.message);
        end

        logs = rmfield(logs, role);

    otherwise
        error('Client_co_TLM_Batch:InvalidWaveformLogAction', ...
            'Unknown TLM waveform log action: %s.', action);
end
end


%% ========================================================================
function waveform = buildTlmWaveformStruct( ...
        role, log, time, localSignal, remoteSignal, params)

[localVoltage, localCurrent] = splitTlmVoltageCurrent(localSignal);
[remoteVoltage, remoteCurrent] = splitTlmVoltageCurrent(remoteSignal);

if strcmp(role, 'client')
    serverVoltage = localVoltage;
    serverCurrent = localCurrent;
    clientVoltage = remoteVoltage;
    clientCurrent = remoteCurrent;
    localName = 'server_tlm_vector';
    remoteName = 'client_tlm_vector';
else
    serverVoltage = remoteVoltage;
    serverCurrent = remoteCurrent;
    clientVoltage = localVoltage;
    clientCurrent = localCurrent;
    localName = 'client_tlm_vector';
    remoteName = 'server_tlm_vector';
end

waveform = struct();
waveform.role = role;
waveform.startedAt = log.startedAt;
waveform.finishedAt = char(datetime('now', ...
    'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));

waveform.sampleTime = params.sampleTime;
waveform.n = params.n;
waveform.batchSteps = params.batchSteps;
waveform.batchInterval_s = params.batchSteps * params.sampleTime;

waveform.serverIp = params.serverIp;
waveform.clientToServerPort = params.clientToServerPort;
waveform.serverToClientPort = params.serverToClientPort;

waveform.vectorOrder = '[Vabc, Iabc]';
waveform.packetOrder = ...
    '[sample_1(:); sample_2(:); ...; sample_batchSteps(:)]';

waveform.localSignalName = localName;
waveform.remoteSignalName = remoteName;
waveform.currentSignConvention = ...
    'Raw exchanged current is saved with no automatic sign inversion.';

waveform.time_s = time;
waveform.local_send = localSignal;
waveform.remote_used = remoteSignal;

waveform.server_voltage_abc = serverVoltage;
waveform.server_current_abc = serverCurrent;
waveform.client_voltage_abc = clientVoltage;
waveform.client_current_abc = clientCurrent;
end


%% ========================================================================
function [voltage, current] = splitTlmVoltageCurrent(signal)
rows = size(signal, 1);

voltage = nan(rows, 3);
current = nan(rows, 3);

voltage(:, 1:min(3, size(signal, 2))) = ...
    signal(:, 1:min(3, size(signal, 2)));

if size(signal, 2) >= 6
    current = signal(:, 4:6);

elseif size(signal, 2) > 3
    cols = size(signal, 2) - 3;
    current(:, 1:cols) = signal(:, 4:end);
end
end


%% ========================================================================
function tableData = makeTlmWaveformTable(waveform, n)
values = [ ...
    waveform.time_s, ...
    waveform.server_voltage_abc, ...
    waveform.server_current_abc, ...
    waveform.client_voltage_abc, ...
    waveform.client_current_abc, ...
    waveform.local_send, ...
    waveform.remote_used];

names = [ ...
    {'time_s'}, ...
    abcColumnNames('server_voltage'), ...
    abcColumnNames('server_current'), ...
    abcColumnNames('client_voltage'), ...
    abcColumnNames('client_current'), ...
    indexedColumnNames('local_send', n), ...
    indexedColumnNames('remote_used', n)];

tableData = array2table(values, 'VariableNames', names);
end


%% ========================================================================
function names = abcColumnNames(prefix)
phaseNames = {'a', 'b', 'c'};
names = cell(1, 3);

for k = 1:3
    names{k} = [prefix, '_', phaseNames{k}];
end
end


%% ========================================================================
function names = indexedColumnNames(prefix, n)
names = cell(1, n);

for k = 1:n
    names{k} = sprintf('%s_%d', prefix, k);
end
end


%% ========================================================================
function baseName = makeUniqueTlmBaseName(folderPath, role, log, params)
baseName = sprintf('TLM_%s_%s_n%d_B%d_Ts%s_P%d_%d', ...
    role, ...
    log.runId, ...
    params.n, ...
    params.batchSteps, ...
    sampleTimeName(params.sampleTime), ...
    params.clientToServerPort, ...
    params.serverToClientPort);

candidate = baseName;
suffix = 1;

while exist(fullfile(folderPath, [candidate, '.mat']), 'file') || ...
        exist(fullfile(folderPath, [candidate, '.csv']), 'file')

    candidate = sprintf('%s_%02d', baseName, suffix);
    suffix = suffix + 1;
end

baseName = candidate;
end


%% ========================================================================
function text = sampleTimeName(sampleTime)
if sampleTime < 1e-3
    value = sampleTime * 1e6;
    unit = 'us';

elseif sampleTime < 1
    value = sampleTime * 1e3;
    unit = 'ms';

else
    value = sampleTime;
    unit = 's';
end

text = sprintf('%.12g%s', value, unit);
text = strrep(text, '.', 'p');
text = strrep(text, '+', 'p');
text = strrep(text, '-', 'm');
end


%% ========================================================================
function tf = isTcpOpen(obj)
tf = false;

if isempty(obj)
    return;
end

try
    tf = isvalid(obj) && strcmp(obj.Status, 'open');

catch
    try
        tf = strcmp(obj.Status, 'open');

    catch
        tf = false;
    end
end
end


%% ========================================================================
function closeTcpObject(obj)
if isempty(obj)
    return;
end

try
    if strcmp(obj.Status, 'open')
        fclose(obj);
    end
catch
end

try
    delete(obj);
catch
end
end


%% ========================================================================
function cleanupStaleTcpObjects(ports)
try
    objs = instrfindall('Type', 'tcpip');
catch
    objs = [];
end

for k = 1:numel(objs)
    objectPorts = getTcpObjectPorts(objs(k));

    if any(ismember(objectPorts, ports))
        closeTcpObject(objs(k));
    end
end
end


%% ========================================================================
function openTcpClient(obj, serverIp, portNumber, channelName)
fprintf('Connecting to %s:%d (%s)...\n', ...
    serverIp, portNumber, channelName);

try
    fopen(obj);

catch ME
    error('Client_co_TLM_Batch:OpenFailed', ...
        'Failed to open %s on %s:%d. %s', ...
        channelName, serverIp, portNumber, ME.message);
end

fprintf('Connected to port %d.\n', portNumber);
end


%% ========================================================================
function ports = getTcpObjectPorts(obj)
ports = [];

try
    ports(end + 1) = get(obj, 'RemotePort');
catch
end

try
    ports(end + 1) = get(obj, 'LocalPort');
catch
end

ports = ports(~isnan(ports));
end
