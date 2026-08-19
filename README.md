# Fixed-delay microgrid co-simulation models

This repository contains the reproducible MATLAB/Simulink version of a
5 MW, 690 V / 66 kV microgrid test system and three two-computer interface
implementations. All published models were saved with MATLAB R2025b Update 5.

## Included models

| Case | Server model | Client model | Purpose |
| --- | --- | --- | --- |
| Reference | `Microgrid.slx` | - | Monolithic reference system |
| TLM-TL | `Microgrid_uniTLM_server.slx` | `Microgrid_uniTLM_client.slx` | Frequency-dependent physical-line TLM interface |
| TLM-G | `Microgrid_LCTLM_server.slx` | `Microgrid_LCTLM_client.slx` | Generalised TLM interface obtained from the LCL/transformer two-port fit |
| ITM | `Microgrid_ITM_server_new.slx` | `Microgrid_ITM_client_new.slx` | Ideal-transformer-method comparison |

The older `Microgrid_TLM_client/server` models are intentionally not included:
they still use the obsolete 10 kW initialization and are not parameter-consistent
with this 5 MW test system.

## Requirements

- MATLAB and Simulink R2025b Update 5 (recommended)
- Simscape Electrical / Specialized Power Systems
- Instrument Control Toolbox (`tcpip` and `instrfindall`)
- Control System Toolbox
- Signal Processing Toolbox
- Optimization Toolbox (only needed when rerunning the interface optimization)

The models use the legacy Instrument Control Toolbox `tcpip` API. Both
computers must use a MATLAB release that still supports this API.

## Quick start

Clone or copy the complete folder, make it the MATLAB current folder, then run:

```matlab
startup_project
validate_project
```

To run the monolithic reference system:

```matlab
open_system('Microgrid')
sim('Microgrid')
```

Simulation callbacks write generated results to `result/`.

## Two-computer co-simulation

1. Copy the same repository version to both computers.
2. Edit `cosim_network_config.m` on both computers and set `serverIp` to the
   server computer's reachable IPv4 address. Keep the ports identical.
3. Allow inbound TCP traffic on ports 30010 and 30011 on the server computer.
4. Run `startup_project` on both computers.
5. Open and start the selected `*_server.slx` model first. It waits for TCP
   connections.
6. Open and start the matching `*_client.slx` model second.
7. Stop both simulations before changing method or restarting a failed run.
   Use `release_two_pc_tcp_ports` if stale MATLAB TCP objects remain.

Do not mix a client and server from different rows of the model table. The two
computers must use the same sample time, batch size, filter file, and model set.

Current communication settings are:

| Interface | Electrical step | Samples per exchange | Interface interval |
| --- | ---: | ---: | ---: |
| TLM-TL / TLM-G | 0.5 us | 200 | 100 us |
| ITM | 0.5 us base step | 100 | 50 us |

The TLM parameters are defined in `unitlm_transmission_line_config.m`. Network
addresses and TCP ports are defined only in `cosim_network_config.m` in this
published version.

TLM-TL and TLM-G callbacks both produce the generic names `client_TLM.mat` and
`server_TLM.mat`. Archive each completed run before starting the other method:

```matlab
archive_run_results('TLM-TL')
% Run the TLM-G pair, then:
archive_run_results('TLM-G')
```

Copy the server-side MAT file into the same local `result/` folder as the
client-side MAT file before archiving. Use `Reference` and `ITM` in the same
function after those runs. The helper
collects all four cases in `result/comparison/`, applies the plot-script naming
convention, and copies both comparison scripts into that folder.

## Rebuilding fitted interface parameters

The checked-in `optimised_frequency_dependent_line_filters.mat` is the parameter
set used by the published TLM-G models. It lets another user run the models
without repeating the fit.

After changing the reference LCL, transformer, communication delay, sample time,
or fitting orders, rebuild the file with:

```matlab
startup_project
heaviside_line_equivalent_optimise
```

`optimised_tlm_interface_config.m` contains the generalized-interface fit band,
orders, iteration settings, and Butterworth cutoff. The TLM-G model initializer
loads the generated MAT file through `initialise_optimised_tlm_interface.m`.

For the physical transmission-line fit, use:

```matlab
fit_non_heaviside_line_rational
```

Its settings are shared by `unitlm_fit_config.m` and
`unitlm_transmission_line_config.m`.

## Example data and plots

`examples/waveforms/` contains compact waveform files for the reference, ITM,
TLM-TL, and TLM-G cases. They retain the 0.09-0.16 s window and every tenth
original sample. The full raw MAT files are 100-220 MB each and are omitted so
the repository remains compatible with GitHub's normal file-size limit.

Run either plotting script from MATLAB:

```matlab
run('examples/waveforms/compare_ref_vs_unitlm_waveforms.m')
run('examples/waveforms/compare_ref_pairwise_a_phase.m')
```

To regenerate compact examples from a folder containing the full raw files:

```matlab
export_example_data(rawFolder, ...
    fullfile(pwd, 'examples', 'waveforms'), [0.09 0.16], 10)
```

`examples/timing/` contains the latest small client/server timing summaries.
`comparison_error_metrics_4method.csv` records the existing four-method error
summary.

## Repository layout

```text
.
|-- Microgrid*.slx                    Current reference and co-simulation models
|-- *_config.m                        Shared physical, fit, and network settings
|-- Client_co*.m / Server_co*.m       MATLAB S-Functions for TCP exchange
|-- functions/                        Generalized-line fitting helpers
|-- examples/waveforms/               Compact benchmark data and plot scripts
|-- examples/timing/                  Timing-probe CSV examples
|-- scripts/                          Data-export utility
|-- result/                           Generated local simulation output
|-- startup_project.m                 Path and environment setup
`-- validate_project.m                Reproducibility smoke test
```

Generated Simulink caches, local waveform logs, figures, and result files are
excluded by `.gitignore`.
