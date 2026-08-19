function projectRoot = startup_project()
%STARTUP_PROJECT Configure the published microgrid co-simulation project.

projectRoot = fileparts(mfilename('fullpath'));
addpath(projectRoot);
addpath(fullfile(projectRoot, 'functions'));
addpath(fullfile(projectRoot, 'scripts'));
addpath(fullfile(projectRoot, 'examples', 'waveforms'));

resultFolder = fullfile(projectRoot, 'result');
if ~exist(resultFolder, 'dir')
    mkdir(resultFolder);
end

releaseName = version('-release');
if ~strcmpi(releaseName, '2025b')
    warning('startup_project:MATLABRelease', ...
        ['The models were saved in MATLAB R2025b Update 5. Current ', ...
         'release: %s. Use R2025b when possible.'], releaseName);
end

network = cosim_network_config();
[tlm, line, ~] = unitlm_transmission_line_config();

fprintf('\nMicrogrid co-simulation project is ready.\n');
fprintf('Project root: %s\n', projectRoot);
fprintf('Server IP: %s\n', network.serverIp);
fprintf('TCP ports: client->server %d, server->client %d\n', ...
    network.clientToServerPort, network.serverToClientPort);
fprintf('TLM step: %.3g s, batch: %d, interface delay: %.3g s\n', ...
    tlm.sampleTime, tlm.batchSteps, tlm.delay);
fprintf('Physical line: %.3g km, R1=%.4g ohm/km, L1=%.4g H/km, C1=%.4g F/km\n\n', ...
    line.originalLength, line.R(1), line.L(1), line.C(1));
end
