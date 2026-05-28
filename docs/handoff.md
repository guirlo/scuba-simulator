# Project Handoff — Scuba Buoyancy Simulation

**Date:** 2026-05-27  
**Project:** scuba-buoyancy  
**Location:** `L:\Projects\scuba`  
**MATLAB version:** R2026a  
**Status:** Phases 1–6 complete. Test suite (Phase 8) implemented and all 41 tests passing. Dashboard (Phase 7) and remaining polish remain.

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

### Accomplishments (Phases 1–6 Complete, Phase 8 Test Suite Complete)

1. **Custom gas domain implemented and compiling** — `scuba.gas` domain with pressure and ambient pressure (across) and molar flow (through) variables, compiled via `sscbuild('scuba')` into `scuba_lib`. P_amb propagates through the domain connection — only AmbientReference takes it as a PS input.

2. **Full gas component library (13 blocks)** — GasTank, FirstStageRegulator, GasVolume, SecondStageRegulator, Lungs, ExhaleValve, BCDInflateValve, BCDBladder, PurgeValve, AmbientReference, GasDomainProperties all working.

3. **Mechanical coupling components** — AmbientPressure (depth sensor -> P_amb), BuoyancyForceSource (volumes -> Archimedes force, includes weight), HydrodynamicDrag (quadratic).

4. **Integrated top-level model running** — `scuba_buoyancy_sim.slx` simulates 120s with ode23t solver. Diver starts at 20m, breathes at 15 bpm, gas flows driven by pressure differentials, buoyancy-depth coupling works correctly.

5. **Numerical issues resolved** — IP node singularity (added GasVolume), lung volume divergence (tuned valve resistances), 2nd stage flow formulation (demand-proportional), initial condition conflicts.

6. **Tuned for realistic behavior** — Regulator-limited tidal volume (~0.1L at 20m), correct tank depletion rate, BCD trimmed for approximate neutral buoyancy at 20m.

7. **Stateflow breathing controller** — 4-state machine (INHALE -> PAUSE -> EXHALE -> PAUSE) with half-sine effort waveform. Configurable rate (bpm) and depth (scalar). Replaces sine wave source.

8. **BCD controller** — 3-state machine (IDLE/INFLATING/PURGING) with mutual exclusion (inflate priority). Accepts button inputs, outputs valve commands.

9. **Root-level Inport blocks** — `breathing_rate`, `breath_depth`, `inflate_btn`, `purge_btn` as model inports, ready for timeseries input via `Simulink.SimulationData.Dataset`.

10. **Model reorganized into subsystems** — Controllers, GasCircuit, Mechanics with named ports (P_amb, V_bcd, V_lungs, breath_effort, inflate_cmd, purge_cmd).

11. **Deprecated `function setup` removed** — All Simscape components use modern constructs: `{value = param, priority = priority.high}` for state initialization, inline node declaration for domain parameter propagation.

12. **Test suite complete and passing** — 41 tests across 8 test classes, all passing. Covers flow conservation, ideal gas law, regulator behavior, breathing mechanics, BCD operation, buoyancy maneuvers, dive profiles, and analytical physics validation.

### Simulation Results (120s run, Phase 6)

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

### Mechanical Coupling (`+scuba/`)
| File | Purpose |
|------|---------|
| `+scuba/AmbientPressure.ssc` | Integrates velocity -> depth, outputs P_amb (zero-force sensor) |
| `+scuba/BuoyancyForceSource.ssc` | Archimedes buoyancy + weight + wetsuit compression |
| `+scuba/HydrodynamicDrag.ssc` | Quadratic drag: 0.5*rho*Cd*A*v*|v| |

### Models
| File | Purpose |
|------|---------|
| `models/scuba_buoyancy_sim.slx` | Top-level model with subsystem hierarchy (see below) |
| `models/test_breathing.slx` | Legacy breathing circuit test harness (unused, can be removed) |

#### Model Hierarchy (`scuba_buoyancy_sim.slx`)
```
root
+-- Inports: breathing_rate, breath_depth, inflate_btn, purge_btn
+-- Controllers/        -- BreathingController (Stateflow), BCDController (Stateflow)
+-- GasCircuit/         -- Tank, regulators, lungs, BCD, valves, SPS converters, Solver
+-- Mechanics/          -- DiverMass, BuoyancyForce, HydroDrag, AmbientPressure, MotionSensor, Scopes
```

### Parameters
| File | Purpose |
|------|---------|
| `parameters/scuba_params.m` | Master configuration (water, tank, diver, wetsuit, BCD, breathing) |
| `parameters/gas_properties.m` | Gas mix lookup (Air, Nitrox 32%) |
| `parameters/diver_configs.m` | Preset configurations (beginner, experienced, nitrox) |

### Scripts
| File | Purpose |
|------|---------|
| `scripts/run_simulation.m` | Programmatic sim runner |
| `scripts/build_library.m` | Runs `sscbuild('scuba')` |
| `scripts/plot_results.m` | 6-panel post-simulation visualization |

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

