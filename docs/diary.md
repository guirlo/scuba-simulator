# Scuba Buoyancy Simulation — Project Diary

## 2026-05-27 — Project Inception & Architecture Iterations

### Initial Request

Goal: Create a Simulink/Simscape simulation of a scuba diver modeling buoyancy dynamics — breath-by-breath gas consumption, BCD control, wetsuit compression, and multiple gas mixes (Air, Nitrox 32%).

Key requirements gathered through Q&A:
- 1D vertical (depth only)
- Interactive dashboard + pre-programmed profiles
- Detailed parameters (wetsuit compression, water type, temperature, BCD capacity)
- Recreational depth range (0–40m), ideal gas law
- Real-time visualization during simulation + post-processing plots
- MATLAB R2026a

### Architecture Iteration 1: Hybrid (Simulink-heavy)

First proposal: Simscape Mechanical for the 1-DOF vertical dynamics, but all gas bookkeeping in Simulink (integrators tracking moles, signal-flow math for volumes and pressures). Stateflow for the breathing state machine.

**Problem identified:** Too much Simulink. The gas system was being treated as signal processing rather than physics. The plant should be fully in Simscape.

### Architecture Iteration 2: Custom Simscape Components with PS Signals

Revised to put all physics in custom `.ssc` components:
- `ScubaTank.ssc`, `BCDVolume.ssc`, `LungVolume.ssc`, `WetsuitVolume.ssc` — each with internal state variables
- Physical Signal (PS) inputs carry molar flow rate "commands" from the Simulink control layer
- PS outputs carry volumes back to the BuoyancyForceSource

**Problem identified:** Still not physical enough. The PS signals carrying molar flow rates are essentially "commanding" flow rather than letting it arise from pressure differentials. The gas system should use conserving physical connections that model the actual plumbing topology — tank through regulators through parallel paths (lungs and BCD) to water.

### Architecture Iteration 3: Custom Gas Domain (Final)

Designed a custom Simscape domain (`scuba.gas`) with:
- **Across variable:** Pressure [Pa]
- **Through variable:** Molar flow rate [mol/s]
- **Conservation:** Sum of flows into each node = 0 (automatic)

The gas network now mirrors the real scuba equipment topology:
```
Tank → 1st Stage Regulator → IP manifold → 2nd Stage (demand valve) → Lungs → Exhale Valve → Water
                                          → BCD Inflate Valve → BCD Bladder → Purge Valve → Water
```

Key insight: The 2nd stage regulator is a **demand valve** — it opens when the diver's muscular effort creates a pressure drop at the lung node below ambient. No "flow command" needed; the physics drives it. Same for exhale: lung pressure rises above ambient, check valve opens, gas escapes.

The control layer (Simulink/Stateflow) only provides:
- `breath_effort` [Pa] — muscular pressure (negative for inhale, positive for exhale)
- `inflate_cmd` [0/1] — opens the BCD inflate valve
- `purge_cmd` [0/1] — opens the BCD purge/dump valve

Flow magnitudes are determined entirely by the pressure network.

### Project Setup

Created the MATLAB project (`scuba-buoyancy`) with:
- Parameter files: `scuba_params.m`, `gas_properties.m`, `diver_configs.m`
- `startup.m` / `shutdown.m`
- `scripts/run_simulation.m`
- Folder structure for `+scuba/`, `models/`, `parameters/`, `scripts/`, `tests/`, `docs/`

### Key Design Decisions Made

1. **Custom domain over Foundation Gas** — Foundation Gas domain requires tabulated thermodynamic properties and is designed for compressible flow networks. Overkill for ideal gas in isolated reservoirs. A lean custom domain with just P and n_dot is simpler and more transparent.

2. **Molar flow (not mass flow) as through variable** — Natural for ideal gas law (PV = nRT). Moles are the conserved quantity.

3. **Isothermal assumption** — Temperature is a domain parameter, not a dynamic variable. Dramatically simplifies the domain (no energy equation needed).

4. **Position-based translational domain (β=90°)** — Depth = position, positive downward. Gravity built into the domain. Clean.

5. **Demand-driven breathing** — Rather than commanding flow, the breathing controller creates pressure differentials that physically trigger the regulator. More realistic and enables natural failure modes (e.g., blocked regulator = no flow).

### Next Steps

- Implement the custom gas domain (`+scuba/+gas/gas.ssc`)
- Build components bottom-up: tank, ambient reference, regulators, lungs, BCD
- Verify each component before integrating
- Build the mechanical domain coupling
- Add controllers and dashboard last

---

