function Zinf = selectCharacteristicImpedance(Zc, frequency)
%SELECTCHARACTERISTICIMPEDANCE Pick a positive real Zinf from Zc samples.

Zc = Zc(:);
frequency = frequency(:);

if numel(Zc) ~= numel(frequency)
    error('Zc and frequency must have the same number of samples.');
end

valid = isfinite(real(Zc)) & isfinite(imag(Zc)) & abs(Zc) > 0;

if ~any(valid)
    error('Cannot select Zinf because all Zc samples are invalid.');
end

validFrequency = frequency(valid);
validZc = Zc(valid);

highFrequencyThreshold = 0.5*max(validFrequency);
highFrequencyBand = validFrequency >= highFrequencyThreshold;

if nnz(highFrequencyBand) < 5
    highFrequencyBand = true(size(validFrequency));
end

candidate = median(abs(validZc(highFrequencyBand)));

if ~isfinite(candidate) || candidate <= 0
    candidate = median(abs(validZc));
end

if ~isfinite(candidate) || candidate <= 0
    error('Selected Zinf is invalid.');
end

Zinf = real(candidate);
end