### Numerical Solutions Discovered

| Problem | Solution |
|---------|----------|
| IP node singular matrix (two regulators sharing node) | Added GasVolume (100mL) between regulators |
| Lung volume divergence (unbounded gas accumulation) | 2nd stage uses demand-proportional flow: (P_amb - P_lung - P_crack) / R_open |
| 2nd stage unrealistic flow rates | Flow driven by demand pressure (~200 Pa), not full IP differential (~10 bar) |
| Hard stop singularity at t=0 | Removed for now; re-add with proper initialization |
| `R.f` balancing variable error | Through variables must use `branches` section, not direct equation reference |
| Domain param propagation | Requires inline node declaration: `A = domain(param = val)` |

### Tuned Parameter Values

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| 2nd stage R_open | 6000 Pa*s/mol | Gives regulator-limited tidal volume with 200 Pa effort |
| Exhale valve R_open | 9000 Pa*s/mol | Balances inhale rate for steady-state lung volume |
| IP volume | 100 mL (n_init=0.04518 mol) | Provides pressure state without affecting dynamics |
| BCD n_init | 0.298 mol | Approximately neutral buoyancy at 20m |
| n_tank initial | 98.47 mol | = 200e5 * 0.012 / (8.314 * 293.15) |

---

## Open Decisions / Risks

| Item | Status | Notes |
|------|--------|-------|
| Hard stop at surface | Deferred | Removed due to initialization singularity; re-add with initial depth away from contact |
| Valve discontinuities | Working | if/else formulation works with ode23t; may need tanh smoothing if solver struggles in edge cases |
| Gas mix switching | Deferred | Currently a parameter, not dynamic. Hot-switching needs additional architecture |
| BCD V_max overflow | Implemented | BCDBladder uses wall stiffness K_wall when V > V_max |
| Breathing controller fidelity | Complete | Stateflow 4-state machine replaces sine wave |
| test_breathing.slx | Unused | Legacy harness from Phase 3, can be deleted |

---

## Blockers

None currently. All prerequisites for Phase 7 (Dashboard) are in place. Controllers output correct signals and model runs stably for 120s+. Test suite validates all physics.

---

## Next Steps

### Phase 7: Dashboard & Visualization
1. Simulink Dashboard blocks: knobs (rate, depth), buttons (inflate, purge), gauges (depth, tank, BCD), scopes
2. Mode switch: manual vs. pre-programmed profiles
3. Real-time pacing for interactive simulation
4. `create_input_profiles.m` for scripted dive scenarios

### Remaining Phase 8 Polish
1. Re-integrate hard stop at surface with proper initialization
2. Parameter sweep / sensitivity analysis
3. Gas mix switching support
4. Delete unused `test_breathing.slx`
5. Documentation finalization

---

## How to Continue

1. Open MATLAB project: `openProject('L:\Projects\scuba')` or double-click `blank_project.prj`
2. Build the library: `run('scripts/build_library.m')` — compiles `.ssc` files into `scuba_lib`
3. Open the model: `open_system('scuba_buoyancy_sim')`
4. Run with default inputs: click Play (uses ground/zero for inports)
5. Run with timeseries inputs:
   ```matlab
   t = [0; 1800];
   ds = Simulink.SimulationData.Dataset;
   ds = ds.addElement(timeseries(15*ones(2,1), t), 'breathing_rate');
   ds = ds.addElement(timeseries(ones(2,1), t), 'breath_depth');
   ds = ds.addElement(timeseries(zeros(2,1), t), 'inflate_btn');
   ds = ds.addElement(timeseries(zeros(2,1), t), 'purge_btn');
   simIn = Simulink.SimulationInput('scuba_buoyancy_sim');
   simIn = simIn.setModelParameter('LoadExternalInput','on','ExternalInput','ds');
   out = sim(simIn);
   ```
6. Visualize: `plot_results(out)` after simulation completes
7. Run tests: `results = runtests('tests'); disp(results);`
8. Continue with Phase 7 per the plan above

---

## Key Physics Parameters (Quick Reference)

| Parameter | Value | Note |
|-----------|-------|------|
| rho_water | 1025 kg/m^3 | Saltwater |
| P_atm | 101,325 Pa | 1 atm |
| Tank | 12 L, 200 bar | 98.47 mol initial |
| IP offset | 10 bar above ambient | 1st stage set point |
| 2nd stage P_crack | 100 Pa | Work of breathing |
| 2nd stage R_open | 6000 Pa*s/mol | Regulator-limited delivery |
| Breathing rate | 15 bpm (0.25 Hz) | Relaxed diver |
| BCD max | 15 L | Bladder capacity |
| Wetsuit V_surface | 6.3 L | Gas volume at surface |
| Diver total mass | 89 kg | Body + belt + gear |
| Body volume | 78 L | Incompressible |
| Gear volume | 3 L | Incompressible |
