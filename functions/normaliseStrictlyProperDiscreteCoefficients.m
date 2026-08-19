function [b, a] = normaliseStrictlyProperDiscreteCoefficients( ...
    b, a, filterName)

b = b(:).';
a = a(:).';

if isempty(a) || a(1) == 0
    error('The %s denominator leading coefficient is invalid.', filterName);
end

b = b/a(1);
a = a/a(1);

if numel(b) < numel(a)
    b = [zeros(1, numel(a) - numel(b)), b];
elseif numel(b) > numel(a)
    error(['The discrete %s numerator order is higher than the ', ...
        'denominator order after discretisation.'], filterName);
end

b = realIfNumericallyReal(b);
a = realIfNumericallyReal(a);

directTolerance = 1e-9*max(1, norm(b, inf));

if abs(b(1)) > directTolerance
    error(['The discrete %s filter has direct feedthrough: ', ...
        '|b(1)| = %.12e. Increase the denominator order or use a ', ...
        'strictly-proper continuous fit.'], filterName, abs(b(1)));
end

b(1) = 0;

end



