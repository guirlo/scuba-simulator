# Scuba Simulator

This repository contains a Simulink and Simscape project for modeling the
vertical dynamics and gas-system behavior of a scuba diver. An overview of the
project is available in the accompanying Simulink blog post:
<https://blogs.mathworks.com/simulink/2026/07/02/my-scuba-diving-simulator/>.
The repository is organized around a reusable plant model, custom Simscape
components, supporting simulation harnesses, MATLAB scripts, and project
documentation.

The central model is `models/Scuba_Diver.slx`, which represents a 1-DOF scuba
diver plant with Simulink interfaces for buoyancy-control commands and lung
volume input, and outputs for depth and vertical velocity. The plant combines a
custom gas domain with translational mechanics to represent the interaction
between gas storage, regulation, breathing, BCD inflation and purge behavior,
buoyancy, drag, and diver mass properties.

The custom physical modeling implementation is defined under `+scuba/`. This
includes the diver body component in `+scuba/DiverBody.ssc`, the custom gas
domain in `+scuba/+gas/underwaterGas.ssc`, and the gas-system elements in
`+scuba/+gas/+elements/`, including the tank, gas volume, first-stage and
second-stage regulators, lungs, BCD bladder, inflate and purge valves,
overpressure relief valve, ambient reference, and related assets.

The `models/` directory contains the reusable plant and associated harness
models:

- `models/Scuba_Diver.slx`: reusable plant model
- `models/descent_test.slx`: closed-loop harness with Stateflow-based depth
  control logic
- `models/breath_test.slx`: harness for breathing and gas-consumption studies
- `models/fullDiveHarness.slx`: harness for fuller dive-sequence experiments
- `models/scuba_lib.slx`: generated Simscape library built from the `.ssc`
  source files

The `data/` directory contains the project data dictionary:

- `data/scubaParams.sldd`: Simulink data dictionary used by the models

The `scripts/` directory contains MATLAB utilities for project support and
library generation:

- `scripts/rebuildScubaLib.m`: rebuilds the Simscape library into
  `models/scuba_lib.slx`

The `tests/` directory contains MATLAB simulation scripts used to run and plot
selected studies:

- `tests/testDepth.m`: runs `breath_test` across multiple depths and plots tank
  pressure behavior
- `tests/testDescent.m`: runs `descent_test` across multiple parameter values
  and plots depth response

The `docs/` directory contains project documentation, including specifications
and development notes. In particular,
`docs/specs/plant-models/scuba-diver/` contains system, architecture,
controller, and implementation documents related to the scuba diver plant
model.

## Repository Structure

- [`models/`](models/): plant and harness models
- [`+scuba/`](+scuba/): custom Simscape source code and assets
- [`data/`](data/): Simulink data dictionary
- [`scripts/`](scripts/): MATLAB support scripts
- [`tests/`](tests/): MATLAB simulation-study scripts
- [`docs/`](docs/): specifications and project documentation

## Getting Started

1. Open `scuba-buyancy.prj` in MATLAB to load the project.
2. Run [`scripts/rebuildScubaLib.m`](scripts/rebuildScubaLib.m) if the custom
   Simscape library needs to be regenerated from source.
3. Open `models/descent_test.slx`, `models/breath_test.slx`, or
   `models/fullDiveHarness.slx` to run a harness model.
4. Open `models/Scuba_Diver.slx` to inspect or reuse the standalone plant.
