function systemStable = stabiliseContinuousTransferFunction(systemInput)
% Reflect unstable fitted poles into the left-half plane while retaining
% the fitted zeros and gain.

[z, p, k] = zpkdata(systemInput, 'v');

unstable = real(p) >= 0;

p(unstable) = -max(abs(real(p(unstable))), 1e-9) + ...
    1j*imag(p(unstable));

systemStable = minreal(zpk(z, p, k), 1e-10);

end


