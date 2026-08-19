function response = symmetricLclTwoPortResponse( ...
    frequency, commonSeries, shuntBranch, fixedDelay)
%SYMMETRICLCLTWOPORTRESPONSE Frequency response of the symmetric LCL two-port.

frequency = frequency(:);
omega = 2*pi*frequency;
s = 1j*omega;

Zseries = commonSeries.R + s*commonSeries.L;
Yshunt = s*shuntBranch.C ./ ...
    (1 + s*shuntBranch.Rc*shuntBranch.C);

nFrequency = numel(frequency);
T = zeros(2, 2, nFrequency);
A = zeros(nFrequency, 1);
B = zeros(nFrequency, 1);
C = zeros(nFrequency, 1);
D = zeros(nFrequency, 1);

for k = 1:nFrequency
    T(:, :, k) = ...
        seriesABCD(Zseries(k)) * ...
        shuntABCD(Yshunt(k)) * ...
        seriesABCD(Zseries(k));

    A(k) = T(1, 1, k);
    B(k) = T(1, 2, k);
    C(k) = T(2, 1, k);
    D(k) = T(2, 2, k);
end

targetImaginary = omega*fixedDelay;
gamma = trackAcoshBranch(A, targetImaginary);
sinhGamma = sinh(gamma);

ZcFromB = B ./ sinhGamma;
ZcFromC = sinhGamma ./ C;
Zc = trackSignedComplexBranch(0.5*(ZcFromB + ZcFromC));

H = exp(-gamma);
Hr = exp(-gamma + s*fixedDelay);

response = struct();
response.frequency = frequency;
response.omega = omega;
response.s = s;
response.T = T;
response.A = A;
response.B = B;
response.C = C;
response.D = D;
response.gamma = gamma;
response.sinhGamma = sinhGamma;
response.ZcFromB = ZcFromB;
response.ZcFromC = ZcFromC;
response.Zc = Zc;
response.H = H;
response.Hr = Hr;
response.reciprocalError = abs(A.*D - B.*C - 1);
response.symmetryError = abs(A - D);
end
