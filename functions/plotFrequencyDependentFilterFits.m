function plotFrequencyDependentFilterFits(filterResult)

if isfield(filterResult, 'plot')
    f = filterResult.plot.frequency;
    plotData = filterResult.plot;
else
    f = filterResult.frequency;
    plotData = struct();
end

f = f(:);

fitMaxFrequency = readFitMaxFrequency(filterResult);

%% Zc magnitude

if isfield(filterResult, 'zcFitQuantity') && ...
        (strcmp(filterResult.zcFitQuantity, 'Zc_ohm') || ...
        strcmp(filterResult.zcFitQuantity, 'Zc_residual_ohm_plus_base_RL'))
    exactZc = readPlotField(plotData, filterResult, ...
        'ZcExact', 'ZcExact');
    continuousFitZc = readPlotField(plotData, filterResult, ...
        'ZcContinuousFit', 'ZcContinuousFit');
    discreteFitZc = readPlotField(plotData, filterResult, ...
        'ZcDiscreteFit', 'ZcDiscreteFit');
    if strcmp(filterResult.zcFitQuantity, 'Zc_residual_ohm_plus_base_RL')
        zcTitle = 'Z_c fitting: base RL + residual';
    else
        zcTitle = 'Z_c fitting';
    end
elseif isfield(filterResult, 'ZcNormalisedExact')
    exactZc = readPlotField(plotData, filterResult, ...
        'ZcNormalisedExact', 'ZcNormalisedExact');
    continuousFitZc = readPlotField(plotData, filterResult, ...
        'ZcContinuousFit', 'ZcContinuousFit');
    discreteFitZc = readPlotField(plotData, filterResult, ...
        'ZcDiscreteFit', 'ZcDiscreteFit');
    zcTitle = 'Z_c/Z_{inf} fitting';
else
    exactZc = readPlotField(plotData, filterResult, ...
        'ZrExact', 'ZrExact');
    continuousFitZc = readPlotField(plotData, filterResult, ...
        'ZrContinuousFit', 'ZrContinuousFit');
    discreteFitZc = readPlotField(plotData, filterResult, ...
        'ZrDiscreteFit', 'ZrDiscreteFit');
    zcTitle = 'Z_r fitting';
end

exactZc = exactZc(:);
continuousFitZc = continuousFitZc(:);
discreteFitZc = discreteFitZc(:);

figure('Name', zcTitle);

subplot(2,1,1);

semilogx( ...
    f, ...
    20*log10(max(abs(exactZc), eps)), ...
    'LineWidth', 1.3);

hold on;

semilogx( ...
    f, ...
    20*log10(max(abs(continuousFitZc), eps)), ...
    '--', ...
    'LineWidth', 1.3);

semilogx( ...
    f, ...
    20*log10(max(abs(discreteFitZc), eps)), ...
    ':', ...
    'LineWidth', 1.4);

grid on;
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
title(zcTitle);
legend('Exact', 'Continuous fit', 'Discrete fit', ...
    'Location', 'best');
markFitBandLimit(fitMaxFrequency);

subplot(2,1,2);

semilogx( ...
    f, ...
    unwrap(angle(exactZc))*180/pi, ...
    'LineWidth', 1.3);

hold on;

semilogx( ...
    f, ...
    unwrap(angle(continuousFitZc))*180/pi, ...
    '--', ...
    'LineWidth', 1.3);

semilogx( ...
    f, ...
    unwrap(angle(discreteFitZc))*180/pi, ...
    ':', ...
    'LineWidth', 1.4);

grid on;
xlabel('Frequency (Hz)');
ylabel('Phase (deg)');
markFitBandLimit(fitMaxFrequency);

%% Hr fitting

hrTitle = 'H_r fitting';
discreteHrLabel = 'Discrete fit';

if isfield(filterResult, 'hrLowPass') && ...
        isfield(filterResult.hrLowPass, 'enabled') && ...
        filterResult.hrLowPass.enabled
    hrTitle = 'H_r fitting: compensation + Butterworth';
    discreteHrLabel = 'Discrete fit + Butterworth';
