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

### Simulink Model Build (scuba_buoyancy_sim.slx)

Used programmatic model construction (`model_edit` tool) to build the top-level model:
- **Gas circuit**: GasTank → FirstStageRegulator → GasVolume(IP) → SecondStageRegulator → Lungs → ExhaleValve → AmbientReference. Branch from IP: BCDInflateValve → BCDBladder → PurgeValve → same AmbientReference.
- **Mechanical circuit**: Translational Mass (89 kg) between two Mechanical Translational References. Connected to AmbientPressure, BuoyancyForceSource, HydrodynamicDrag, and Ideal Translational Motion Sensor.
- **Coupling**: P_amb physical signal distributes from AmbientPressure to all gas components needing depth-dependent pressure. V_bcd and V_lungs feed back from gas accumulators to BuoyancyForceSource.
- **Control inputs**: Sine wave breath_effort (200 Pa, 0.25 Hz), constants for inflate/purge commands (both 0).

Key decisions during model build:
1. **Gravity integrated into BuoyancyForceSource** — eliminated separate Ideal Force Source because PS connection between SPS converter and force source failed. The component now computes `f == F_weight - F_buoy` directly.
2. **Hard stop removed** — caused singular matrix at t=0 with diver initialized at 20m. Will re-add in Phase 8 with proper initial conditions.
3. **BCD n_init = 0.298 mol** — calculated analytically for neutral buoyancy at 20m: need V_total = m/ρ = 89/1025 = 0.08683 m³, solve for n_bcd given all other volumes at that depth.

### Model Verification

Ran 120s simulation successfully:
- Diver starts at 20m, breathes steadily at 15 bpm
- Slow ascent due to BCD expansion positive feedback (expanding gas → more buoyancy → shallower → gas expands more)
- Stabilizes around 15–16m (BCD expansion balances wetsuit compression loss)
- Tank consumes ~0.36 mol (correct order: at 20m, ~3 atm absolute, ~0.003 mol/breath × 30 breaths/min × 2 min)
- Lung volume oscillates with correct ~500mL tidal swing
- All physics coupling working: depth ↔ pressure ↔ gas volumes ↔ buoyancy ↔ acceleration ↔ depth

### Git Repository

Initial commit pushed to `origin/master` at `insidelabs-git.mathworks.com:grouleau/scuba-buoyancy.git`. Contains all Phase 1–5 deliverables (92 files, 2290 insertions).

---

## Phase 6: Controllers (2026-05-27)

### Stateflow Breathing Controller

Replaced the sine wave `breath_effort` source with a 4-state Stateflow chart:
- States: INHALE → PAUSE_POST_INHALE → EXHALE → PAUSE_POST_EXHALE
- Waveform: half-sine shape during active phases (peak ±200·breath_depth Pa), zero during pauses
- Timing: 40% inhale, 10% pause, 35% exhale, 15% pause (per cycle = 60/rate seconds)
- Inputs: `breathing_rate` (bpm), `breath_depth` (0–1 scalar)
- Discrete sample time: 0.01s

Measured results at 15 bpm: period=4.04s (target 4.0), duty cycle 39/34/28% (target 40/35/25%).

### BCD Controller

3-state Stateflow chart (IDLE / INFLATING / PURGING):
- Mutual exclusion: inflate takes priority when both buttons pressed simultaneously
- Direct pass-through of button state to valve commands (no timing/debounce — can add in Phase 7)
- Verified: inflate produces flow, purge produces flow, both pressed → only inflate fires

### Model Reorganization

Restructured the flat top-level into subsystem hierarchy:
```
scuba_buoyancy_sim (root)
├── Inports: breathing_rate, breath_depth, inflate_btn, purge_btn
├── Controllers    — Stateflow charts (breathing + BCD)
├── GasCircuit     — Tank, regulators, lungs, BCD, valves, SPS converters
└── Mechanics      — Mass, buoyancy, drag, motion sensor, scopes
```

Key coupling connections between subsystems:
- Controllers → GasCircuit: breath_effort, inflate_cmd, purge_cmd (Simulink signals)
- GasCircuit ↔ Mechanics: P_amb, V_bcd, V_lungs (physical signals)

### Root-Level Inports

