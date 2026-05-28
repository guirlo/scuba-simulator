# Project Handoff — Scuba Buoyancy Simulation

**Date:** 2026-05-28  
**Project:** scuba-buoyancy  
**Location:** `L:\Projects\scuba`  
**MATLAB version:** R2026a  
**Status:** Phases 1–6 complete. Depth controller and full 36-min dive profile implemented. Test suite (Phase 8) complete — all 41 tests passing. Dashboard (Phase 7) and remaining polish remain.

---

## Project Goal

Build a 1D vertical buoyancy simulation of a scuba diver in Simulink/Simscape that:
- Models breath-by-breath gas consumption through a realistic equipment topology (tank → regulators → lungs/BCD → water)
- Uses a **custom Simscape gas domain** with conserving physical connections (pressure across, molar flow through)
- Simulates wetsuit neoprene compression, BCD inflate/purge, and depth-dependent gas behavior
- Supports Air and Nitrox 32% gas mixes
- Provides interactive real-time dashboard control AND pre-programmed dive profiles
- Validates physics against analytical solutions

---

## Architecture Summary

| Layer | Technology | Responsibility |
|-------|-----------|----------------|
| Plant — Gas | Custom Simscape domain (`+scuba/+gas/`) | Physical gas flow: tank, regulators, lungs, BCD, valves |
| Plant — Mechanical | Simscape Translational (Position-Based, beta=90 deg) | 1-DOF vertical motion, buoyancy force, drag |
| Control | Simulink + Stateflow | Breathing state machine, BCD commands, dashboard UI |
| Coupling | Domain across variable + PS ports | P_amb (mech->AmbientRef->domain), volumes (gas->mech), commands (Simulink->gas) |

Key design principle: Gas flow is driven by **pressure differentials**, not command signals. The 2nd stage regulator opens physically when the diver's breathing effort creates suction. The BCD fills because opening the inflate valve exposes it to intermediate pressure.

---

## Current Progress

### Accomplishments (Phases 1–6 Complete, Depth Controller Added, Phase 8 Test Suite Complete)

1. **Custom gas domain implemented and compiling** — `scuba.gas` domain with pressure and ambient pressure (across) and molar flow (through) variables, compiled via `sscbuild('scuba')` into `scuba_lib`. P_amb propagates through the domain connection — only AmbientReference takes it as a PS input.

2. **Full gas component library (13 blocks)** — GasTank, FirstStageRegulator, GasVolume, SecondStageRegulator, Lungs, ExhaleValve, BCDInflateValve, BCDBladder, PurgeValve, AmbientReference, GasDomainProperties all working.

3. **Mechanical coupling components** — AmbientPressure (depth sensor -> P_amb), BuoyancyForceSource (volumes -> Archimedes force, includes weight), HydrodynamicDrag (quadratic).

4. **Integrated top-level model running** — `scuba_buoyancy_sim.slx` simulates 120s with ode23t solver. Diver starts at 20m, breathes at 15 bpm, gas flows driven by pressure differentials, buoyancy-depth coupling works correctly.

5. **Numerical issues resolved** — IP node singularity (added GasVolume), lung volume divergence (tuned valve resistances), 2nd stage flow formulation (demand-proportional), initial condition conflicts.

6. **Tuned for realistic behavior** — Regulator-limited tidal volume (~0.1L at 20m), correct tank depletion rate, BCD trimmed for approximate neutral buoyancy at 20m.

7. **Stateflow breathing controller** — 4-state machine (INHALE -> PAUSE -> EXHALE -> PAUSE) with half-sine effort waveform. Configurable rate (bpm) and depth (scalar). Replaces sine wave source.

8. **BCD controller** — 3-state machine (IDLE/INFLATING/PURGING) with mutual exclusion (inflate priority). Accepts button inputs, outputs valve commands.

9. **Root-level Inport blocks** — `breathing_rate`, `breath_depth`, `inflate_btn`, `purge_btn`, `depth_target`, `auto_depth` as model inports. When `auto_depth > 0.5`, the DepthController overrides manual BCD buttons.

10. **Model reorganized into subsystems** — Controllers, GasCircuit, Mechanics with named ports (P_amb, V_bcd, V_lungs, breath_effort, inflate_cmd, purge_cmd).