end

figure('Name', hrTitle);

exactHr = readPlotField(plotData, filterResult, 'HrExact', 'HrExact');
continuousFitHr = readPlotField( ...
    plotData, filterResult, 'HrContinuousFit', 'HrContinuousFit');
discreteFitHr = readPlotField( ...
    plotData, filterResult, 'HrDiscreteFit', 'HrDiscreteFit');

exactHr = exactHr(:);
continuousFitHr = continuousFitHr(:);
discreteFitHr = discreteFitHr(:);

subplot(2,1,1);

semilogx( ...
    f, ...
    20*log10(max(abs(exactHr), eps)), ...
    'LineWidth', 1.3);

hold on;

semilogx( ...
    f, ...
    20*log10(max(abs(continuousFitHr), eps)), ...
    '--', ...
    'LineWidth', 1.3);

semilogx( ...
    f, ...
    20*log10(max(abs(discreteFitHr), eps)), ...
    ':', ...
    'LineWidth', 1.4);

grid on;
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
title(hrTitle);
legend('Exact', 'Continuous fit', discreteHrLabel, ...
    'Location', 'best');
markFitBandLimit(readHrFitMaxFrequency(filterResult));

subplot(2,1,2);

semilogx( ...
    f, ...
    unwrap(angle(exactHr))*180/pi, ...
    'LineWidth', 1.3);

hold on;

semilogx( ...
    f, ...
    unwrap(angle(continuousFitHr))*180/pi, ...
    '--', ...
    'LineWidth', 1.3);

semilogx( ...
    f, ...
    unwrap(angle(discreteFitHr))*180/pi, ...
    ':', ...
    'LineWidth', 1.4);

grid on;
xlabel('Frequency (Hz)');
ylabel('Phase (deg)');
markFitBandLimit(readHrFitMaxFrequency(filterResult));

%% Original-system two-port error

if isfield(plotData, 'continuousAbcdError') && ...
        isfield(plotData, 'discreteAbcdError')
    figure('Name', 'Original two-port vs fitted LCTLM error');

    semilogx( ...
        f, ...
        plotData.continuousAbcdError, ...
        '--', ...
        'LineWidth', 1.3);

    hold on;

    semilogx( ...
        f, ...
        plotData.discreteAbcdError, ...
        ':', ...
        'LineWidth', 1.4);

    grid on;
    xlabel('Frequency (Hz)');
    ylabel('Relative ABCD error');
    title('Original two-port vs fitted LCTLM');
    legend('Continuous fit', 'Discrete fit', ...
        'Location', 'best');
    markFitBandLimit(fitMaxFrequency);
end

if isfield(plotData, 'continuousTwoPortComparison') && ...
        isfield(plotData, 'discreteTwoPortComparison')
    plotTwoPortAbcdElementComparison( ...
        plotData.continuousTwoPortComparison, ...
        plotData.discreteTwoPortComparison, ...
        fitMaxFrequency);

    plotTwoPortAbcdElementError( ...
        plotData.continuousTwoPortComparison, ...
        plotData.discreteTwoPortComparison, ...
        fitMaxFrequency);
end
end


function value = readPlotField(plotData, filterResult, plotField, resultField)

if isfield(plotData, plotField)
    value = plotData.(plotField);
else
    value = filterResult.(resultField);
end
end


function fitMaxFrequency = readFitMaxFrequency(filterResult)

fitMaxFrequency = [];

if isfield(filterResult, 'settings') && ...
        isfield(filterResult.settings, 'fMax')
    fitMaxFrequency = filterResult.settings.fMax;
end

if isfield(filterResult, 'zcFitMaxFrequency')
    fitMaxFrequency = filterResult.zcFitMaxFrequency;
end
end


function fitMaxFrequency = readHrFitMaxFrequency(filterResult)