Replaced the 4 Constant blocks (BreathingRate, BreathDepth, InflateBtn, PurgeBtn) with root-level Inport blocks. This enables feeding timeseries via `Simulink.SimulationData.Dataset` for scripted dive profiles in Phase 7.

### Simulation Results (Phase 6, 120s)

- Depth: 20.3m → 18.9m (less drift than sine wave due to pause phases)
- Tank consumed: 0.278 mol (vs 0.36 with sine — pauses reduce active breathing time)
- Behavior physically correct and stable

### Next Steps

- Phase 7: Dashboard with interactive controls, dive profile scripts
- Phase 8: Test suite, hard stop re-integration, parameter sweep

---

## 2026-05-28 — Two-Tier Depth Controller: Breathing Trim + BCD

### Motivation

The existing depth controller used only BCD inflate/purge (binary bang-bang), producing ±2m oscillations during bottom phase. In real diving, BCD is for large maneuvers; fine depth adjustments come from modulating breathing pattern — inhaling deeper to ascend slightly, exhaling more fully to descend. This session added a breathing-based inner control loop for realistic fine-trim depth holding.

### Architecture: Two-Tier Control Hierarchy

```
depth_error
    ├── |error| < 0.3m  → dead zone (no action)
    ├── 0.3m < |error| < 2.0m → BREATHING BIAS (inner loop, fine trim)
    │         breath_bias ∈ [-1, +1]
    │         → duty cycle shift (±10%)
    │         → amplitude asymmetry (±30%)
    │         → time-averaged lung volume shift → buoyancy trim
    └── |error| > 2.0m → BCD inflate/purge (outer loop, coarse)
```

### Implementation

**DepthController MATLAB Function block** — added `breath_bias` as third output:
- Proportional gain with 0.3m dead zone, saturates at ±1 at 1.5m error
- Velocity damping (K_vel = 0.8 s/m) prevents oscillation around setpoint
- BCD bang-bang retained for |error| > 2m with rate limiting

**BreathingController Stateflow chart** — added `breath_bias` input:
- Bias latched once per breath cycle (at INHALE entry) to prevent mid-breath waveform discontinuities
- Duty cycle shift: inhale fraction 0.40 ± 0.05×bias, exhale fraction 0.35 ∓ 0.05×bias
- Amplitude asymmetry: inhale effort = 200×depth×(1 + 0.3×max(0,bias)), exhale mirrored
- Combined effect: ~0.1–0.2L time-averaged lung volume shift → 1–2N sustained trim force

**Signal routing** — BiasSwitch (Switch block, threshold 0.5 on auto_depth):
- auto_depth=1 → DepthController breath_bias passes through
- auto_depth=0 → ZeroBias constant → symmetric breathing (manual mode)

**Parameters** — new `params.breathControl.*` section in `scuba_params.m`, exposed as `bc_*` workspace variables.

### Bugs Discovered and Fixed

1. **Persisted block parameters from `run_full_dive.m`**: Prior session had hardcoded numeric values into BuoyancyForce (m_total=93), AmbientPressure (depth_init=1), and BCDBladder (n_init=0.05) via `set_param`. All tests broke with massive errors. Fix: restored workspace variable references (`'ic_depth'`, `'bcd_n_init'`, `'diver_m_total'`).

2. **DepthMemory IC causing first-cycle bias inversion**: Memory block had IC='1' (surface start from dive profile). At t=0 with ic_depth=20m, DepthController received depth_actual=1 instead of 20, computing depth_error=-17m → bias=-1 (wrong sign). First breath cycle had stronger exhale instead of stronger inhale. Fix: set Memory IC to `'ic_depth'` workspace variable.

3. **Test assertions vs Boyle instability**: Breathing trim produces correct initial motion, but Boyle expansion positive feedback overwhelms it after a few seconds at 20m depth. Tests adjusted to verify first-cycle corrective direction rather than steady-state convergence.

### Tuning Iterations

