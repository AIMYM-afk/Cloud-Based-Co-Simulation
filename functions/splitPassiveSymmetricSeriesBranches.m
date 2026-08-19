function [common, separated, decision] = splitPassiveSymmetricSeriesBranches( ...
    terminal1, terminal2, comparisonFrequency)
%SPLITPASSIVESYMMETRICSERIESBRANCHES Split two RL branches passively.
%
% The common branch is used on both sides of the symmetric two-port. Any
% extra positive R/L is left as a separated terminal branch.

tolerance = 1e-12;

terminal1NoLarger = ...
    terminal1.R <= terminal2.R*(1 + tolerance) && ...
    terminal1.L <= terminal2.L*(1 + tolerance);

terminal2NoLarger = ...
    terminal2.R <= terminal1.R*(1 + tolerance) && ...
    terminal2.L <= terminal1.L*(1 + tolerance);

common = struct();

if terminal1NoLarger
    common.R = terminal1.R;
    common.L = terminal1.L;
    selectedSide = 'terminal1';
    splitMode = 'single-side-minimum';
elseif terminal2NoLarger
    common.R = terminal2.R;
    common.L = terminal2.L;
    selectedSide = 'terminal2';
    splitMode = 'single-side-minimum';
else
    common.R = min(terminal1.R, terminal2.R);
    common.L = min(terminal1.L, terminal2.L);
    selectedSide = 'componentwise';
    splitMode = 'componentwise-passive-minimum';
end

separated = struct();
separated.terminal1 = struct( ...
    'R', max(terminal1.R - common.R, 0), ...
    'L', max(terminal1.L - common.L, 0));
separated.terminal2 = struct( ...
    'R', max(terminal2.R - common.R, 0), ...
    'L', max(terminal2.L - common.L, 0));

omega = 2*pi*comparisonFrequency;
zTerminal1 = terminal1.R + 1j*omega*terminal1.L;
zTerminal2 = terminal2.R + 1j*omega*terminal2.L;
zCommon = common.R + 1j*omega*common.L;

decision = struct();
decision.splitMode = splitMode;
decision.selectedSide = selectedSide;
decision.comparisonFrequency = comparisonFrequency;
decision.terminal1Magnitude = abs(zTerminal1);
decision.terminal2Magnitude = abs(zTerminal2);
decision.commonMagnitude = abs(zCommon);
decision.terminal1NoLarger = terminal1NoLarger;
decision.terminal2NoLarger = terminal2NoLarger;
decision.usedComponentwiseMinimum = strcmp(splitMode, ...
    'componentwise-passive-minimum');
end
