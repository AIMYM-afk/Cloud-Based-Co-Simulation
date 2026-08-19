function [sys, x0, str, ts] = Client_co(t, x, u, flag)
switch flag
    case 0
        [sys, x0, str, ts] = mdlInitializeSizes();
    case 3
        sys = mdlOutputs(t, x, u);
    case 9
        sys = mdlTerminate();
    case {1, 2, 4}
        sys = [];
    otherwise
        error(['Unhandled flag = ', num2str(flag)]);
end
end

function [sys, x0, str, ts] = mdlInitializeSizes()
params = loadClientParameters();
n = params.n;

sizes = simsizes;
sizes.NumContStates = 0;
sizes.NumDiscStates = 0;
sizes.NumOutputs = n;
sizes.NumInputs = n;
sizes.DirFeedthrough = 1;
sizes.NumSampleTimes = 1;
sys = simsizes(sizes);
x0 = [];
str = [];
ts = [params.sampleTime 0];
itmWaveformLog('reset', 'client', params);

global t_client_receive t_client_send;
serverIp = params.serverIp;

closeTcpObject(t_client_send);
closeTcpObject(t_client_receive);
t_client_send = [];
t_client_receive = [];
cleanupStaleTcpObjects(params.ports);

disp(['Initializing TCP client for server ', serverIp, '...']);
t_client_send = tcpip(serverIp, params.clientToServerPort, 'NetworkRole', 'client');
t_client_receive = tcpip(serverIp, params.serverToClientPort, 'NetworkRole', 'client');
set(t_client_send, ...
    'OutputBufferSize', params.bufferSize, ...
    'Timeout', params.timeoutSeconds);
set(t_client_receive, ...
    'InputBufferSize', params.bufferSize, ...
    'Timeout', params.timeoutSeconds);

try
    openTcpClient(t_client_send, serverIp, params.clientToServerPort, ...
        'client send channel -> server receive channel');
    openTcpClient(t_client_receive, serverIp, params.serverToClientPort, ...
        'client receive channel <- server send channel');
catch ME
    closeTcpObject(t_client_send);
    closeTcpObject(t_client_receive);
    t_client_send = [];
    t_client_receive = [];
    error('Client_co:ConnectionFailed', ...
        ['Client_co could not connect to the server. Start the server ', ...
        'model first and wait until it is listening on ports 30011 and 30010. ', ...
        'Also check Tailscale reachability to %s and Windows Firewall. Details: %s'], ...
        serverIp, ME.message);
end
primeInitialSend(t_client_send, n, 'Client_co');
disp('Client_co initialized successfully.');
end

function sys = mdlOutputs(t, ~, u)
params = loadClientParameters();
n = params.n;
global t_client_receive t_client_send;
persistent last_valid_data;
if isempty(last_valid_data) || numel(last_valid_data) ~= n
    last_valid_data = zeros(n, 1);
end

% Send local three-phase interface signal. Do not try to reconnect here:
% reconnecting can block Simulink and make the Stop button unresponsive.
payload = validatePayload(u, n, 'Client_co input');
try
    if isTcpOpen(t_client_send)
        fwrite(t_client_send, payload, 'double');
    else
        error('Client send socket is not open.');
    end
catch ME
    error('Client_co:WriteFailed', ...
        'Client write failed. Stop both simulations and restart server first. Details: %s', ...
        ME.message);
end

[data_recv, ok] = readNDoubles(t_client_receive, n, params.timeoutSeconds);
if ok
    last_valid_data = data_recv;
else
    error('Client_co:ReadTimeout', ...
        ['Client timed out at model time %.9g s after %.1f seconds while waiting ', ...
        'for %d server value(s). Check that the server model is still running ', ...
        'and that TCP port %d is reachable.'], ...
        t, params.timeoutSeconds, n, params.serverToClientPort);
end

sys = sanitizeOutput(last_valid_data, n);
itmWaveformLog('record', 'client', t, payload, sys, params);
end

function sys = mdlTerminate()
global t_client_receive t_client_send;
params = loadClientParameters();
itmWaveformLog('save', 'client', params);
closeTcpObject(t_client_send);
closeTcpObject(t_client_receive);
t_client_send = [];
t_client_receive = [];
sys = [];
end

function params = loadClientParameters()
% BEGIN AUTO COSIM PARAMETERS
network = cosim_network_config();
params.serverIp = network.serverIp;
params.listenAddress = network.listenAddress;
params.baseSampleTime = 5e-7;
params.batchSteps = 100;
params.sampleTime = params.batchSteps*params.baseSampleTime;
params.n = 3;
params.timeoutSeconds = network.timeoutSeconds;
params.clientToServerPort = network.clientToServerPort;
params.serverToClientPort = network.serverToClientPort;
params.bufferSize = network.itmBufferSize;
% END AUTO COSIM PARAMETERS
params.waveformFolderName = 'itm_waveforms';
params.ports = [params.clientToServerPort, params.serverToClientPort];
end

function [data, ok] = readNDoubles(obj, n, timeoutSeconds)
data = zeros(n, 1);
ok = false;
startTime = tic;
bytesNeeded = n * 8;

while toc(startTime) < timeoutSeconds
    drawnow limitrate;

    if ~isTcpOpen(obj)
        return;
    end

    try
        if obj.BytesAvailable >= bytesNeeded
            data = fread(obj, n, 'double');
            ok = numel(data) == n;
            if ok
                data = data(:);
            end
            return;
        end
    catch
        return;
    end

    pause(1e-4);
end
end

