%% Compare reference, TLM-TL, TLM-G, and ITM waveforms
% Run this script from any folder. It loads the MAT files saved beside this
% script and writes Nature-style figures plus an error-metric CSV to
% comparison_figures.

clear;
clc;
close all;

%% User Settings

% Plot/metric time range. Use [] for the full common time range, or set
% e.g. [0.18 0.45] to zoom into a transient.
TimeWindow = [0.095 0.15];

MaxPlotPoints = 25000;
FigureVisible = "on";       % "on" displays figures while keeping batch export
SavePng = false;
SaveFig = true;
SaveSvg = true;
SavePdf = true;
ExportResolution = 600;

PhaseNames = ["A", "B", "C"];
VoltageUnit = "V";
CurrentUnit = "A";
PowerUnit = "pu";

% y-limits for waveform overlays are set from the reference amplitude in
% the selected time window.
ReferenceYLimPadding = 1.10;
ErrorYLimPadding = 1.15;
ErrorYLimReferenceFraction = 0.10;

% Sign convention used only for overlay/error comparisons. The standalone
% saved signals are not modified. Server-side current and P/Q are measured
% in the opposite direction from the reference-system convention.
CompareSign.client.voltage = 1;
CompareSign.client.current = 1;
CompareSign.client.PQ = [1, 1];
CompareSign.server.voltage = 1;
CompareSign.server.current = 1;
CompareSign.server.PQ = [-1, -1];

% Nature-style plot settings.
Style.FontName = "Arial";
Style.FontSize = 9;
Style.LabelFontSize = 13;
Style.LegendFontSize = 9;
Style.LineWidth = 1.45;
Style.ErrorLineWidth = 0.95;
Style.ItmLineWidth = 0.65;
Style.ItmErrorLineWidth = 0.55;
Style.AxesLineWidth = 0.75;
Style.GridAlpha = 0.10;
Style.FigurePosition = [80 80 460 330];
Style.LegendLocation = "southwest";
Style.Colors = [
    0.0000 0.0000 0.0000  % Reference: black
    0.0000 0.6000 0.5000  % TLM-TL: green
    0.8500 0.3250 0.0980  % TLM-G: vermillion
    0.0000 0.4470 0.7410  % ITM: blue
    ];
Style.LineStyles = ["-", "--", "-.", "-"];

%% Locate Data Folder

scriptPath = mfilename("fullpath");
if strlength(scriptPath) == 0
    dataFolder = pwd;
else
    dataFolder = fileparts(scriptPath);
end

outputFolder = fullfile(dataFolder, "comparison_figures_separate_12");
if ~exist(outputFolder, "dir")
    mkdir(outputFolder);
end

fprintf("Data folder:\n%s\n\n", dataFolder);

%% Define Data Sets

dataSets = struct([]);

dataSets(end+1).key = "ref";
dataSets(end).label = "Reference";
dataSets(end).clientFile = "ref_system.mat";
dataSets(end).serverFile = "ref_system.mat";
dataSets(end).suffix = "ref";
dataSets(end).isReference = true;

dataSets(end+1).key = "tlm_tl";
dataSets(end).label = "TLM-TL";
dataSets(end).clientFile = firstExistingFile(dataFolder, ["client_TLM_TL.mat", "client_TLM.mat"]);
dataSets(end).serverFile = firstExistingFile(dataFolder, ["server_TLM_TL.mat", "server_TLM.mat"]);
dataSets(end).suffix = "TLM";
dataSets(end).isReference = false;

dataSets(end+1).key = "tlm_g";
dataSets(end).label = "TLM-G";
dataSets(end).clientFile = "client_TLM_G.mat";
dataSets(end).serverFile = "server_TLM_G.mat";
dataSets(end).suffix = "TLM";
dataSets(end).isReference = false;

dataSets(end+1).key = "itm";
dataSets(end).label = "ITM";
dataSets(end).clientFile = "client_ITM.mat";
dataSets(end).serverFile = "server_ITM.mat";
dataSets(end).suffix = "ITM";
dataSets(end).isReference = false;

%% Load Result Data

dataSets = loadAllDataSets(dataFolder, dataSets);
dataSets = assignStyle(dataSets, Style);