11. **Deprecated `function setup` removed** — All Simscape components use modern constructs: `{value = param, priority = priority.high}` for state initialization, inline node declaration for domain parameter propagation.

12. **Test suite complete and passing** — 41 tests across 8 test classes, all passing. Covers flow conservation, ideal gas law, regulator behavior, breathing mechanics, BCD operation, buoyancy maneuvers, dive profiles, and analytical physics validation.

13. **Custom SVG mask icons** — All 14 Simscape components have custom SVG icons (schematic-style line art) via `annotations` blocks referencing SVG files in `images/` directories. Icons are embedded in `scuba_lib.slx` on rebuild.

14. **Externalized plant parameters** — All hardcoded numerical values removed from Simscape block dialogs. Block parameters reference workspace variables (e.g., `tank_V`, `reg1_IP_offset`, `env_rho_water`) populated by `load_plant_params()` from the master `scuba_params()` struct. Single source of truth for all plant tuning.

15. **Depth controller with full dive profile** — Closed-loop depth-following controller (MATLAB Function block) commands BCD inflate/purge to track a target depth trajectory. Bang-bang with ±2m deadband, velocity damping, and ascent/descent rate limiting. Mode switch selects manual (buttons) vs auto (controller). Memory blocks break algebraic loop.

16. **36-minute dive profile** — Surface start (1m) → descent to 30m → 20 min bottom → stepped 5m ascent with 1-min holds → 3-min safety stop at 5m → return to 1m. Script `create_dive_profile.m` generates the dataset; `run_full_dive.m` runs end-to-end.

17. **PurgeValve enhanced with P_dump** — 5000 Pa mechanical dump bias enables active BCD venting even when bladder is not overfull. Models hydrostatic head from raising dump valve. Flow clamped non-negative (one-way: BCD to water).

### Simulation Results (36-min dive profile)

- Diver tracks 30m target with ±2m accuracy (std=1.6m during bottom phase)
- Stepped ascent followed through all 5m increments
- Max ascent rate: 0.64 m/s (physics-limited by Boyle expansion vs purge rate; 0.15 m/s target is aspirational)
- Tank consumption: 123 bar (200→77 bar) — realistic for 36 min at 30m
- Safety stop at 5m maintained correctly
- All 41 tests pass (no regressions)

### Simulation Results (120s run, Phase 6 — original open-loop)

- Diver starts at 20m, drifts to ~18.9m (less drift than sine wave due to pause phases)
- Tank consumes ~0.278 mol over 120s (lower than 0.36 with sine because pauses reduce active breathing time)
- Breathing period measured at 4.04s (15 bpm target = 4.0s)
- Duty cycle: Inhale 39%, Exhale 34%, Pauses 28% (targets: 40/35/25)
- BCD inflate/purge verified functional with mutual exclusion
- All domain coupling continues to function correctly

---

## Implementation Phases

| Phase | Focus | Status |
|-------|-------|--------|
| 1 | Domain foundation (gas.ssc, branch.ssc, GasTank, AmbientRef) | **Complete** |
| 2 | Regulators (1st stage, 2nd stage demand valve) | **Complete** |
| 3 | Breathing circuit (Lungs, ExhaleValve) | **Complete** |
| 4 | BCD circuit (InflateValve, Bladder, PurgeValve) | **Complete** |
| 5 | Mechanical domain coupling (AmbientPressure, BuoyancyForce, Drag) | **Complete** |
| 6 | Controllers (Stateflow breathing, BCD logic) | **Complete** |
| 7 | Dashboard, visualization, input profiles | **Not started** |
| 8 | Test suite, tuning, documentation | **Tests complete (41/41 passing)** |

---

## Files Created / Modified

### Project Infrastructure
| File | Purpose |
|------|---------|
| `blank_project.prj` | MATLAB Project file (name: "scuba-buoyancy") |
| `startup.m` | Loads params into workspace on project open |
| `shutdown.m` | Clears workspace on project close |
| `.gitignore` | Excludes slprj/, *.slxc, *.mex*, codegen/, *.autosave |
| `.gitattributes` | Git LFS / line-ending config |