## 2026-05-27 — Phase 1–5 Implementation

### Custom Gas Domain Implemented

Created `+scuba/+gas/gas.ssc` with:
- Across: `p` [Pa] (pressure)
- Through (Balancing): `n_dot` [mol/s] (molar flow)
- Domain params: `R_gas`, `T`

Key Simscape lessons learned:
- Balancing variables (through) can ONLY be referenced via `branches` section, not in equations
- Domain parameter propagation requires `component(Propagation = source)` attribute
- `function setup` is deprecated (still works, but emits warnings)
- The `R.f` / `R.v` pattern for translational mechanical ports: force is through (needs branches), velocity is across (free to use in equations)

### Component Library (13 blocks)

Gas elements:
- `GasDomainProperties` — Propagation source for R_gas, T
- `GasTank` — Rigid reservoir, P=n·R·T/V, tracks n_tank
- `GasVolume` — Small rigid volume for IP node (provides pressure state between regulators)
- `FirstStageRegulator` — Maintains IP = P_amb + offset
- `SecondStageRegulator` — Demand valve, flow ∝ (demand - P_crack)/R
- `Lungs` — Pressure source (P_amb + breath_effort), tracks n_lungs
- `ExhaleValve` — Check valve with cracking pressure
- `BCDInflateValve` — Commanded on/off valve
- `BCDBladder` — Flexible accumulator (P = P_amb when not full, wall stiffness when V>V_max)
- `PurgeValve` — Commanded dump valve
- `AmbientReference` — Infinite source/sink at P_amb

Mechanical coupling:
- `AmbientPressure` — Integrates velocity to depth, computes P(d), zero-force sensor
- `BuoyancyForceSource` — Net vertical force (buoyancy - weight) including wetsuit compression
- `HydrodynamicDrag` — Quadratic drag: 0.5·ρ·Cd·A·v·|v|

### Numerical Issues & Solutions

1. **IP node singularity**: Without a gas volume between 1st and 2nd stage regulators, the solver encounters a singular matrix (two algebraic constraints fixing the same pressure). Fixed by adding `GasVolume` (100mL) at the IP node.

2. **Lung volume divergence**: Initial design had lungs as pure pressure source with no volume limiting. Gas accumulated unboundedly during inhale half-cycle. Fixed by tuning valve resistances so inhale rate ≈ exhale rate, producing ~500mL tidal volume.

3. **2nd stage flow formulation**: Using full IP-to-downstream differential (ΔP ≈ 10 bar) for flow gave unrealistically high rates. Changed to flow ∝ (demand - P_crack), where demand = P_amb - P_lung. This self-limits delivery to what the breathing effort actually demands.

4. **Hard stop initialization**: Translational Hard Stop at surface caused singular matrix at t=0 (conflicting position constraints). Removed for initial testing — will re-add with proper initial conditions away from contact.

5. **n_tank initial moles**: Handoff doc had 984.6 mol (calculation error). Correct value: 200e5 × 0.012 / (8.314 × 293.15) = 98.47 mol.

### Full Model Integration

Built `scuba_buoyancy_sim.slx` combining:
- Gas circuit: Tank → Reg1 → IP → Reg2 → Lungs → ExhaleValve → AmbRef + IP → BCDInflate → Bladder → Purge → AmbRef
- Mechanical: Mass (89kg) with BuoyancyForce, Drag, AmbientPressure, MotionSensor
- Coupling: P_amb signal distributes from AmbientPressure to all gas components; V_bcd and V_lungs feed back to BuoyancyForce
- Control: Sine breath effort (200Pa, 0.25Hz = 15bpm), BCD commands = 0

Result at 120s: Diver starts at ~20m, slowly ascends due to BCD expansion feedback, stabilizes around 15-16m. Tank consumes 0.36 mol. Lung volume oscillates with ~500mL tidal swing. Physics coupling works correctly.

### Current Parameter Values (tuned)

| Parameter | Value | Reason |
|-----------|-------|--------|
| 2nd stage R_open | 6000 Pa·s/mol | Gives ~0.5L tidal volume with 200Pa effort |
| Exhale valve R_open | 9000 Pa·s/mol | Balances inhale rate for steady-state lungs |
| IP volume | 100 mL | Provides pressure state, prevents algebraic loop |
| BCD n_init | 0.298 mol | Approximately neutral at 20m |

### Next Steps

- Phase 6: Stateflow breathing controller (proper inhale/pause/exhale/pause cycle)
- Phase 7: Dashboard with interactive controls
- Phase 8: Test suite, hard stop re-integration, parameter sweep