fprintf("Loaded data sets:\n");
for k = 1:numel(dataSets)
    fprintf("  %s\n", dataSets(k).label);
end
fprintf("\n");

%% Save Separate Three-Phase Voltage and Current Figures

nExported = plotSeparateAbcFigures( ...
    dataSets, ["client", "server"], PhaseNames, VoltageUnit, CurrentUnit, ...
    TimeWindow, MaxPlotPoints, CompareSign, ReferenceYLimPadding, ...
    FigureVisible, Style, outputFolder, SavePng, SaveFig, SaveSvg, ...
    SavePdf, ExportResolution);

nPqExported = plotSeparatePqFigures( ...
    dataSets, "client", PowerUnit, TimeWindow, MaxPlotPoints, ...
    CompareSign.client.PQ, ReferenceYLimPadding, FigureVisible, Style, ...
    outputFolder, SavePng, SaveFig, SaveSvg, SavePdf, ExportResolution, ...
    nExported);

fprintf("\nSaved %d separate voltage/current figures and %d client P/Q figures to:\n%s\n", ...
    nExported, nPqExported, outputFolder);

%% Local Functions

function name = firstExistingFile(folder, candidates)
name = candidates(1);
for k = 1:numel(candidates)
    if isfile(fullfile(folder, candidates(k)))
        name = candidates(k);
        return;
    end
end
end

function dataSets = loadAllDataSets(dataFolder, dataSets)
for k = 1:numel(dataSets)
    dataSets(k).client = loadSideData( ...
        fullfile(dataFolder, dataSets(k).clientFile), ...
        "client", dataSets(k).suffix);
    dataSets(k).server = loadSideData( ...
        fullfile(dataFolder, dataSets(k).serverFile), ...
        "server", dataSets(k).suffix);
end
end

function sideData = loadSideData(filePath, sideName, suffix)
if ~isfile(filePath)
    error("Required file not found: %s", filePath);
end

S = load(filePath);
sideData = struct();
sideData.voltage = readRequiredSignal(S, sideName + "_voltage_" + suffix, filePath);
sideData.current = readRequiredSignal(S, sideName + "_current_" + suffix, filePath);
sideData.PQ = readRequiredSignal(S, sideName + "_PQ_" + suffix, filePath);

omegaName = sideName + "_omega_" + suffix;
if isfield(S, omegaName)
    sideData.omega = S.(omegaName);
else
    sideData.omega = [];
end
end

function signal = readRequiredSignal(S, variableName, filePath)
if ~isfield(S, variableName)
    error("Variable %s was not found in %s.", variableName, filePath);
end
signal = S.(variableName);
end

function dataSets = assignStyle(dataSets, Style)
for k = 1:numel(dataSets)
    styleIndex = min(k, size(Style.Colors, 1));
    dataSets(k).color = Style.Colors(styleIndex, :);
    dataSets(k).lineStyle = Style.LineStyles(styleIndex);
    dataSets(k).lineWidth = Style.LineWidth;
    dataSets(k).errorLineWidth = Style.ErrorLineWidth;

    if dataSets(k).label == "ITM"
        dataSets(k).lineWidth = Style.ItmLineWidth;
        dataSets(k).errorLineWidth = Style.ItmErrorLineWidth;
    end
end
end

function fig = createNatureFigure(figName, visibleMode, Style)
fig = figure( ...
    "Name", figName, ...
    "Visible", visibleMode, ...
    "Color", "w", ...
    "Renderer", "painters", ...
    "Units", "pixels", ...
    "Position", Style.FigurePosition);
end

function nExported = plotSeparateAbcFigures( ...
    dataSets, sideNames, phaseNames, voltageUnit, currentUnit, ...
    timeWindow, maxPlotPoints, compareSign, yPadding, figureVisible, Style, ...
    outputFolder, savePng, saveFig, saveSvg, savePdf, exportResolution)

signalNames = ["voltage", "current"];
signalLabels = ["voltage", "current"];
unitTexts = [voltageUnit, currentUnit];
nExported = 0;