fitMaxFrequency = readFitMaxFrequency(filterResult);

if isfield(filterResult, 'hrFitMaxFrequency')
    fitMaxFrequency = filterResult.hrFitMaxFrequency;
end
end


function markFitBandLimit(fitMaxFrequency)

if isempty(fitMaxFrequency) || ~isfinite(fitMaxFrequency)
    return;
end

limits = ylim;
plot( ...
    [fitMaxFrequency, fitMaxFrequency], ...
    limits, ...
    'k-.', ...
    'LineWidth', 0.8, ...
    'HandleVisibility', 'off');
ylim(limits);
end


function plotTwoPortAbcdElementComparison( ...
    continuousComparison, discreteComparison, fitMaxFrequency)

f = continuousComparison.frequency(:);
labels = continuousComparison.elementLabels;
originalElements = normalisedAbcdElements( ...
    continuousComparison.originalNormalisedAbcd);
continuousElements = normalisedAbcdElements( ...
    continuousComparison.fittedNormalisedAbcd);
discreteElements = normalisedAbcdElements( ...
    discreteComparison.fittedNormalisedAbcd);

figure('Name', 'Original two-port vs fitted LCTLM ABCD magnitude');

for k = 1:4
    subplot(2, 2, k);
    semilogx(f, 20*log10(max(abs(originalElements(:, k)), eps)), ...
        'LineWidth', 1.3);
    hold on;
    semilogx(f, 20*log10(max(abs(continuousElements(:, k)), eps)), ...
        '--', 'LineWidth', 1.3);
    semilogx(f, 20*log10(max(abs(discreteElements(:, k)), eps)), ...
        ':', 'LineWidth', 1.4);
    grid on;
    xlabel('Frequency (Hz)');
    ylabel('Magnitude (dB)');
    title(labels{k});
    markFitBandLimit(fitMaxFrequency);
end

legend('Exact', 'Continuous fit', 'Discrete fit', ...
    'Location', 'best');

figure('Name', 'Original two-port vs fitted LCTLM ABCD phase');

for k = 1:4
    subplot(2, 2, k);
    semilogx(f, unwrap(angle(originalElements(:, k)))*180/pi, ...
        'LineWidth', 1.3);
    hold on;
    semilogx(f, unwrap(angle(continuousElements(:, k)))*180/pi, ...
        '--', 'LineWidth', 1.3);
    semilogx(f, unwrap(angle(discreteElements(:, k)))*180/pi, ...
        ':', 'LineWidth', 1.4);
    grid on;
    xlabel('Frequency (Hz)');
    ylabel('Phase (deg)');
    title(labels{k});
    markFitBandLimit(fitMaxFrequency);
end

legend('Exact', 'Continuous fit', 'Discrete fit', ...
    'Location', 'best');
end


function plotTwoPortAbcdElementError( ...
    continuousComparison, discreteComparison, fitMaxFrequency)

f = continuousComparison.frequency(:);
labels = continuousComparison.elementLabels;

figure('Name', 'Original two-port vs fitted LCTLM ABCD element error');

for k = 1:4
    subplot(2, 2, k);
    semilogy( ...
        f, ...
        max(continuousComparison.elementRelativeError(:, k), eps), ...
        '--', ...
        'LineWidth', 1.3);
    hold on;
    semilogy( ...
        f, ...
        max(discreteComparison.elementRelativeError(:, k), eps), ...
        ':', ...
        'LineWidth', 1.4);
    grid on;
    xlabel('Frequency (Hz)');
    ylabel('Relative error');
    title(labels{k});
    legend('Continuous fit', 'Discrete fit', ...
        'Location', 'best');
    markFitBandLimit(fitMaxFrequency);
end
end


function elements = normalisedAbcdElements(T)

nFrequency = size(T, 3);
elements = zeros(nFrequency, 4);

for k = 1:nFrequency
    elements(k, :) = [T(1, 1, k), T(1, 2, k), T(2, 1, k), T(2, 2, k)];
end
end
