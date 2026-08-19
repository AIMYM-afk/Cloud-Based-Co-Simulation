function transformer = readTransformerData(modelName,blockPath)
modelWasLoaded = bdIsLoaded(modelName);
load_system(modelName);

try
    winding1 = evalin('base',get_param(blockPath,'Winding1'));
    winding2 = evalin('base',get_param(blockPath,'Winding2'));
    nominal  = evalin('base',get_param(blockPath,'NominalPower'));

    RmExpression = readMaskParameterExpression( ...
        blockPath,{'Rm','MagnetizationResistance','MagnetisationResistance'});
    LmExpression = readMaskParameterExpression( ...
        blockPath,{'Lm','MagnetizationInductance','MagnetisationInductance'});

    RmPu = evalin('base',RmExpression);
    LmPu = evalin('base',LmExpression);
catch exception
    if ~modelWasLoaded
        close_system(modelName,0);
    end
    rethrow(exception);
end

if ~modelWasLoaded
    close_system(modelName,0);
end

transformer = struct( ...
    'nominalPower',nominal(1), ...
    'frequency',nominal(2), ...
    'windings',[winding1;winding2], ...
    'RmPu',RmPu, ...
    'LmPu',LmPu);
end