Started with plan values (deadzone=0.5m, saturation=2.5m, bcdDeadband=3m). Three rounds of simulation-driven tuning converged to:
- deadzone=0.3m, saturation=1.5m (more responsive inner loop)
- K_vel=0.8 s/m (aggressive damping for 4s breath period lag)
- bcdDeadband=2.0m (narrower than planned — breathing alone can't overcome Boyle instability for large errors)

### Test Results

New test class `tests/tBreathingControl.m` (7 tests):
- testZeroBiasSymmetric — manual mode produces symmetric breathing
- testPositiveBiasIncreasesLungMoles — positive bias → more moles per inhale
- testNegativeBiasDecreasesLungMoles — negative bias → fewer mean moles
- testContinuousBreathing — diver never stops breathing even at max bias
- testBCDInactiveForSmallError — BCD silent for |error| < 2m
- testBCDFiresForLargeError — BCD active for |error| > 2m
- testBreathingTrimDirection — positive bias produces initial ascent

All 48 tests passing (41 existing + 7 new).

### Full Dive Profile (36 min)

With breathing control active: mean depth error 0.49m, std 1.86m, tank consumption 104 bar. Bottom phase shows tighter tracking with breathing trim providing continuous fine adjustment between BCD bursts.

### Key Insight

Breathing-based depth control is inherently limited by Boyle's law positive feedback: as the diver ascends, lung gas expands, increasing buoyancy, accelerating ascent. At 20m depth, this instability grows faster than the ~4s breath cycle can correct. The controller works as a fine-trim stabilizer within its authority band but cannot replace BCD for errors exceeding ~1.5m. The two-tier architecture correctly delegates based on each actuator's physical authority.

---

## 2026-05-28 through 2026-06-14 — Major Architecture Refactoring

### Motivation

The original architecture used a centralized coupling approach: a separate `AmbientPressure` sensor block computed P_amb from depth and distributed it via PS wires to every gas component. A centralized `BuoyancyForceSource` summed all volumes and applied Archimedes force. A separate `HydrodynamicDrag` block handled drag. This worked but was fragile to wire, and the `p_amb` domain variable added unnecessary complexity.

### Key Changes

1. **Removed P_amb from gas domain** — `underwaterGas.ssc` now has only `p` (across) and `n_dot` (through). No domain-level ambient pressure propagation.

2. **Added translational port to gas components** — GasTank, FirstStageRegulator, SecondStageRegulator, Lungs, BCDBladder, and AmbientReference each gained a `foundation.translational.translational` node (`R`). Each computes `P_amb = P_atm + rho_water * R.gravity * R.x` locally.

3. **Distributed buoyancy forces** — Lungs applies `F_buoy = rho_water * g * V_lungs` through its translational port. BCDBladder applies `F_buoy = rho_water * g * V_bcd`. GasTank applies gas weight `n_tank * M_gas * g`.

4. **Created DiverBody** — Single component combining body mass, body buoyancy (fixed volume), and quadratic drag. Equation: `f == mass*der(R.v) - mass*R.gravity + F_buoy + F_drag`.

5. **Removed old mechanical components** — `AmbientPressure.ssc`, `BuoyancyForceSource.ssc`, `HydrodynamicDrag.ssc` deleted.

6. **Added OPRV** — `OverpressureReliefValve.ssc` for passive BCD overpressure relief (3 psi cracking pressure).

7. **Added hard stops** — `Surface and Bottom` subsystem with spacer + hard-stop pairs provides physical depth limits.

8. **Replaced `let/in/end` with `intermediates`** — All components updated to modern Simscape syntax.

9. **Simplified controller** — Old two-tier MATLAB Function block + breathing bias removed. Replaced with simple Stateflow chart (drop → float → done) in harness.

10. **Deleted old model and tests** — `scuba_buoyancy_sim.slx` and all 9 test classes removed. New primary model is `bcd_buoyancy_with_tank_harness.slx`.

11. **Library output moved** — `sscbuild('scuba','-output','models')` places `scuba_lib.slx` in `models/` rather than project root.

12. **Created Scuba_Diver.slx** — Reusable plant model (same topology as Plant subsystem in harness) with clean 3-input/2-output interface.

### Design Rationale

The translational-port approach is more modular: each component is self-contained and doesn't need external P_amb wiring. Adding or removing a component from the mechanical network automatically includes/excludes its force contribution. The gas domain stays pure (pressure + flow) while depth coupling happens through the shared translational domain.

### What Was Lost

- Wetsuit compression (was computed in BuoyancyForceSource) — not yet re-added
- Full test suite (48 tests) — needs rewrite for new model topology
- Two-tier breathing depth controller — replaced by simpler Stateflow
- 36-minute dive profile scripting — `run_full_dive.m` references old model
- `shutdown.m` — removed
