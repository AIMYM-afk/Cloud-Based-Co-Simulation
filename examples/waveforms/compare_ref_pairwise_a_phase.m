%% Pairwise A-phase waveform comparison against the reference system
% This script creates separate A-phase voltage/current figures for both
% terminals. Each figure compares one interface method with the reference.

clear;
clc;
close all;

%% User Settings

SideNames = ["client", "server"];
TimeWindow = [0.095 0.15];  % [] for full common time range

MaxPlotPoints = 25000;
FigureVisible = "on";
SavePng = false;
SaveFig = true;
SaveSvg = true;
SavePdf = true;
ExportResolution = 600;

VoltageUnit = "V";
CurrentUnit = "A";
ReferenceYLimPadding = 1.08;

CompareSign.client.voltage = 1;
CompareSign.client.current = 1;
CompareSign.server.voltage = 1;
CompareSign.server.current = 1;

Style.FontName = "Arial";
Style.FontSize = 9;
Style.LabelFontSize = 13;
Style.LegendFontSize = 9;
Style.ReferenceLineWidth = 1.55;
Style.MethodLineWidth = 1.55;
Style.MethodLineStyle = "--";
Style.ItmDashLength = 3.5e-4;
Style.ItmDashGap = 1.2e-4;
Style.AxesLineWidth = 0.75;
Style.GridAlpha = 0.10;
Style.FigurePosition = [80 80 520 420];
Style.LegendLocation = "southwest";
Style.ReferenceColor = [0.0000 0.0000 0.0000];
Style.MethodColors.ITM = [0.0000 0.4470 0.7410];
Style.MethodColors.TLMTL = [0.0000 0.6000 0.5000];
Style.MethodColors.TLMG = [0.8500 0.3250 0.0980];

%% Locate Data Folder

scriptPath = mfilename("fullpath");
if strlength(scriptPath) == 0
    dataFolder = pwd;
else
    dataFolder = fileparts(scriptPath);
end

outputFolder = fullfile(dataFolder, "comparison_figures_pairwise_a_phase_12");
if ~exist(outputFolder, "dir")
    mkdir(outputFolder);
end

fprintf("Data folder:\n%s\n\n", dataFolder);

%% Define Pairwise Cases

cases = struct([]);

cases(end+1).key = "itm";
cases(end).label = "ITM";
cases(end).color = Style.MethodColors.ITM;
cases(end).lineStyle = "-";
cases(end).useShortDash = true;
cases(end).clientFile = "client_ITM.mat";
cases(end).serverFile = "server_ITM.mat";
cases(end).suffix = "ITM";

cases(end+1).key = "tlm_tl";
cases(end).label = "TLM-TL";
cases(end).color = Style.MethodColors.TLMTL;
cases(end).lineStyle = Style.MethodLineStyle;
cases(end).useShortDash = false;
cases(end).clientFile = firstExistingFile(dataFolder, ["client_TLM_TL.mat", "client_TLM.mat"]);
cases(end).serverFile = firstExistingFile(dataFolder, ["server_TLM_TL.mat", "server_TLM.mat"]);
cases(end).suffix = "TLM";

cases(end+1).key = "tlm_g";
cases(end).label = "TLM-G";
cases(end).color = Style.MethodColors.TLMG;
cases(end).lineStyle = Style.MethodLineStyle;
cases(end).useShortDash = false;
cases(end).clientFile = "client_TLM_G.mat";
cases(end).serverFile = "server_TLM_G.mat";
cases(end).suffix = "TLM";

%% Plot Pairwise A-Phase Comparisons

signalNames = ["voltage", "current"];
signalLabels = ["voltage", "current"];
unitTexts = [VoltageUnit, CurrentUnit];
nExported = 0;

for sideIndex = 1:numel(SideNames)
    sideName = SideNames(sideIndex);
    refData = loadSideData(fullfile(dataFolder, "ref_system.mat"), ...
        sideName, "ref");

    for signalIndex = 1:numel(signalNames)
        signalName = signalNames(signalIndex);
        signalLabel = signalLabels(signalIndex);
        unitText = unitTexts(signalIndex);

        for k = 1:numel(cases)
            methodData = loadSideData( ...
                fullfile(dataFolder, cases(k).(sideName + "File")), ...
                sideName, cases(k).suffix);

            nExported = nExported + 1;
            figName = sprintf('%s A-phase %s: %s vs Reference', ...
                char(sideLabel(sideName)), char(signalLabel), ...
                char(cases(k).label));
            fig = createPairFigure(figName, FigureVisible, Style);
            ax = axes(fig);

            plotPairSignal(ax, refData.(signalName), ...
                methodData.(signalName), cases(k), sideName, signalName, ...
                1, TimeWindow, MaxPlotPoints, CompareSign, unitText, ...
                ReferenceYLimPadding, Style);

            baseName = string(sprintf('%02d_%s_a_phase_%s_%s_vs_ref', ...
                nExported, char(sideName), char(signalName), ...
                char(cases(k).key)));
            exportFigure(fig, outputFolder, baseName, SavePng, SaveFig, ...
                SaveSvg, SavePdf, ExportResolution);
        end
    end
