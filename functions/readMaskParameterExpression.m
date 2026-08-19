function expression = readMaskParameterExpression(blockPath,candidateNames)
for k = 1:numel(candidateNames)
    try
        expression = get_param(blockPath,candidateNames{k});
        if ~isempty(expression)
            return;
        end
    catch
    end
end

error('Could not find transformer mask parameter: %s', ...
    strjoin(candidateNames,', '));
end


