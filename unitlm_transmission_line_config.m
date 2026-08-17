function [params, DPL, line] = unitlm_transmission_line_config()
%UNITLM_TRANSMISSION_LINE_CONFIG Shared uniTLM communication and line data.
%
% Edit this file when tuning the physical line or the interface delay.
% Both fit_non_heaviside_line_rational.m and initialize_unitlm_microgrid.m
% read these values.

%% Communication / interface parameters

params.sampleTime = 5e-7;    % Simulation/interface sample time, s
params.n          = 6;       % Number of exchanged signals
params.batchSteps = 200;     % Number of samples per TCP batch
params.delay      = params.batchSteps*params.sampleTime;

%% Distributed transmission-line parameters

DPL.N    = 3;                % Number of phases
DPL.freq = 50;               % Parameter specification frequency, Hz
DPL.R    = [0.115, 0.40];    % [R1 R0], Ohm/km, 66 kV overhead line
DPL.L    = [1.20e-3, 3.60e-3]; % [L1 L0], H/km
DPL.C    = [11e-9, 6e-9];    % [C1 C0], F/km
DPL.G    = 0;                % Positive-sequence shunt conductance, S/km

% Original physical line length in the reference system.
DPL.originalLength = 50;     % km

% Scaling from communication delay to the line portion represented by the
% explicit TLM delay. Keep at 1 for a direct high-frequency delay match.
DPL.delayLengthScale = 1;

%% Derived line quantities

DPL.velocityHF = 1/sqrt(DPL.L(1)*DPL.C(1));   % km/s
DPL.communicationLength = ...
    DPL.delayLengthScale*params.delay*DPL.velocityHF;
DPL.length = DPL.originalLength - DPL.communicationLength;

line.R = DPL.R(1);
line.L = DPL.L(1);
line.C = DPL.C(1);
line.G = DPL.G;
line.nDelay = params.batchSteps;
line.delay = params.delay;
line.velocityHF = 1/sqrt(line.L*line.C);
line.delayEquivalentLength = line.delay*line.velocityHF;
line.Zinf = sqrt(line.L/line.C);
end