end

fprintf("Saved %d separate pairwise A-phase figures to:\n%s\n", ...
    nExported, outputFolder);

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

function sideData = loadSideData(filePath, sideName, suffix)
if ~isfile(filePath)
    error("Required file not found: %s", filePath);
end

S = load(filePath);
sideData = struct();
sideData.voltage = readRequiredSignal(S, sideName + "_voltage_" + suffix, filePath);
sideData.current = readRequiredSignal(S, sideName + "_current_" + suffix, filePath);
end

function signal = readRequiredSignal(S, variableName, filePath)
if ~isfield(S, variableName)
    error("Variable %s was not found in %s.", variableName, filePath);
end
signal = S.(variableName);
end

function fig = createPairFigure(figName, visibleMode, Style)
fig = figure( ...
    "Name", figName, ...
    "Visible", visibleMode, ...
    "Color", "w", ...
    "Renderer", "painters", ...
    "Units", "pixels", ...
    "Position", Style.FigurePosition);
end

function plotPairFigure(fig, refData, methodData, methodCase, sideName, ...
    timeWindow, maxPlotPoints, compareSign, voltageUnit, currentUnit, ...
    yPadding, Style)

layout = tiledlayout(fig, 2, 1, ...
    "TileSpacing", "compact", ...
    "Padding", "compact");

axVoltage = nexttile(layout);
plotPairSignal(axVoltage, refData.voltage, methodData.voltage, methodCase, ...
    sideName, "voltage", 1, timeWindow, maxPlotPoints, compareSign, ...
    voltageUnit, yPadding, Style);

axCurrent = nexttile(layout);
plotPairSignal(axCurrent, refData.current, methodData.current, methodCase, ...
    sideName, "current", 1, timeWindow, maxPlotPoints, compareSign, ...
    currentUnit, yPadding, Style);

linkaxes([axVoltage, axCurrent], "x");
end

function plotPairSignal(ax, refTs, methodTs, methodCase, sideName, ...
    signalName, channel, timeWindow, maxPlotPoints, compareSign, unitText, ...
    yPadding, Style)

[tRef, refY] = selectTimeseriesChannel(refTs, channel, timeWindow);
[t, refAligned, methodY] = alignTimeseriesToReference( ...
    refTs, methodTs, channel, timeWindow);

scale = getScale(compareSign, sideName, signalName);
methodY = scale * methodY;
idxRef = plotIndex(numel(tRef), maxPlotPoints);
idx = plotIndex(numel(t), maxPlotPoints);

hold(ax, "on");
refHandle = plot(ax, tRef(idxRef), refY(idxRef), ...
    "Color", Style.ReferenceColor, ...
    "LineStyle", "-", ...
    "LineWidth", Style.ReferenceLineWidth);
methodHandle = plotMethodLine(ax, t(idx), methodY(idx), methodCase, Style);

formatWaveAxes(ax, unitText, Style);
applyTimeWindowXLim(ax, timeWindow);
applyPairYLim(ax, refAligned, methodY, yPadding);
applyLegendStyle(legend(ax, [refHandle, methodHandle], ...
    ["Reference", methodCase.label], ...
    "Location", Style.LegendLocation, ...
    "FontName", Style.FontName, ...
    "FontSize", Style.LegendFontSize));
end

function h = plotMethodLine(ax, t, y, methodCase, Style)
if isfield(methodCase, "useShortDash") && methodCase.useShortDash
    [t, y] = buildShortDashSeries(t, y, ...
        Style.ItmDashLength, Style.ItmDashGap);
end

h = plot(ax, t, y, ...
    "Color", methodCase.color, ...
    "LineStyle", methodCase.lineStyle, ...
    "LineWidth", Style.MethodLineWidth);
end

function [tDash, yDash] = buildShortDashSeries(t, y, dashLength, dashGap)
if numel(t) < 2 || dashLength <= 0 || dashGap <= 0
    tDash = t;
    yDash = y;
    return;
end

dashPeriod = dashLength + dashGap;
phase = mod(t - t(1), dashPeriod);
keep = phase <= dashLength;

tDash = t(:);
yDash = y(:);
yDash(~keep(:)) = NaN;
end

function scale = getScale(compareSign, sideName, signalName)
scale = compareSign.(sideName).(signalName);
end

function label = sideLabel(sideName)
if sideName == "client"
    label = "Client";
else
    label = "Server";
end
end

function formatWaveAxes(ax, yLabelText, Style)
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

function applyPairYLim(ax, refY, methodY, padding)
amplitude = max(abs([refY(:); methodY(:)]));
if ~isfinite(amplitude) || amplitude <= 0
    return;
end

ylim(ax, padding * [-amplitude, amplitude]);
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

function exportFigure(fig, outputFolder, baseName, savePng, saveFig, ...
    saveSvg, savePdf, resolution)

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