function payload = validatePayload(u, n, signalName)
payload = u(:);
if numel(payload) ~= n
    error('Client_co:InvalidPayloadLength', ...
        '%s must contain exactly %d value(s), but got %d.', ...
        signalName, n, numel(payload));
end
if ~isreal(payload)
    error('Client_co:ComplexPayload', ...
        '%s must be real-valued before TCP transmission.', signalName);
end
payload = double(payload);
end

function primeInitialSend(obj, n, roleName)
try
    fwrite(obj, zeros(n, 1), 'double');
    disp([roleName, ' sent initial zero frame.']);
catch ME
    error('Client_co:InitialPrimeFailed', ...
        '%s could not send the initial zero frame after TCP connection. Details: %s', ...
        roleName, ME.message);
end
end

function result = itmWaveformLog(action, role, varargin)
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
        log.runId = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
        log.startedAt = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
        log.sampleTime = params.sampleTime;
        log.n = params.n;
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
            itmWaveformLog('reset', role, params);
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
            folderPath = fullfile(fileparts(mfilename('fullpath')), params.waveformFolderName);
            if ~exist(folderPath, 'dir')
                mkdir(folderPath);
            end

            time = log.time(1:log.count, :);
            localSignal = log.local(1:log.count, :);
            remoteSignal = log.remote(1:log.count, :);
            waveform = buildItmWaveformStruct(role, log, time, localSignal, remoteSignal, params);
            baseName = makeUniqueItmBaseName(folderPath, role, log, params);
            matPath = fullfile(folderPath, [baseName, '.mat']);
            csvPath = fullfile(folderPath, [baseName, '.csv']);

            save(matPath, 'waveform');
            tableData = makeItmWaveformTable(waveform, params.n);
            writetable(tableData, csvPath);

            disp(['ITM ', role, ' waveform saved to MAT: ', matPath]);
            disp(['ITM ', role, ' waveform saved to CSV: ', csvPath]);
        catch ME
            warning('Client_co:WaveformSaveFailed', ...
                'Could not save ITM %s waveform: %s', role, ME.message);
        end
        logs = rmfield(logs, role);

    otherwise
        error('Client_co:InvalidWaveformLogAction', ...
            'Unknown ITM waveform log action: %s', action);
end
end

function waveform = buildItmWaveformStruct(role, log, time, localSignal, remoteSignal, params)
if strcmp(role, 'server')
    voltage = localSignal;
    current = remoteSignal;
    localName = 'server_voltage_abc';
    remoteName = 'client_current_abc';
else
    voltage = remoteSignal;
    current = localSignal;
    localName = 'client_current_abc';
    remoteName = 'server_voltage_abc';
end

waveform = struct();
waveform.role = role;
waveform.startedAt = log.startedAt;
waveform.finishedAt = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
waveform.sampleTime = params.sampleTime;
waveform.n = params.n;
waveform.serverIp = params.serverIp;
waveform.clientToServerPort = params.clientToServerPort;
waveform.serverToClientPort = params.serverToClientPort;
waveform.localSignalName = localName;
waveform.remoteSignalName = remoteName;
waveform.currentSignConvention = 'Raw exchanged current is saved with no automatic sign inversion.';
waveform.time_s = time;
waveform.local_send_abc = localSignal;
waveform.remote_receive_abc = remoteSignal;
waveform.server_voltage_abc = voltage;
waveform.server_current_abc = current;
waveform.client_voltage_abc = voltage;
waveform.client_current_abc = current;
end

function tableData = makeItmWaveformTable(waveform, n)
values = [waveform.time_s, ...
    waveform.server_voltage_abc, waveform.server_current_abc, ...
    waveform.client_voltage_abc, waveform.client_current_abc, ...
    waveform.local_send_abc, waveform.remote_receive_abc];

names = [{'time_s'}, ...
    abcColumnNames('server_voltage', n), abcColumnNames('server_current', n), ...
    abcColumnNames('client_voltage', n), abcColumnNames('client_current', n), ...
    abcColumnNames('local_send', n), abcColumnNames('remote_receive', n)];
tableData = array2table(values, 'VariableNames', names);
end

function names = abcColumnNames(prefix, n)
phaseNames = {'a', 'b', 'c'};
names = cell(1, n);
for k = 1:n
    if k <= numel(phaseNames)
        suffix = phaseNames{k};
    else
        suffix = sprintf('%d', k);
    end
    names{k} = [prefix, '_', suffix];
end
end

function baseName = makeUniqueItmBaseName(folderPath, role, log, params)
baseName = sprintf('ITM_%s_%s_N%d_Ts%s_P%d_%d', ...
    role, log.runId, params.n, sampleTimeName(params.sampleTime), ...
    params.clientToServerPort, params.serverToClientPort);
candidate = baseName;
suffix = 1;
while exist(fullfile(folderPath, [candidate, '.mat']), 'file') || ...
        exist(fullfile(folderPath, [candidate, '.csv']), 'file')
    candidate = sprintf('%s_%02d', baseName, suffix);
    suffix = suffix + 1;
end
baseName = candidate;
end

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

function y = sanitizeOutput(x, n)
y = x(:);
if isempty(y) || numel(y) ~= n || ~isreal(y) || any(isnan(y))
    y = zeros(n, 1);
end
end

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

function openTcpClient(obj, serverIp, portNumber, channelName)
disp(['Client_co connecting to ', serverIp, ':', num2str(portNumber), ...
    ' (', channelName, ')...']);
try
    fopen(obj);
catch ME
    error('Client_co:OpenFailed', ...
        'Failed to open %s on %s:%d. %s', ...
        channelName, serverIp, portNumber, ME.message);
end
disp(['Client_co connected to port ', num2str(portNumber), '.']);
end
