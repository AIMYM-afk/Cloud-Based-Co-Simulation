function savedFiles = archive_run_results(caseName, targetFolder)
%ARCHIVE_RUN_RESULTS Preserve one completed simulation for comparison.
%
% Run this after both computers have stopped and both result files have
% been copied into this repository's result folder.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
sourceFolder = fullfile(projectRoot, 'result');
if nargin < 2 || isempty(targetFolder)
    targetFolder = fullfile(sourceFolder, 'comparison');
end
if ~exist(targetFolder, 'dir')
    mkdir(targetFolder);
end

key = lower(regexprep(string(caseName), '[^a-zA-Z0-9]', ''));
switch key
    case {"reference", "ref"}
        sourceNames = "ref_system.mat";
        targetNames = "ref_system.mat";
    case "itm"
        sourceNames = ["client_ITM.mat", "server_ITM.mat"];
        targetNames = sourceNames;
    case {"tlmtl", "unitlm"}
        sourceNames = ["client_TLM.mat", "server_TLM.mat"];
        targetNames = ["client_TLM_TL.mat", "server_TLM_TL.mat"];
    case {"tlmg", "lctlm"}
        sourceNames = ["client_TLM.mat", "server_TLM.mat"];
        targetNames = ["client_TLM_G.mat", "server_TLM_G.mat"];
    otherwise
        error('archive_run_results:UnknownCase', ...
            'Unknown case "%s". Use Reference, ITM, TLM-TL, or TLM-G.', ...
            caseName);
end

savedFiles = strings(numel(sourceNames), 1);
for k = 1:numel(sourceNames)
    sourceFile = fullfile(sourceFolder, sourceNames(k));
    targetFile = fullfile(targetFolder, targetNames(k));
    if exist(sourceFile, 'file') ~= 2
        error('archive_run_results:MissingResult', ...
            'Missing completed-run result: %s', sourceFile);
    end
    copyfile(sourceFile, targetFile, 'f');
    savedFiles(k) = targetFile;
    fprintf('Archived %s\n', targetFile);
end

plotFolder = fullfile(projectRoot, 'examples', 'waveforms');
plotScripts = [
    "compare_ref_vs_unitlm_waveforms.m"
    "compare_ref_pairwise_a_phase.m"
];
for k = 1:numel(plotScripts)
    copyfile(fullfile(plotFolder, plotScripts(k)), ...
        fullfile(targetFolder, plotScripts(k)), 'f');
end

fprintf('Comparison folder: %s\n', targetFolder);
end