for sideIndex = 1:numel(sideNames)
    sideName = sideNames(sideIndex);

    for signalIndex = 1:numel(signalNames)
        signalName = signalNames(signalIndex);
        signalLabel = signalLabels(signalIndex);
        unitText = unitTexts(signalIndex);

        for ch = 1:numel(phaseNames)
            nExported = nExported + 1;
            plotTitle = sideLabel(sideName) + " " + phaseNames(ch) + ...
                "-phase " + signalLabel;
            showLegend = ch == 1;

            fig = createNatureFigure(plotTitle, figureVisible, Style);
            ax = axes(fig);
            plotOverlayOnly(ax, dataSets, sideName, signalName, ch, ...
                getScale(compareSign, sideName, signalName, ch), ...
                plotTitle, unitText, timeWindow, maxPlotPoints, ...
                yPadding, Style, showLegend);

            baseName = string(sprintf('%02d_%s_%s_%s_phase_4method', ...
                nExported, char(sideName), char(signalName), ...
                lower(char(phaseNames(ch)))));
            exportFigure(fig, outputFolder, baseName, savePng, saveFig, ...
                saveSvg, savePdf, exportResolution);
        end
    end
end
end

function nExported = plotSeparatePqFigures( ...
    dataSets, sideName, powerUnit, timeWindow, maxPlotPoints, ...
    compareScale, yPadding, figureVisible, Style, outputFolder, savePng, ...
    saveFig, saveSvg, savePdf, exportResolution, startIndex)

pqLabels = ["P", "Q"];
nExported = 0;

for ch = 1:numel(pqLabels)
    nExported = nExported + 1;
    plotTitle = sideLabel(sideName) + " " + pqLabels(ch);
    showLegend = ch == 1;
    plotStyle = Style;

    if pqLabels(ch) == "P"
        plotStyle.LegendLocation = "northwest";
    end

    fig = createNatureFigure(plotTitle, figureVisible, plotStyle);
    ax = axes(fig);
    plotOverlayOnly(ax, dataSets, sideName, "PQ", ch, ...
        compareScale(ch), plotTitle, powerUnit, timeWindow, ...
        maxPlotPoints, yPadding, plotStyle, showLegend);

    baseName = string(sprintf('%02d_%s_%s_4method', ...
        startIndex + nExported, char(sideName), lower(char(pqLabels(ch)))));
    exportFigure(fig, outputFolder, baseName, savePng, saveFig, ...
        saveSvg, savePdf, exportResolution);
end
end

function plotAbcOverlayFigure(fig, dataSets, sideName, voltageUnit, ...
    currentUnit, phaseNames, timeWindow, maxPlotPoints, compareSign, ...
    yPadding, Style)

tiledlayout(fig, 2, 3, "TileSpacing", "compact", "Padding", "compact");

for ch = 1:3
    ax = nexttile;
    plotOverlayOnly(ax, dataSets, sideName, "voltage", ch, ...
        getScale(compareSign, sideName, "voltage", ch), ...
        sideLabel(sideName) + " " + phaseNames(ch) + "-phase voltage", ...
        voltageUnit, timeWindow, maxPlotPoints, yPadding, Style);
end

for ch = 1:3
    ax = nexttile;
    plotOverlayOnly(ax, dataSets, sideName, "current", ch, ...
        getScale(compareSign, sideName, "current", ch), ...
        sideLabel(sideName) + " " + phaseNames(ch) + "-phase current", ...
        currentUnit, timeWindow, maxPlotPoints, yPadding, Style);
end
end

function metrics = plotSignalComparisonFigure(fig, dataSets, sideName, ...
    signalName, channel, plotTitle, unitText, timeWindow, maxPlotPoints, ...
    compareScale, yPadding, errorPadding, errorMinReferenceFraction, ...
    Style, startTile)

if nargin < 15
    startTile = 1;
end

if startTile == 1
    tiledlayout(fig, 2, 2, "TileSpacing", "compact", "Padding", "compact");
end

axWave = nexttile(startTile);
axError = nexttile(startTile + 1);

[metrics, refAmplitude, errorAmplitude] = plotOverlayAndErrors( ...
    axWave, axError, dataSets, sideName, signalName, channel, ...
    compareScale, plotTitle, unitText, timeWindow, maxPlotPoints, Style);