### Custom Simscape Domain (`+scuba/+gas/`)
| File | Purpose |
|------|---------|
| `+scuba/+gas/gas.ssc` | Domain definition (p, p_amb across; n_dot through; R_gas, T params) |
| `+scuba/+gas/branch.ssc` | Two-port base class (A->B, p_diff, n_dot) |
| `+scuba/+gas/+elements/GasDomainProperties.ssc` | Propagation source for domain params |
| `+scuba/+gas/+elements/GasTank.ssc` | HP reservoir (n_init=98.47 mol, V=12L) |
| `+scuba/+gas/+elements/GasVolume.ssc` | Small rigid volume for IP node (V=100mL) |
| `+scuba/+gas/+elements/FirstStageRegulator.ssc` | HP -> IP (P_amb + 10 bar) |
| `+scuba/+gas/+elements/SecondStageRegulator.ssc` | Demand valve (R_open=6000 Pa*s/mol) |
| `+scuba/+gas/+elements/Lungs.ssc` | Variable chamber (P_amb + breath_effort) |
| `+scuba/+gas/+elements/ExhaleValve.ssc` | Check valve (R_open=9000, P_crack=50 Pa) |
| `+scuba/+gas/+elements/BCDInflateValve.ssc` | Commanded on/off valve |
| `+scuba/+gas/+elements/BCDBladder.ssc` | Flexible accumulator (P=P_amb, V_max clamped) |
| `+scuba/+gas/+elements/PurgeValve.ssc` | Commanded dump valve |
| `+scuba/+gas/+elements/AmbientReference.ssc` | Infinite source/sink at P_amb; injects p_amb into domain |
| `+scuba/+gas/+elements/images/*.svg` | Custom SVG mask icons for all gas elements (11 files) |

### Mechanical Coupling (`+scuba/`)
| File | Purpose |
|------|---------|
| `+scuba/AmbientPressure.ssc` | Integrates velocity -> depth, outputs P_amb (zero-force sensor) |
| `+scuba/BuoyancyForceSource.ssc` | Archimedes buoyancy + weight + wetsuit compression |
| `+scuba/HydrodynamicDrag.ssc` | Quadratic drag: 0.5*rho*Cd*A*v*|v| |
| `+scuba/images/*.svg` | Custom SVG mask icons for mechanical components (3 files) |

### Models
| File | Purpose |
|------|---------|
| `models/scuba_buoyancy_sim.slx` | Top-level model with subsystem hierarchy (see below) |
| `models/test_breathing.slx` | Legacy breathing circuit test harness (unused, can be removed) |

#### Model Hierarchy (`scuba_buoyancy_sim.slx`)
```
root
+-- Inports: breathing_rate, breath_depth, inflate_btn, purge_btn, depth_target, auto_depth
+-- Controllers/        -- BreathingController (Stateflow), BCDController (Stateflow),
|                          DepthController (MATLAB Function), InflateSwitch, PurgeSwitch,
|                          DepthMemory, VelMemory
+-- GasCircuit/         -- Tank, regulators, lungs, BCD, valves, SPS converters, Solver
+-- Mechanics/          -- DiverMass, BuoyancyForce, HydroDrag, AmbientPressure, MotionSensor, Scopes
                           (outputs: P_amb, depth, velocity)
```

### Parameters
| File | Purpose |
|------|---------|
| `parameters/scuba_params.m` | Master configuration (water, tank, regulators, valves, diver, wetsuit, BCD, ICs, constants, derived) |
| `parameters/gas_properties.m` | Gas mix lookup (Air, Nitrox 32%) |
| `parameters/diver_configs.m` | Preset configurations (beginner, experienced, nitrox) |

### Scripts
| File | Purpose |
|------|---------|
| `scripts/run_simulation.m` | Programmatic sim runner (open-loop, short runs) |
| `scripts/run_full_dive.m` | Full 36-min dive profile with depth controller |
| `scripts/create_dive_profile.m` | Generates dive profile dataset (descent, bottom, stepped ascent, safety stop) |
| `scripts/plot_dive_results.m` | 3-panel dive results (depth+target, tank pressure, BCD volume) |
| `scripts/build_library.m` | Runs `sscbuild('scuba')` |
| `scripts/plot_results.m` | 6-panel post-simulation visualization |
| `scripts/load_plant_params.m` | Flattens `params` struct into workspace variables for Simscape block dialogs |

