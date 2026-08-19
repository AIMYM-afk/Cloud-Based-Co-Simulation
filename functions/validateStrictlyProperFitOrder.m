function validateStrictlyProperFitOrder( ...
    filterName, numeratorOrder, denominatorOrder)

if denominatorOrder <= numeratorOrder
    error(['The %s fit must be strictly proper. ', ...
        'Use denominator order > numerator order; got %d/%d.'], ...
        filterName, numeratorOrder, denominatorOrder);
end

end