applyReferenceYLim(axWave, refAmplitude, yPadding);
applyErrorYLim(axError, refAmplitude, errorAmplitude, ...
    errorPadding, errorMinReferenceFraction);
end

function plotOverlayOnly(ax, dataSets, sideName, signalName, channel, ...
    compareScale, plotTitle, unitText, timeWindow, maxPlotPoints, ...
    yPadding, Style, showLegend, referenceScale)

if nargin < 13
    showLegend = true;
end
if nargin < 14
    referenceScale = 1;
end

[~, refAmplitude] = plotOverlayAndErrors( ...
    ax, [], dataSets, sideName, signalName, channel, compareScale, ...
    plotTitle, unitText, timeWindow, maxPlotPoints, Style, showLegend, ...
    referenceScale);
applyReferenceYLim(ax, refAmplitude, yPadding);
end

function [metrics, refAmplitude, errorAmplitude] = plotOverlayAndErrors( ...
    axWave, axError, dataSets, sideName, signalName, channel, ...
    compareScale, plotTitle, unitText, timeWindow, maxPlotPoints, Style, ...
    showLegend, referenceScale)

if nargin < 13
    showLegend = true;
end
if nargin < 14
    referenceScale = 1;
end

metrics = struct([]);
refTs = dataSets(1).(sideName).(signalName);
[tRef, refY] = selectTimeseriesChannel(refTs, channel, timeWindow);
refY = referenceScale * refY;
idxRef = plotIndex(numel(tRef), maxPlotPoints);

hold(axWave, "on");

refAmplitude = max(abs(refY));
errorAmplitude = 0;
comparison = struct([]);

for k = 2:numel(dataSets)
    simTs = dataSets(k).(sideName).(signalName);
    [t, refAligned, simY] = alignTimeseriesToReference( ...
        refTs, simTs, channel, timeWindow);
    refAligned = referenceScale * refAligned;
    simY = compareScale * simY;
    err = simY - refAligned;

    comparison(k).t = t;
    comparison(k).simY = simY;
    comparison(k).err = err;
    idx = plotIndex(numel(t), maxPlotPoints);
    comparison(k).idx = idx;
    errorAmplitude = max(errorAmplitude, max(abs(err)));
    metrics(end+1).method = dataSets(k).label; %#ok<AGROW>
    metrics(end).values = computeErrorMetrics(t, refAligned, simY, err);
end

plotOrder = bottomFirstPlotOrder(dataSets);
waveHandles = gobjects(1, numel(dataSets));
errorHandles = gobjects(1, numel(dataSets) - 1);

for orderIndex = 1:numel(plotOrder)
    k = plotOrder(orderIndex);
    if k == 1
        waveHandles(k) = plot(axWave, tRef(idxRef), refY(idxRef), ...
            "Color", dataSets(k).color, ...
            "LineStyle", dataSets(k).lineStyle, ...
            "LineWidth", dataSets(k).lineWidth);
        continue;
    end

    idx = comparison(k).idx;
    waveHandles(k) = plot(axWave, ...
        comparison(k).t(idx), ...
        comparison(k).simY(idx), ...
        "Color", dataSets(k).color, ...
        "LineStyle", dataSets(k).lineStyle, ...
        "LineWidth", dataSets(k).lineWidth);

    if ~isempty(axError)
        errorHandles(k - 1) = plot(axError, ...
            comparison(k).t(idx), ...
            comparison(k).err(idx), ...
            "Color", dataSets(k).color, ...
            "LineStyle", dataSets(k).lineStyle, ...
            "LineWidth", dataSets(k).errorLineWidth);
        hold(axError, "on");
    end
end

formatWaveAxes(axWave, plotTitle, unitText, Style);
applyTimeWindowXLim(axWave, timeWindow);
if showLegend
    applyLegendStyle(legend(axWave, waveHandles, [dataSets.label], ...
        "Location", Style.LegendLocation, ...
        "FontName", Style.FontName, ...
        "FontSize", Style.LegendFontSize));
end

