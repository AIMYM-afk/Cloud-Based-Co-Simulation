function release_two_pc_tcp_ports()
%RELEASE_TWO_PC_TCP_PORTS Close stale tcpip objects for the co-simulation ports.

ports = [30010, 30011];
fprintf('Releasing MATLAB tcpip objects on ports 30010 and 30011...\n');

try
    objs = instrfindall('Type', 'tcpip');
catch ME
    warning('release_two_pc_tcp_ports:InstrFindFailed', ...
        'Could not query instrument objects: %s', ME.message);
    return;
end

closedCount = 0;
for k = 1:numel(objs)
    objectPorts = getTcpObjectPorts(objs(k));

    if any(ismember(objectPorts, ports))
        try
            if strcmp(get(objs(k), 'Status'), 'open')
                fclose(objs(k));
            end
        catch
        end
        try
            delete(objs(k));
        catch
        end
        closedCount = closedCount + 1;
    end
end

clear global t_server_receive t_server_send t_client_receive t_client_send
clear global t_tlm_server_receive t_tlm_server_send t_tlm_client_receive t_tlm_client_send
fprintf('Released %d tcpip object(s).\n', closedCount);
end

function ports = getTcpObjectPorts(obj)
ports = [];

try
    ports(end + 1) = get(obj, 'RemotePort');
catch
end

try
    ports(end + 1) = get(obj, 'LocalPort');
catch
end

ports = ports(~isnan(ports));
end
