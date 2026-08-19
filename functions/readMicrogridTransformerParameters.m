function transformer = readMicrogridTransformerParameters()
modelName = 'Microgrid';
transformerBlock = [modelName, '/T_vsc_66kV_0p38kV'];
modelWasLoaded = bdIsLoaded(modelName);

load_system(modelName);

try
    winding1 = evalin('base', get_param(transformerBlock, 'Winding1'));
    winding2 = evalin('base', get_param(transformerBlock, 'Winding2'));
    nominal = evalin('base', get_param(transformerBlock, 'NominalPower'));
catch exception
    if ~modelWasLoaded
        close_system(modelName, 0);
    end

    rethrow(exception);
end

if ~modelWasLoaded
    close_system(modelName, 0);
end

validateattributes(winding1, ...
    {'numeric'}, {'row','numel',3,'real','finite','positive'});

validateattributes(winding2, ...
    {'numeric'}, {'row','numel',3,'real','finite','positive'});

validateattributes(nominal, ...
    {'numeric'}, {'row','numel',2,'real','finite','positive'});

transformer = struct( ...
    'nominalPower', nominal(1), ...
    'frequency', nominal(2), ...
    'windings', [winding1; winding2]);
end