if ~isempty(axError)
    formatWaveAxes(axError, plotTitle + " error", ...
        "error (" + unitText + ")", Style);
    applyTimeWindowXLim(axError, timeWindow);
    if showLegend
        applyLegendStyle(legend(axError, errorHandles, [dataSets(2:end).label], ...
            "Location", Style.LegendLocation, ...
            "FontName", Style.FontName, ...
            "FontSize", Style.LegendFontSize));
    end
end
end

function applyLegendStyle(lgd)
lgd.Box = "on";
lgd.Color = "w";
lgd.EdgeColor = "k";
end

function applyTimeWindowXLim(ax, timeWindow)
if isempty(timeWindow)
    return;
end

xlim(ax, timeWindow);
end

function plotOrder = bottomFirstPlotOrder(dataSets)
labels = [dataSets.label];
preferredLabels = ["ITM", "Reference", "TLM-G", "TLM-TL"];
plotOrder = [];

for k = 1:numel(preferredLabels)
    idx = find(labels == preferredLabels(k), 1);
    if ~isempty(idx)
        plotOrder(end+1) = idx; %#ok<AGROW>
    end
end

remaining = setdiff(1:numel(dataSets), plotOrder, "stable");
plotOrder = [plotOrder, remaining];
end

function scale = getScale(compareSign, sideName, signalName, channel)
value = compareSign.(sideName).(signalName);
if isscalar(value)
    scale = value;
else
    scale = value(channel);
end
end

function label = sideLabel(sideName)
if sideName == "client"
    label = "Client";
else
    label = "Server";
end
end

function formatWaveAxes(ax, ~, yLabelText, Style)
set(ax, ...
    "FontName", Style.FontName, ...
    "FontSize", Style.FontSize, ...
    "LineWidth", Style.AxesLineWidth, ...
    "Box", "off", ...
    "TickDir", "out", ...
    "XMinorTick", "on", ...
    "YMinorTick", "on");
grid(ax, "on");
ax.GridAlpha = Style.GridAlpha;
try
    ax.Toolbar.Visible = "off";
    disableDefaultInteractivity(ax);
catch
end
xlabel(ax, "Time (s)", ...
    "FontName", Style.FontName, ...
    "FontSize", Style.LabelFontSize);
ylabel(ax, yLabelText, ...
    "FontName", Style.FontName, ...
    "FontSize", Style.LabelFontSize);
end

function applyReferenceYLim(ax, refAmplitude, padding)
if ~isfinite(refAmplitude) || refAmplitude <= 0
    return;
end
limit = padding * refAmplitude;
ylim(ax, [-limit, limit]);
end

function applyErrorYLim(ax, refAmplitude, ~, padding, referenceFraction)
if ~isfinite(refAmplitude) || refAmplitude <= 0
    return;
end
limit = padding * max(refAmplitude, eps) * referenceFraction;
if limit > 0 && isfinite(limit)
    ylim(ax, [-limit, limit]);
end
end

function [t, y] = selectTimeseriesChannel(ts, channel, timeWindow)
[tAll, yAll] = timeseriesToMatrix(ts);
assert(channel <= size(yAll, 2), "Signal has no channel %d.", channel);

idx = timeWindowIndex(tAll, timeWindow);
t = tAll(idx);
y = yAll(idx, channel);

valid = isfinite(t) & isfinite(y);
t = t(valid);
y = y(valid);

if isempty(t)
    error("No valid samples remain after applying the selected time window.");
end
end

function [t, refY, simY] = alignTimeseriesToReference( ...
    refTs, simTs, channel, timeWindow)

[tRefAll, yRefAll] = timeseriesToMatrix(refTs);
[tSimAll, ySimAll] = timeseriesToMatrix(simTs);

assert(channel <= size(yRefAll, 2), "Reference signal has no channel %d.", channel);
assert(channel <= size(ySimAll, 2), "Compared signal has no channel %d.", channel);

tStart = max(tRefAll(1), tSimAll(1));
tEnd = min(tRefAll(end), tSimAll(end));

if ~isempty(timeWindow)
    tStart = max(tStart, timeWindow(1));
    tEnd = min(tEnd, timeWindow(2));
end

idx = tRefAll >= tStart & tRefAll <= tEnd;
t = tRefAll(idx);
refY = yRefAll(idx, channel);

