function [bS, aS] = scaledPolynomialToPhysicalS( ...
    bQ, aQ, wScale)
% Convert a transfer function expressed in q=s/wScale into a transfer
% function expressed directly in s.
%
% If
%
%   B(q) = b_n q^n + ... + b_0,
%
% then
%
%   B(s/wScale)
%   = b_n s^n/wScale^n + ... + b_0.

bQ = realIfNumericallyReal(bQ(:).');
aQ = realIfNumericallyReal(aQ(:).');

bOrder = numel(bQ)-1;
aOrder = numel(aQ)-1;

bPowers = bOrder:-1:0;
aPowers = aOrder:-1:0;

bS = bQ ./ (wScale.^bPowers);
aS = aQ ./ (wScale.^aPowers);

% Normalise denominator.
bS = bS/aS(1);
aS = aS/aS(1);

end


