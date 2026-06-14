# Project Handoff — Scuba Buoyancy Simulation

**Date:** 2026-06-14  
**Project:** scuba-buoyancy  
**Location:** `L:\Projects\scuba`  
**MATLAB version:** R2026a  
**Status:** Major refactor complete. Architecture simplified: DiverBody replaces 3 separate mechanical components; P_amb computed locally per component (no domain-level propagation); Lungs/BCD/GasTank have translational ports with direct force output. Old top-level model (`scuba_buoyancy_sim.slx`) and test suite removed. New primary model is `descent_test.slx` with Stateflow depth controller.

---

## Project Goal

Build a 1D vertical buoyancy simulation of a scuba diver in Simulink/Simscape that:
- Models breath-by-breath gas consumption through a realistic equipment topology (tank → regulators → lungs/BCD → water)
- Uses a **custom Simscape gas domain** with conserving physical connections (pressure across, molar flow through)
- Simulates BCD inflate/purge and depth-dependent gas behavior (Boyle's law)
- Supports Air and Nitrox 32% gas mixes
- Validates physics against analytical solutions

---

## Architecture Summary

| Layer | Technology | Responsibility |
|-------|-----------|----------------|
| Plant — Gas | Custom Simscape domain (`+scuba/+gas/`) | Physical gas flow: tank, regulators, lungs, BCD, valves |
| Plant — Mechanical | Simscape Translational (Position-Based, beta=90 deg) | 1-DOF vertical motion, buoyancy force, drag |
| Coupling | Translational port on gas components | Each gas component (Lungs, BCDBladder, GasTank, regulators, AmbientRef) has a translational port `R`; computes P_amb from `R.x` and applies forces (buoyancy, weight) directly |
| Control | Stateflow | Depth controller state machine (drop → float → done) |

Key design principle: Gas flow is driven by **pressure differentials**, not command signals. The 2nd stage regulator opens physically when the diver's breathing effort creates suction. The BCD fills because opening the inflate valve exposes it to intermediate pressure.

**Coupling approach (current):** No separate coupling layer. Each gas component that needs ambient pressure has a `foundation.translational.translational` node and reads depth from `R.x`. Components that produce buoyancy (Lungs, BCDBladder) or weight (GasTank) apply force directly through that same port. `DiverBody` provides combined body mass + body buoyancy + hydrodynamic drag as a single block.

---

## Current Progress

### Architecture Refactoring (post-Phase 8)

The project underwent a major simplification from the original multi-phase implementation:

**Removed (old architecture):**
- `AmbientPressure.ssc` — replaced by translational ports on each component
- `BuoyancyForceSource.ssc` — replaced by per-component buoyancy forces (Lungs, BCDBladder)
- `HydrodynamicDrag.ssc` — absorbed into `DiverBody.ssc`
- `models/scuba_buoyancy_sim.slx` — replaced by harness + Scuba_Diver plant
- `bcd_buoyancy_harness.slx`, `bcd_buoyancy_with_valve_harness.slx` — superseded
- Entire test suite (`tests/`) — 9 test classes + ScubaTestHelper removed
- `scripts/build_library.m` — replaced by `scripts/rebuildScubaLib.m`
- `shutdown.m` — removed
- `scuba_lib.slx` at root — moved to `models/scuba_lib.slx`

**Added (new architecture):**
- `+scuba/DiverBody.ssc` — combined mass + body buoyancy + quadratic drag, single translational port
- `+scuba/+gas/+elements/OverpressureReliefValve.ssc` — passive OPRV for BCD overpressure
- `+scuba/+gas/+elements/IdealMolarFlowSource.ssc` — test utility (flow source)
- `+scuba/+gas/+elements/IdealPressureSource.ssc` — test utility (pressure source)
- `models/Scuba_Diver.slx` — reusable plant model (3 inputs, 2 outputs)
- `scripts/rebuildScubaLib.m` — builds library to `models/` folder
- Translational port (`R`) added to: GasTank, FirstStageRegulator, SecondStageRegulator, Lungs, BCDBladder, AmbientReference

**Key architectural changes:**
1. **P_amb removed from gas domain** — was an across variable; now each component computes `P_amb = P_atm + rho_water * R.gravity * R.x` locally from its translational port
2. **Buoyancy distributed** — Lungs applies lung buoyancy force; BCDBladder applies BCD buoyancy force; DiverBody applies body buoyancy; GasTank applies gas weight
3. **Surface hard-stop implemented** — `Surface and Bottom` subsystem with spacer+hard-stop pairs (previously deferred)
4. **Stateflow depth controller** — simple 3-state (drop → float → done) replaces the two-tier MATLAB Function block + breathing bias approach
5. **`let/in/end` replaced with `intermediates`** — all Simscape components updated to modern syntax

### Current Model State

The harness (`descent_test.slx`) runs successfully with:
- Stateflow chart commanding descent to target depth, BCD inflation to achieve neutral buoyancy, then hold
- Full gas circuit: Tank → 1st Stage → Hose Volume → 2nd Stage → Lungs → Exhale → Ambient, with BCD branch (InflateValve → OPRV → PurgeValve → Bladder)
- Mechanical: DiverBody + Weights + hard stops + Initial Depth + MotionSensor
- Stop conditions at depth < 0.1m or > 45m

---

## Implementation Status

| Area | Status |
|------|--------|
| Custom gas domain | **Complete** — `underwaterGas.ssc` |
| Gas components (tank, regulators, lungs, BCD, valves) | **Complete** — 12 active components |
| Mechanical coupling (DiverBody) | **Complete** — single combined block |
| Depth controller | **Complete** — Stateflow in harness |
| Surface/bottom hard stops | **Complete** — spacer+hard-stop pairs |
| OPRV | **Complete** — passive overpressure relief |
| Test suite | **Removed** — needs rewrite for new architecture |
| Dashboard / visualization | **Not started** |
| Dive profile scripting | **Legacy scripts exist** — need update for new model |

---

## Files (Current State)

### Project Infrastructure
| File | Purpose |
|------|---------|
| `scuba-buyancy.prj` | MATLAB Project file |
| `scripts/initWorkspace.m` | Loads params into workspace on project open |
| `.gitignore` | Excludes slprj/, *.slxc, *.mex*, codegen/, *.autosave |
| `.gitattributes` | Git LFS / line-ending config |

### Custom Simscape Domain (`+scuba/+gas/`)
| File | Purpose |
|------|---------|
| `+scuba/+gas/underwaterGas.ssc` | Domain definition (p across; n_dot through; R_gas, T params) |
| `+scuba/+gas/branch.ssc` | Two-port base class — **unused, candidate for removal** |
| `+scuba/+gas/+elements/GasDomainProperties.ssc` | Propagation source for domain params |
| `+scuba/+gas/+elements/GasTank.ssc` | HP reservoir with translational port (weight force) |
| `+scuba/+gas/+elements/GasVolume.ssc` | Small rigid volume for IP node (100mL) |
| `+scuba/+gas/+elements/FirstStageRegulator.ssc` | HP → IP (P_amb + 10 bar), translational port |
| `+scuba/+gas/+elements/SecondStageRegulator.ssc` | Demand valve, translational port |
| `+scuba/+gas/+elements/Lungs.ssc` | Variable chamber with buoyancy force output |
| `+scuba/+gas/+elements/ExhaleValve.ssc` | Check valve (P_crack=50 Pa) |
| `+scuba/+gas/+elements/BCDInflateValve.ssc` | Commanded on/off valve |
| `+scuba/+gas/+elements/BCDBladder.ssc` | Flexible accumulator with buoyancy force output |
| `+scuba/+gas/+elements/PurgeValve.ssc` | Commanded dump valve |
| `+scuba/+gas/+elements/OverpressureReliefValve.ssc` | Passive OPRV (cracks at 3 psi gauge) |
| `+scuba/+gas/+elements/AmbientReference.ssc` | Infinite source/sink at P_amb, translational port |
| `+scuba/+gas/+elements/IdealMolarFlowSource.ssc` | Test utility — **unused in main model** |
| `+scuba/+gas/+elements/IdealPressureSource.ssc` | Test utility — **unused in main model** |
| `+scuba/+gas/+elements/images/*.svg` | Custom SVG mask icons |

### Mechanical (`+scuba/`)
| File | Purpose |
|------|---------|
| `+scuba/DiverBody.ssc` | Combined mass + body buoyancy + quadratic drag |
| `+scuba/images/DiverBody.svg` | Icon for DiverBody |

### Models
| File | Purpose |
|------|---------|
| `descent_test.slx` | Primary test harness (Stateflow controller + Plant) |
| `models/Scuba_Diver.slx` | Reusable plant (3 in, 2 out) — same as Plant subsystem |
| `models/scuba_lib.slx` | Compiled Simscape library (output of `sscbuild`) |

#### Model Hierarchy (`descent_test.slx`)
```
root
├── Desired Depth (Constant = 15)
├── Chart (Stateflow: drop → float → done)
├── Plant/
│   ├── Gas Tank (+ GasDomainProps on same node)
│   ├── First Stage Regulator
│   ├── Hose Volume (GasVolume at IP node)
│   ├── Regulator/ — SecondStageReg, Lungs, ExhaleValve
│   ├── BCD/ — InflateValve, OPRV, PurgeValve, BCD Bladder, BCD Probe
│   ├── AmbientRef
│   ├── Diver Body
│   ├── Weights (Mass PB)
│   ├── Surface and Bottom/ — 2× Hard Stop + 2× Spacer
│   ├── Initial Depth (Initial Length PB)
│   ├── MechProps, Translational World, Solver
│   └── MotionSensor → PSS_Pos → depth, PSS_Vel → vel
├── Compare To Constant (depth < 0.1), Compare To Constant1 (depth > 45)
├── OR → Stop Simulation
├── Unit Delay (depth feedback to Chart)
└── DepthScope, VelScope, VelScope1 (BCD commands)
```

### Parameters
| File | Purpose |
|------|---------|
| `parameters/scuba_params.m` | Master configuration |
| `parameters/gas_properties.m` | Gas mix lookup (Air, Nitrox 32%) |
| `parameters/diver_configs.m` | Preset configurations |

### Scripts
| File | Purpose |
|------|---------|
| `scripts/rebuildScubaLib.m` | `sscbuild('scuba','-output','models')` |
| `scripts/load_plant_params.m` | Flattens `params` struct into workspace variables |
| `scripts/run_simulation.m` | Programmatic sim runner (legacy, may need update) |
| `scripts/run_full_dive.m` | Full dive profile (legacy, references old model) |
| `scripts/create_dive_profile.m` | Generates dive profile dataset |
| `scripts/plot_dive_results.m` | 3-panel dive results plot |
| `scripts/plot_results.m` | 6-panel post-simulation visualization |
| `scripts/test_bcd_buoyancy.m` | Programmatic harness builder (builds `bcd_buoyancy_harness` from scratch) |

### Tests
| Status | Notes |
|--------|-------|
| **Removed** | All 9 test classes and ScubaTestHelper deleted. Need rewrite targeting new model architecture. |

### Documentation
| File | Purpose |
|------|---------|
| `docs/implementation_plan.md` | Original architecture and phase plan (partially outdated) |
| `docs/test_plan.md` | Original test plan (outdated — tests removed) |
| `docs/diary.md` | Design diary (historical) |
| `docs/handoff.md` | This file |

---

## Key Technical Decisions

### Current Design Decisions

1. **Custom gas domain** — Not Foundation Gas (overkill) or PS signals (not physical enough)
2. **Demand-driven breathing** — Muscular effort pressure triggers the regulator physically
3. **Molar flow as through variable** — Natural for ideal gas; conserved quantity
4. **Isothermal assumption** — T is a domain parameter, not dynamic state
5. **Position-based translational (beta=90 deg)** — Depth = position, positive downward
6. **P_amb computed locally per component** — Each component with a translational port computes `P_amb = P_atm + rho_water * R.gravity * R.x`. No domain-level propagation needed. Eliminates wiring complexity.
7. **DiverBody = mass + buoyancy + drag** — Single component: `f == mass*der(R.v) - mass*R.gravity + F_buoy + F_drag`. No separate force blocks.
8. **Lungs and BCDBladder apply buoyancy directly** — Each computes `F_buoy = rho_water * R.gravity * V` and applies through translational port. Eliminates the old centralized BuoyancyForceSource.
9. **GasTank applies gas weight** — `f == n_tank * M_gas * R.gravity` through translational port.
10. **Modern Simscape constructs** — No deprecated `function setup` or `let/in/end`; uses `{value = param, priority = priority.high}` for state init, `intermediates` for derived quantities.
11. **Custom SVG mask icons via annotations** — `annotations; Icon = 'images/Name.svg'; end`
12. **OPRV in BCD circuit** — Passive overpressure relief valve (P_crack = 20684 Pa / 3 psi) between InflateValve output and PurgeValve output nodes.
13. **BCDBladder moles clamped non-negative** — Prevents unphysical reverse depletion.
14. **Surface and Bottom hard stops** — Spacer + Hard Stop pairs limit travel range. Initialization no longer singular because Initial Length (PB) sets starting position.

### Numerical Solutions

| Problem | Solution |
|---------|----------|
| IP node singular matrix | GasVolume (100mL) between regulators |
| 2nd stage unrealistic flow rates | Flow driven by demand pressure (~200 Pa), not full IP differential |
| Hard stop singularity at t=0 | Initial Length (PB) block sets starting position away from stops |
| `R.f` balancing variable error | Through variables must use `branches` section |
| BCD negative moles | Clamped in `intermediates`: `n_dot_clamped = 0` when `n_bcd <= 0` and outflow requested |

---

## Open Decisions / Risks

| Item | Status | Notes |
|------|--------|-------|
| Valve discontinuities | Working | if/else formulation works with ode23t; may need tanh smoothing if solver struggles |
| Gas mix switching | Deferred | Currently a parameter, not dynamic |
| BCD V_max overflow | Implemented | BCDBladder uses wall stiffness K_wall when V > V_max |
| Unused library components | Pending cleanup | `branch.ssc`, `IdealMolarFlowSource.ssc`, `IdealPressureSource.ssc` |
| Test suite | Removed | Needs full rewrite for new architecture |
| Legacy scripts | Partially outdated | `run_full_dive.m`, `run_simulation.m` reference old model |
| Wetsuit compression | Not in current model | DiverBody uses fixed V_body; wetsuit was in old BuoyancyForceSource |

---

## Blockers

None. Harness model runs successfully with Stateflow depth controller.

---

## Next Steps

1. **Remove unused components** — delete `branch.ssc`, `IdealMolarFlowSource.ssc`, `IdealPressureSource.ssc` and corresponding SVGs
2. **Rewrite test suite** — target `descent_test.slx` / `Scuba_Diver.slx`
3. **Add wetsuit compression** — either in DiverBody or as separate component
4. **Improve depth controller** — current Stateflow is minimal (drop → float → done); add proper depth-following
5. **Update legacy scripts** — `run_simulation.m`, `run_full_dive.m` for new model
6. **Dashboard & visualization** — knobs, gauges, real-time pacing

---

## How to Continue

1. Open MATLAB project: `openProject('L:\Projects\scuba')` or double-click `scuba-buyancy.prj` — `scripts/initWorkspace.m` auto-loads params and plant variables
2. Build the library: `run('scripts/rebuildScubaLib.m')` — compiles `.ssc` files into `models/scuba_lib.slx`
3. Open the harness: `open_system('descent_test')`
4. Click Play — Stateflow controller descends to target depth (15m default), inflates BCD, holds
5. If you get "undefined variable" errors, run `initWorkspace` to reload workspace variables
6. Modify target depth: change the "Desired Depth" constant block
7. Open `models/Scuba_Diver.slx` to use the plant standalone (provide inflate, purge, breath inputs)

---

## Component Port Summary (Current)

Each gas component with a translational port:

| Component | Gas Port | Translational Port | Force Applied |
|-----------|----------|-------------------|---------------|
| GasTank | A (outlet) | R | Gas weight: `n_tank * M_gas * g` |
| FirstStageRegulator | A (HP in), B (IP out) | R | Zero (sensor only) |
| SecondStageRegulator | A (IP in), B (breathing out) | R | Zero (sensor only) |
| Lungs | A (gas) | R | Lung buoyancy: `rho * g * V_lungs` |
| BCDBladder | A (gas) | R | BCD buoyancy: `rho * g * V_bcd` |
| AmbientReference | A (gas) | R | Zero (sensor only) |
| DiverBody | — | R | `mass*a = -weight + body_buoyancy + drag` |
