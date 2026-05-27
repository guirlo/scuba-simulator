# Project Handoff — Scuba Buoyancy Simulation

**Date:** 2026-05-27  
**Project:** scuba-buoyancy  
**Location:** `L:\Projects\scuba`  
**MATLAB version:** R2026a  
**Status:** Planning and scaffolding complete. Implementation not yet started.

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
| Plant — Mechanical | Simscape Translational (Position-Based, β=90°) | 1-DOF vertical motion, buoyancy force, drag, hardstop |
| Control | Simulink + Stateflow | Breathing state machine, BCD commands, dashboard UI |
| Coupling | Physical Signal (PS) ports | P_amb (mech→gas), volumes (gas→mech), commands (Simulink→gas) |

Key design principle: Gas flow is driven by **pressure differentials**, not command signals. The 2nd stage regulator opens physically when the diver's breathing effort creates suction. The BCD fills because opening the inflate valve exposes it to intermediate pressure.

---

## Files Created

### Project Infrastructure
| File | Purpose |
|------|---------|
| `blank_project.prj` | MATLAB Project file (name: "scuba-buoyancy") |
| `startup.m` | Loads params into workspace on project open |
| `shutdown.m` | Clears workspace on project close |
| `.gitignore` | Excludes slprj/, *.slxc, etc. |
| `.gitattributes` | Git LFS / line-ending config (auto-generated) |

### Parameters (implemented)
| File | Purpose |
|------|---------|
| `parameters/scuba_params.m` | Master configuration function (water, tank, diver, wetsuit, BCD, breathing, constants) |
| `parameters/gas_properties.m` | Gas mix lookup (Air, Nitrox 32%): O2/N2 fractions, molar mass |
| `parameters/diver_configs.m` | Preset configurations (beginner_tropical, experienced_cold, nitrox_warm) |

### Scripts (implemented)
| File | Purpose |
|------|---------|
| `scripts/run_simulation.m` | Programmatic sim runner (loads params, configures SimulationInput) |

### Documentation
| File | Purpose |
|------|---------|
| `docs/implementation_plan.md` | Final architecture and phase plan (custom gas domain approach) |
| `docs/test_plan.md` | 25 tests across 4 tiers with quantitative pass criteria |
| `docs/diary.md` | Design diary for blog post (records architecture iterations) |
| `docs/handoff.md` | This file |

---

## What Has NOT Been Created Yet

### Simscape Components (core physics — Phase 1–4)
```
+scuba/+gas/gas.ssc                          ← Domain definition
+scuba/+gas/branch.ssc                       ← Two-port base class
+scuba/+gas/+elements/GasDomainProperties.ssc
+scuba/+gas/+elements/GasTank.ssc
+scuba/+gas/+elements/FirstStageRegulator.ssc
+scuba/+gas/+elements/SecondStageRegulator.ssc
+scuba/+gas/+elements/Lungs.ssc
+scuba/+gas/+elements/ExhaleValve.ssc
+scuba/+gas/+elements/BCDInflateValve.ssc
+scuba/+gas/+elements/BCDBladder.ssc
+scuba/+gas/+elements/PurgeValve.ssc
+scuba/+gas/+elements/AmbientReference.ssc
+scuba/AmbientPressure.ssc
+scuba/BuoyancyForceSource.ssc
+scuba/HydrodynamicDrag.ssc
```

### Simulink Models (Phase 5–7)
```
models/scuba_buoyancy_sim.slx                ← Top-level model
models/subsystems/breathing_controller.slx   ← Stateflow
models/subsystems/bcd_controller.slx         ← BCD logic
```

### Scripts (remaining)
```
scripts/build_library.m                      ← sscbuild('scuba')
scripts/plot_results.m                       ← Post-simulation visualization
scripts/create_input_profiles.m              ← Dive profile generator
```

### Tests (Phase 8)
```
tests/tGasDomainBasic.m
tests/tRegulatorSetPoint.m
tests/tBreathingCycle.m
tests/tBCDInflateDeflate.m
tests/tWetsuitDrag.m
tests/tBuoyancyManeuvers.m
tests/tDiveProfiles.m
tests/tPhysicsValidation.m
```

---

## Implementation Phases (from plan)

| Phase | Focus | Status |
|-------|-------|--------|
| 1 | Domain foundation (gas.ssc, branch.ssc, GasTank, AmbientRef) | **Not started** |
| 2 | Regulators (1st stage, 2nd stage demand valve) | Not started |
| 3 | Breathing circuit (Lungs, ExhaleValve) | Not started |
| 4 | BCD circuit (InflateValve, Bladder, PurgeValve) | Not started |
| 5 | Mechanical domain coupling (AmbientPressure, BuoyancyForce, Drag) | Not started |
| 6 | Controllers (Stateflow breathing, BCD logic) | Not started |
| 7 | Dashboard, visualization, input profiles | Not started |
| 8 | Test suite, tuning, documentation | Not started |

---

## Key Design Decisions (Locked In)

1. **Custom gas domain** — Not Foundation Gas (overkill) or PS signals (not physical enough)
2. **Demand-driven breathing** — Muscular effort pressure triggers the regulator physically
3. **Molar flow as through variable** — Natural for ideal gas; conserved quantity
4. **Isothermal assumption** — T is a domain parameter, not dynamic state
5. **Position-based translational (β=90°)** — Depth = position, gravity built in
6. **Wetsuit compression exponent 0.7** — Empirical, accounts for neoprene structural constraint
7. **Physical topology mirrors real equipment** — Tank → 1st stage → IP → 2nd stage / BCD inflate → lungs/bladder → exhale/purge → water

---

## Key Physics Parameters (quick reference)

| Parameter | Value | Note |
|-----------|-------|------|
| ρ_water | 1025 kg/m³ | Saltwater |
| P_atm | 101,325 Pa | 1 atm |
| Tank | 12 L, 200 bar | ~985 mol initial |
| IP offset | 10 bar above ambient | 1st stage set point |
| 2nd stage P_crack | 100 Pa | Work of breathing |
| Tidal volume | 0.5 L | Normal breath |
| Breathing rate | 15 bpm | Relaxed diver |
| BCD max | 15 L | Bladder capacity |
| Wetsuit V_surface | 6.3 L | Gas volume at surface |
| Diver total mass | 89 kg | Body + belt + gear |

---

## How to Continue

1. Open the MATLAB project: double-click `blank_project.prj` or `openProject('L:\Projects\scuba')`
2. Start with **Phase 1**: create `+scuba/+gas/gas.ssc` and `branch.ssc`
3. Build library after each .ssc change: `sscbuild('scuba')`
4. Follow the phase plan in `docs/implementation_plan.md`
5. Validate incrementally using tests from `docs/test_plan.md`
6. Update `docs/diary.md` with progress for the blog post

---

## Open Questions / Risks

- **Regulator numerical formulation**: The 1st stage ideally "sets" output pressure, but this creates an algebraic constraint. May need small flow resistance for solver stability.
- **BCD full condition**: When bladder hits V_max, internal pressure must rise to stop inflow. May need conditional stiffness or overflow valve logic.
- **Valve discontinuities**: if/else in .ssc can cause solver difficulty. May need smooth transitions (tanh-based switching) for robustness.
- **Hardstop stiffness**: Very stiff spring at surface can slow the solver. Tune for stability vs. realism.
- **Gas mix switching**: Currently a parameter, not dynamic. Hot-switching mid-dive (for stage bottles) would require additional architecture.
