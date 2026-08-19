function value = trackSignedComplexBranch(rawValue)
%TRACKSIGNEDCOMPLEXBRANCH Keep the sign of a square-root-like response continuous.

rawValue = rawValue(:);
value = zeros(size(rawValue));

for k = 1:numel(rawValue)
    candidates = [rawValue(k); -rawValue(k)];

    if k == 1
        score = abs(imag(candidates)) - 1e-6*real(candidates);
    else
        score = abs(candidates - value(k - 1));
    end

    [~, bestIndex] = min(score);
    value(k) = candidates(bestIndex);
end
end