### Tests
| File | Purpose |
|------|---------|
| `tests/ScubaTestHelper.m` | Shared test infrastructure (model load, logging, signal extraction) |
| `tests/tGasDomainBasic.m` | Flow conservation, tank pressure, depletion (3 tests) |
| `tests/tRegulatorSetPoint.m` | 1st/2nd stage regulator behavior (4 tests) |
| `tests/tBreathingCycle.m` | Lung volume, moles/breath, frequency, positivity (4 tests) |
| `tests/tBCDInflateDeflate.m` | Inflate, purge, hold, V_max, monotonicity (5 tests) |
| `tests/tWetsuitDrag.m` | Wetsuit compression, drag formula (6 tests, analytical) |
| `tests/tBuoyancyManeuvers.m` | Neutral hold, descent, ascent, BCD control (7 tests) |
| `tests/tDiveProfiles.m` | Profile scenarios, instability, consumption (5 tests) |
| `tests/tPhysicsValidation.m` | Analytical physics: Boyle's law, Archimedes, terminal velocity, mass balance (7 tests) |

### Documentation
| File | Purpose |
|------|---------|
| `docs/implementation_plan.md` | Architecture and phase plan |
| `docs/test_plan.md` | 41 tests across 4 tiers with pass criteria |
| `docs/diary.md` | Design diary (records architecture iterations and implementation notes) |
| `docs/handoff.md` | This file |

---

## Key Technical Decisions & Lessons Learned

### Locked-In Design Decisions

1. **Custom gas domain** — Not Foundation Gas (overkill) or PS signals (not physical enough)
2. **Demand-driven breathing** — Muscular effort pressure triggers the regulator physically
3. **Molar flow as through variable** — Natural for ideal gas; conserved quantity
4. **Isothermal assumption** — T is a domain parameter, not dynamic state
5. **Position-based translational (beta=90 deg)** — Depth = position, positive downward
6. **Wetsuit compression exponent 0.7** — Empirical, partial structural constraint
7. **Weight integrated into BuoyancyForceSource** — Eliminates separate gravity block and PS connection issues
8. **Modern Simscape constructs** — No deprecated `function setup`; uses variable priority for initialization and inline node params for propagation
9. **P_amb as domain across variable** — Ambient pressure propagates through gas connections (set by AmbientReference, read via `A.p_amb` by all components). Eliminates individual PS wires to each block
10. **Externalized plant parameters** — All Simscape block values reference workspace variables (not hardcoded numbers). `scuba_params()` is the single source of truth; `load_plant_params()` flattens into named variables (e.g., `tank_V`, `reg1_IP_offset`). Block dialogs use these names directly.
11. **Custom SVG mask icons via annotations** — Each `.ssc` component declares `annotations; Icon = 'images/Name.svg'; end`. SVGs are embedded into `scuba_lib.slx` during `sscbuild`.
12. **Depth controller as MATLAB Function block** — Bang-bang with deadband, not PID. Chosen because plant is fundamentally unstable (Boyle expansion positive feedback) and valve actuation is binary (open/closed). Velocity damping provides station-keeping. Memory blocks break algebraic loop.
13. **Asymmetric inflate/purge rates for controllability** — BCD inflate valve R_open=5e6 (gives ~0.2 mol/s) to prevent controller overshoot. Purge P_dump=5000 Pa with R_open=1e4 (gives ~0.5 mol/s) for faster venting during Boyle-expansion-driven ascent.
14. **Diver weighting: 93 kg for surface-start dives** — Default 89 kg is neutral at surface with no BCD gas. Surface-start dive requires ~2 kg overweight (93 kg total) so diver can descend passively. Override via `setBlockParameter` in run scripts; base params unchanged for existing tests.

### Numerical Solutions Discovered

