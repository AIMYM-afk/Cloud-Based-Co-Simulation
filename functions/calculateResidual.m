function residual = calculateResidual( ...
    x, ...
    s, ...
    tau, ...
    Toriginal, ...
    Zbase, ...
    frequencyWeight, ...
    lineFirst)

q = exp(x(:));

Rline = q(1);
Gline = q(2);
Lline = q(3);

Rr  = q(4);
Lr  = q(5);
Rcr = q(6);
Cr  = q(7);

Cline = tau^2/Lline;

nFrequency = numel(s);

% Four complex ABCD elements give eight real residuals.
residual = zeros(8*nFrequency,1);

for k = 1:nFrequency
    sk = s(k);

    [Tline, ~, ~] = ...
        lineABCD(sk, Rline, Lline, Gline, Cline);

    Zremaining = Rr + sk*Lr;

    Yremaining = ...
        sk*Cr/(1 + sk*Rcr*Cr);

    Tremaining = ...
        seriesABCD(Zremaining)*shuntABCD(Yremaining);

    if lineFirst
        Tnew = Tline*Tremaining;
    else
        Tnew = Tremaining*Tline;
    end

    T0n = normaliseABCD( ...
        Toriginal(:,:,k), Zbase);

    Tnn = normaliseABCD( ...
        Tnew, Zbase);

    errorMatrix = T0n - Tnn;

    weightScale = sqrt(frequencyWeight(k));

    index = (k-1)*8 + (1:8);

    residual(index) = weightScale*[ ...
        real(errorMatrix(:)); ...
        imag(errorMatrix(:))];
end

invalid = ~isfinite(residual);

if any(invalid)
    residual(invalid) = 1e12;
end

end


%% ========================================================================
% Transmission-line ABCD matrix
% ========================================================================

