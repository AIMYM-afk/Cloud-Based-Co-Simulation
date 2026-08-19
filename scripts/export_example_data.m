function export_example_data(sourceFolder, outputFolder, timeWindow, stride)
%EXPORT_EXAMPLE_DATA Create compact GitHub-safe waveform MAT files.
%
% Example:
%   export_example_data(rawFolder, outputFolder, [0.09 0.16], 10)

if nargin < 3 || isempty(timeWindow)
    timeWindow = [0.09 0.16];
end
if nargin < 4 || isempty(stride)
    stride = 10;
end
if nargin < 2 || isempty(outputFolder)
    outputFolder = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
        'examples', 'waveforms');
end

validateattributes(timeWindow, {'numeric'}, ...
    {'real', 'finite', 'numel', 2, 'increasing'});
validateattributes(stride, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'integer', 'positive'});

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

fileNames = {
    'ref_system.mat'
    'client_TLM_G.mat'
    'server_TLM_G.mat'
    'client_TLM_TL.mat'
    'server_TLM_TL.mat'
    'client_ITM.mat'
    'server_ITM.mat'
};

for fileIndex = 1:numel(fileNames)
    sourceFile = fullfile(sourceFolder, fileNames{fileIndex});
    if exist(sourceFile, 'file') ~= 2
        error('export_example_data:MissingInput', ...
            'Missing source file: %s', sourceFile);
    end

    sourceData = load(sourceFile);
    variableNames = fieldnames(sourceData);
    compactData = struct();

    for variableIndex = 1:numel(variableNames)
        variableName = variableNames{variableIndex};
        sourceSeries = sourceData.(variableName);
        if ~isa(sourceSeries, 'timeseries')
            warning('export_example_data:SkippedVariable', ...
                'Skipping %s in %s because it is not a timeseries.', ...
                variableName, fileNames{fileIndex});
            continue;
        end

        candidate = find(sourceSeries.Time >= timeWindow(1) & ...
            sourceSeries.Time <= timeWindow(2));
        if isempty(candidate)
            error('export_example_data:EmptyWindow', ...
                'No samples from %s lie in [%g, %g] s.', ...
                variableName, timeWindow(1), timeWindow(2));
        end
        keep = candidate(1:stride:end);

        compactSeries = timeseries( ...
            sourceSeries.Data(keep, :), sourceSeries.Time(keep));
        compactSeries.Name = sourceSeries.Name;
        compactData.(variableName) = compactSeries;
    end

    outputFile = fullfile(outputFolder, fileNames{fileIndex});
    save(outputFile, '-struct', 'compactData', '-v7');
    fprintf('Saved %s\n', outputFile);
end
end