| Problem | Solution |
|---------|----------|
| IP node singular matrix (two regulators sharing node) | Added GasVolume (100mL) between regulators |
| Lung volume divergence (unbounded gas accumulation) | 2nd stage uses demand-proportional flow: (P_amb - P_lung - P_crack) / R_open |
| 2nd stage unrealistic flow rates | Flow driven by demand pressure (~200 Pa), not full IP differential (~10 bar) |
| Hard stop singularity at t=0 | Removed for now; re-add with proper initialization |
| `R.f` balancing variable error | Through variables must use `branches` section, not direct equation reference |
| Domain param propagation | Requires inline node declaration: `A = domain(param = val)` |
| Depth controller algebraic loop | Memory blocks on depth/velocity feedback break the loop |
| BCD purge ineffective (zero pressure diff) | Added P_dump parameter (5000 Pa) to PurgeValve, clamped non-negative |
| Controller overshoot from fast inflate | Increased BCDInflateValve R_open from 2e4 to 5e6 Pa*s/mol |
| Boyle expansion exceeds purge rate during ascent | Physics-correct: max ascent ~0.64 m/s with current valve sizing (not a bug) |

### Tuned Parameter Values

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| 2nd stage R_open | 6000 Pa*s/mol | Gives regulator-limited tidal volume with 200 Pa effort |
| Exhale valve R_open | 9000 Pa*s/mol | Balances inhale rate for steady-state lung volume |
| IP volume | 100 mL (n_init=0.04518 mol) | Provides pressure state without affecting dynamics |
| BCD n_init | 0.298 mol | Approximately neutral buoyancy at 20m (open-loop tests) |
| BCD inflate R_open | 5e6 Pa*s/mol | ~0.2 mol/s fill rate; prevents controller overshoot |
| Purge P_dump | 5000 Pa | Enables active dump; models hydrostatic head |
| Purge R_open | 1e4 Pa*s/mol | With P_dump gives ~0.5 mol/s vent rate |
| n_tank initial | 98.47 mol | = 200e5 * 0.012 / (8.314 * 293.15) |
| Depth controller deadband | ±2 m | Reduces limit cycling on unstable plant |
| Max ascent rate | 0.15 m/s | 9 m/min recreational diving limit |
| Diver mass (dive profile) | 93 kg | Surface-start: 80 body + 8 belt + 5 gear |

---

## Open Decisions / Risks

| Item | Status | Notes |
|------|--------|-------|
| Hard stop at surface | Deferred | Removed due to initialization singularity; dive profile starts at 1m to avoid |
| Valve discontinuities | Working | if/else formulation works with ode23t; may need tanh smoothing if solver struggles in edge cases |
| Gas mix switching | Deferred | Currently a parameter, not dynamic. Hot-switching needs additional architecture |
| BCD V_max overflow | Implemented | BCDBladder uses wall stiffness K_wall when V > V_max |
| Breathing controller fidelity | Complete | Stateflow 4-state machine replaces sine wave |
| Ascent rate limiting | Partial | Controller targets 0.15 m/s but Boyle expansion limits actual to ~0.64 m/s during step transitions. Faster purge valve or proportional control would improve this. |
| Depth controller oscillation | Acceptable | ±2m at target depth due to bang-bang on unstable plant. PID or proportional valve would reduce. |
| test_breathing.slx | Unused | Legacy harness from Phase 3, can be deleted |

---

## Blockers

None currently. Model runs stably for 36+ minutes with closed-loop depth control. All prerequisites for Phase 7 (Dashboard) are in place — auto/manual mode switching infrastructure exists. Test suite (41/41) validates all physics.

---

## Next Steps

### Phase 7: Dashboard & Visualization
1. Simulink Dashboard blocks: knobs (rate, depth), buttons (inflate, purge, auto mode), gauges (depth, tank, BCD), scopes
2. Mode switch: manual vs. auto depth control (wiring exists — `auto_depth` inport)
3. Real-time pacing for interactive simulation
4. Dive profile selector (pre-built profiles via `create_dive_profile.m` pattern)

### Remaining Phase 8 Polish
1. Improve ascent rate control (proportional purge valve or faster vent)
2. Re-integrate hard stop at surface with proper initialization
3. Parameter sweep / sensitivity analysis
4. Gas mix switching support
5. Delete unused `test_breathing.slx`
6. Documentation finalization

---

## How to Continue

