function setup_two_pc_cosim()
%SETUP_TWO_PC_COSIM Configure MATLAB path for the shared co-simulation folder.

projectDir = fileparts(mfilename('fullpath'));
addpath(projectDir);

rehash;

matlabRelease = version('-release');
if ~strcmpi(matlabRelease, '2025b')
    warning('setup_two_pc_cosim:RecommendedRelease', ...
        ['This model is saved in R2025b and should be run with MATLAB R2025b. ', ...
        'Current MATLAB release is %s.'], matlabRelease);
end

fprintf('Two-PC co-simulation path configured.\n');
fprintf('Project folder: %s\n', projectDir);
fprintf('ITM server model: IEEE14_bus_system_model_ITM_server.slx\n');
fprintf('ITM client model: IEEE14_bus_system_model_ITM_client.slx\n');
fprintf('TLM server model: IEEE14_bus_system_model_TLM_server.slx\n');
fprintf('TLM client model: IEEE14_bus_system_model_TLM_client.slx\n');
fprintf('Co-simulation sample time: 50e-6 s\n');
fprintf('Server Tailscale IP: 100.72.6.122\n');
end