if isempty(t)
    error("No overlapping samples are available for the selected time window.");
end

if numel(tSimAll) == numel(tRefAll) && ...
        max(abs(tSimAll(:) - tRefAll(:))) < 1e-12
    simY = ySimAll(idx, channel);
else
    simY = interp1(tSimAll, ySimAll(:, channel), t, "linear");
end

valid = isfinite(refY) & isfinite(simY);
t = t(valid);
refY = refY(valid);
simY = simY(valid);
end

function idx = timeWindowIndex(t, timeWindow)
if isempty(timeWindow)
    idx = true(size(t));
    return;
end

if numel(timeWindow) ~= 2 || any(~isfinite(timeWindow)) || ...
        timeWindow(2) <= timeWindow(1)
    error("TimeWindow must be [] or [tStart tEnd] with tEnd > tStart.");
end

idx = t >= timeWindow(1) & t <= timeWindow(2);
end

function [t, y] = timeseriesToMatrix(ts)
if ~isa(ts, "timeseries")
    error("Expected a timeseries object, got %s.", class(ts));
end

t = ts.Time(:);
y = squeeze(ts.Data);

if isvector(y)
    y = y(:);
elseif size(y, 1) ~= numel(t) && size(y, 2) == numel(t)
    y = y.';
elseif size(y, 1) ~= numel(t)
    y = reshape(y, numel(t), []);
end

y = double(y);
end

function idx = plotIndex(n, maxPlotPoints)
if n <= maxPlotPoints
    idx = 1:n;
else
    idx = unique(round(linspace(1, n, maxPlotPoints)));
end
end

function metrics = computeErrorMetrics(t, refY, simY, err)
metrics = struct();
metrics.tStart_s = t(1);
metrics.tEnd_s = t(end);
metrics.nSamples = numel(t);
metrics.refRms = sqrt(mean(refY.^2));
metrics.simRms = sqrt(mean(simY.^2));
metrics.errorMean = mean(err);
metrics.errorRms = sqrt(mean(err.^2));
metrics.errorMaxAbs = max(abs(err));
metrics.errorMae = mean(abs(err));
metrics.errorRelativeRms = metrics.errorRms / max(metrics.refRms, eps);
metrics.errorRelativeMax = metrics.errorMaxAbs / max(max(abs(refY)), eps);
end

function T = metricRows(side, signalName, unitText, metrics)
T = table();
for k = 1:numel(metrics)
    T = [T; metricRow(metrics(k).method, side, signalName, ...
        unitText, metrics(k).values)]; %#ok<AGROW>
end
end

function T = metricRow(methodName, side, signalName, unitText, metrics)
T = table( ...
    string(methodName), ...
    string(side), ...
    string(signalName), ...
    string(unitText), ...
    metrics.tStart_s, ...
    metrics.tEnd_s, ...
    metrics.nSamples, ...
    metrics.refRms, ...
    metrics.simRms, ...
    metrics.errorMean, ...
    metrics.errorRms, ...
    metrics.errorMaxAbs, ...
    metrics.errorMae, ...
    metrics.errorRelativeRms, ...
    metrics.errorRelativeMax, ...
    'VariableNames', { ...
        'method', 'side', 'signal', 'unit', ...
        'tStart_s', 'tEnd_s', 'nSamples', ...
        'refRms', 'simRms', 'errorMean', 'errorRms', ...
        'errorMaxAbs', 'errorMae', ...
        'errorRelativeRms', 'errorRelativeMax'});
end

function exportFigure(fig, outputFolder, baseName, savePng, saveFig, saveSvg, savePdf, resolution)
if savePng
    exportgraphics(fig, fullfile(outputFolder, baseName + ".png"), ...
        "Resolution", resolution);
end
if saveFig
    savefig(fig, fullfile(outputFolder, baseName + ".fig"));
end
if saveSvg
    exportgraphics(fig, fullfile(outputFolder, baseName + ".svg"), ...
        "ContentType", "vector");
end
if savePdf
    exportgraphics(fig, fullfile(outputFolder, baseName + ".pdf"), ...
        "ContentType", "vector");
end
end