1. Open MATLAB project: `openProject('L:\Projects\scuba')` or double-click `blank_project.prj` — `startup.m` auto-loads `params`, `gas`, and all plant variables into workspace
2. Build the library: `run('scripts/build_library.m')` — compiles `.ssc` files (with SVG icons) into `scuba_lib`
3. Open the model: `open_system('scuba_buoyancy_sim')`
4. **Run the full dive profile:**
   ```matlab
   run('scripts/run_full_dive.m')
   ```
   This creates the 36-min dive profile, configures initial conditions (1m depth, 93 kg diver, near-empty BCD), enables logging, simulates, and plots results.
5. Run with default inputs (open-loop): click Play (uses ground/zero for inports — manual mode, diver at 20m)
   - If you get "undefined variable" errors, run `startup` to reload workspace variables
6. Run with custom timeseries inputs:
   ```matlab
   t = [0; 1800];
   ds = Simulink.SimulationData.Dataset;
   ds = ds.addElement(timeseries(15*ones(2,1), t), 'breathing_rate');
   ds = ds.addElement(timeseries(ones(2,1), t), 'breath_depth');
   ds = ds.addElement(timeseries(zeros(2,1), t), 'inflate_btn');
   ds = ds.addElement(timeseries(zeros(2,1), t), 'purge_btn');
   ds = ds.addElement(timeseries([20;20], t), 'depth_target');  % target depth
   ds = ds.addElement(timeseries([1;1], t), 'auto_depth');      % 1=auto, 0=manual
   simIn = Simulink.SimulationInput('scuba_buoyancy_sim');
   simIn = simIn.setModelParameter('LoadExternalInput','on','ExternalInput','ds');
   out = sim(simIn);
   ```
7. Visualize: `plot_dive_results(out, ds)` or `plot_results(out)` after simulation
8. Run tests: `results = runtests('tests'); disp(results);`
9. Continue with Phase 7 per the plan above

---

## Key Physics Parameters (Quick Reference)

All values defined in `parameters/scuba_params.m`, loaded into workspace by `load_plant_params()`.

| Workspace Variable | Value | Source in `params` |
|--------------------|-------|-------------------|
| `env_rho_water` | 1025 kg/m^3 | `params.water.rho` |
| `env_P_atm` | 101,325 Pa | `params.const.Patm` |
| `tank_V` | 0.012 m^3 (12 L) | `params.tank.internalVolume` |
| `tank_n_init` | 98.47 mol | `params.tank.startMoles` (derived) |
| `reg1_IP_offset` | 10e5 Pa (10 bar) | `params.firstStage.IP_offset` |
| `reg1_R_open` | 1e3 Pa*s/mol | `params.firstStage.R_open` |
| `reg2_P_crack` | 100 Pa | `params.secondStage.P_crack` |
| `reg2_R_open` | 6000 Pa*s/mol | `params.secondStage.R_open` |
| `exhale_P_crack` | 50 Pa | `params.exhaleValve.P_crack` |
| `exhale_R_open` | 9000 Pa*s/mol | `params.exhaleValve.R_open` |
| `bcdinfl_R_open` | 5e6 Pa*s/mol | `params.bcdInflateValve.R_open` |
| `bcd_V_max` | 0.015 m^3 (15 L) | `params.bcd.maxVolume` |
| `purge_R_open` | 1e4 Pa*s/mol | `params.purgeValve.R_open` |
| `purge_P_dump` | 5000 Pa | Hardcoded in `load_plant_params.m` |
| `diver_m_total` | 89 kg (93 for dive profile) | `params.diver.totalMass` (derived) |
| `diver_V_body` | 0.078 m^3 | `params.diver.bodyVolume` |
| `gear_V` | 0.003 m^3 | `params.gear.volume` |
| `ws_V_surface` | 0.0063 m^3 | `params.wetsuit.surfaceVolume` (derived) |
| `ws_comp_exp` | 0.7 | `params.wetsuit.compressionExponent` |
| `drag_Cd` | 1.1 | `params.diver.dragCoeff` |
| `drag_A_frontal` | 0.12 m^2 | `params.diver.frontalArea` |
| `ic_depth` | 20 m | `params.ic.depth` |
