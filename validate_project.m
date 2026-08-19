function report = validate_project(loadModels)
%VALIDATE_PROJECT Check files, initialization, saved filters, and models.

if nargin < 1
    loadModels = true;
end

projectRoot = startup_project();

models = {
    'Microgrid'
    'Microgrid_uniTLM_client'
    'Microgrid_uniTLM_server'
    'Microgrid_LCTLM_client'
    'Microgrid_LCTLM_server'
    'Microgrid_ITM_client_new'
    'Microgrid_ITM_server_new'
};

requiredFiles = [
    strcat(models, '.slx')
    {'Client_co_TLM.m'; 'Server_co_TLM.m'; 'Client_co.m'; 'Server_co.m'}
    {'initialize_unitlm_microgrid.m'; 'initialise_optimised_tlm_interface.m'}
    {'startup_project.m'; 'setup_two_pc_cosim.m'; 'cosim_network_config.m'}
    {'scripts/archive_run_results.m'; 'scripts/export_example_data.m'}
    {'optimised_frequency_dependent_line_filters.mat'}
];

missingFiles = requiredFiles(~cellfun(@(name) ...
    exist(fullfile(projectRoot, name), 'file') ~= 0, requiredFiles));
if ~isempty(missingFiles)
    error('validate_project:MissingFiles', ...
        'Missing required files:\n%s', strjoin(missingFiles, '\n'));
end

initialize_unitlm_microgrid('skipLineFit');
initialise_optimised_tlm_interface();

loadedModels = {};
if loadModels
    for k = 1:numel(models)
        load_system(models{k});
        loadedModels{end + 1, 1} = models{k}; %#ok<AGROW>
        close_system(models{k}, 0);
    end
end

report = struct();
report.projectRoot = projectRoot;
report.matlabRelease = version('-release');
report.requiredFiles = requiredFiles;
report.loadedModels = loadedModels;
report.network = cosim_network_config();
report.passed = true;

fprintf('Validation passed: %d required files, %d models loaded.\n', ...
    numel(requiredFiles), numel(loadedModels));
end
