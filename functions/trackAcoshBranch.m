function gamma = trackAcoshBranch(A, targetImaginary)
%TRACKACOSHBRANCH Select a continuous passive branch of acosh(A).
%
% acosh(A) is multi-valued through both sign and 2*pi*j shifts. The fixed
% delay extraction uses gamma = s*tau + gamma_r, so the selected branch is
% chosen to keep imag(gamma) close to omega*tau while preserving
% real(gamma) >= 0.

A = A(:);
targetImaginary = targetImaginary(:);

if numel(A) ~= numel(targetImaginary)
    error('A and targetImaginary must have the same number of samples.');
end

raw = acosh(A);
gamma = zeros(size(raw));

branchSpan = max(3, ceil(max(abs(targetImaginary))/(2*pi)) + 4);
branchNumbers = -branchSpan:branchSpan;
signs = [1, -1];
realTolerance = 1e-10;

for k = 1:numel(raw)
    candidates = zeros(numel(signs)*numel(branchNumbers), 1);
    n = 0;

    for signIndex = 1:numel(signs)
        for branchIndex = 1:numel(branchNumbers)
            n = n + 1;
            candidates(n) = ...
                signs(signIndex)*raw(k) + ...
                2j*pi*branchNumbers(branchIndex);
        end
    end

    passiveCandidates = candidates(real(candidates) >= -realTolerance);

    if isempty(passiveCandidates)
        passiveCandidates = candidates;
    end

    targetPhaseScore = abs(imag(passiveCandidates) - targetImaginary(k));

    if k == 1
        score = targetPhaseScore + ...
            0.01*abs(real(passiveCandidates));
    else
        predicted = gamma(k - 1) + ...
            1j*(targetImaginary(k) - targetImaginary(k - 1));
        continuityScore = abs(passiveCandidates - predicted);
        score = targetPhaseScore + ...
            0.05*continuityScore + ...
            0.001*abs(real(passiveCandidates));
    end

    [~, bestIndex] = min(score);
    selected = passiveCandidates(bestIndex);

    if real(selected) < 0 && abs(real(selected)) < realTolerance
        selected = 1j*imag(selected);
    end

    gamma(k) = selected;
end
end
