function hasAllVariables = baseHasVariables(variableNames)
hasAllVariables = true;

for k = 1:numel(variableNames)
    variableName = variableNames{k};

    if evalin('base', sprintf('exist(''%s'', ''var'')', variableName)) ~= 1
        hasAllVariables = false;
        return;
    end
end
end


