function config = cosim_network_config()
%COSIM_NETWORK_CONFIG Shared TCP settings for all published interfaces.
%
% Keep this file identical on both computers. Usually only serverIp needs
% to be changed. The server listens on all local interfaces.

config.serverIp = '100.72.6.122';
config.listenAddress = '0.0.0.0';

config.clientToServerPort = 30011;
config.serverToClientPort = 30010;
config.timeoutSeconds = 30;

config.tlmBufferSize = 20000;
config.itmBufferSize = 10000;
end
