function value = realIfNumericallyReal(value)

imaginaryScale = max(abs(imag(value)));

realScale = max(1, max(abs(real(value))));

if imaginaryScale < 1e-10*realScale
    value = real(value);
end

end

