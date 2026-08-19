function [T, gamma, Zc] = lineABCD(s, R, L, G, C)
% Total-parameter RLGC line with normalised length equal to one.
%
%   Z(s) = R + sL
%   Y(s) = G + sC
%
%   gamma = sqrt(ZY)
%   Zc    = sqrt(Z/Y)
%
% The branch of gamma is selected to give passive attenuation.

Z = R + s*L;
Y = G + s*C;

gamma = sqrt(Z*Y);

if real(gamma) < 0
    gamma = -gamma;
elseif abs(real(gamma)) < 1e-14 && imag(gamma) < 0
    gamma = -gamma;
end

if abs(gamma) > 1e-15
    Zc = Z/gamma;
else
    Zc = sqrt(Z/Y);
end

T = [ ...
    cosh(gamma),       Zc*sinh(gamma); ...
    sinh(gamma)/Zc,    cosh(gamma)];

end


%% ========================================================================
% Series and shunt ABCD matrices
% ========================================================================

