function values = readBaseVariables(variableNames)
values = struct();

for k = 1:numel(variableNames)
    variableName = variableNames{k};
    values.(variableName) = evalin('base', variableName);
end
end


