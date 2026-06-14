# Scuba Diver — Full-Dive Harness Implementation Plan

## Status: Not Started
**Last Updated:** 2026-06-14  
**Architecture Spec:** [scuba-diver-architecture.md](scuba-diver-architecture.md)  
**Test Plan:** [scuba-diver-test-plan.md](scuba-diver-test-plan.md)

---

## 1. Progress Summary

| Phase | Status | Subsystems |
|-------|--------|------------|
| Phase 0: Interface & Profile Infrastructure | 🔲 Not Started | Parameter scripts, profile generators |
| Phase 1: Breathing Generator | 🔲 Not Started | Respiratory waveform subsystem |
| Phase 2: Dive Profile Controller | 🔲 Not Started | Stateflow dive FSM + BCD controller |
| Phase 3: Harness Integration | 🔲 Not Started | full_dive_test.slx assembly |
| Phase 4: Multi-Scenario Validation | 🔲 Not Started | All 4 scenarios from system spec |

---

## 2. Model Hierarchy

```
full_dive_test.slx (root)
├── Dive Profile (Stateflow or From Workspace)     # Generates depth_target, phase signals
├── Breathing Generator (Subsystem)                 # Sinusoidal breath_effort signal
│   ├── Breath Oscillator                          # sin(2π × rate/60 × t) with amplitude
│   └── Depth-Scaled Effort                        # Effort scales with depth for realistic WOB
├── BCD Controller (Stateflow or MATLAB Fcn)       # Depth error → inflate/purge commands
│   ├── Descent logic (inflate for rate control)
│   ├── Hold logic (deadband + periodic corrections)
│   └── Ascent logic (vent to limit ascent rate)
├── Plant (Model Reference → Scuba_Diver.slx)     # 3 in, 2 out
├── Gas Consumption Monitor (Subsystem)            # Integrates flow, computes SAC
├── Safety Monitor (Subsystem)                     # Rate limits, ceiling violations
├── Logging & Scopes                               # Key signals for post-processing
└── Stop Simulation (Stop block)                   # Depth < 0 or tank empty
```

---

## 3. Dependencies

### 3.1 MATLAB Toolbox Dependencies

| Toolbox | Required For | Required? |
|---------|-------------|-----------|
| Simulink | All | Yes |
| Simscape | Plant model physics | Yes |
| Stateflow | Dive profile FSM, BCD controller | Yes |
| Simscape (custom library) | Gas domain components | Yes (rebuild with `sscbuild`) |

### 3.2 Deliverables

| Asset | Path | Description |
|-------|------|-------------|
| Plant model | `models/Scuba_Diver.slx` | Reusable plant: 3 inports, 2 outports |
| Descent test harness | `models/descent_test.slx` | Simple drop-and-hold for initial validation |
| Full-dive test harness | `models/full_dive_test.slx` | Multi-scenario dive profile harness |
| Parameter file | `parameters/scuba_params.m` | Master parameter configuration |
| Gas properties | `parameters/gas_properties.m` | Gas mix lookup (air, nitrox32) |
| Diver configs | `parameters/diver_configs.m` | Preset configurations (beginner, experienced, nitrox) |
| Profile generator | `scripts/dive_profiles.m` | Multi-scenario dive profile function |
| Compiled library | `models/scuba_lib.slx` | Built from .ssc source via `sscbuild` |

---

## 4. Workstream Graph

```
                    Phase 0: Interface & Profile Infrastructure
                    (freeze plant ports, create profile functions, create params)
                                    │
               ┌────────────────────┼────────────────────┐
               │                    │                    │
        ┌──────▼──────┐     ┌──────▼──────┐     ┌──────▼──────┐
        │ Breathing    │     │ Dive Profile │     │ BCD         │
        │ Generator    │     │ State Machine│     │ Controller  │
        │ (Phase 1)    │     │ (Phase 2a)   │     │ (Phase 2b)  │
        └──────┬──────┘     └──────┬──────┘     └──────┬──────┘
               │                    │                    │
               └────────────────────┼────────────────────┘
                                    │
                    Phase 3: Harness Integration
                    (wire all subsystems + plant, configure solver, add monitors)
                                    │
                    Phase 4: Multi-Scenario Validation
                    (run all profiles, validate against acceptance criteria)
```

---

## 5. Build Phases

### Phase 0: Interface & Profile Infrastructure
**Goal:** Create parameter infrastructure, dive profile functions, and define plant interface contract  
**Duration:** 2–3 hours

| Step | Operation | Details |
|------|-----------|---------|
| 0.1 | Create `scuba_params.m` | Master parameter function returning full configuration struct |
| 0.2 | Create `gas_properties.m` | Gas mix lookup (air, nitrox32) |
| 0.3 | Create `load_plant_params.m` | Flattens struct into workspace variables for Simscape blocks |
| 0.4 | Create `initWorkspace.m` | Project startup script calling param loaders |
| 0.5 | Create `dive_profiles.m` | Function returning profile struct for each scenario (depths, times, rates) |
| 0.6 | Create `compute_bcd_init_moles.m` | Helper: given target_depth, compute n_bcd for neutral buoyancy |
| 0.7 | Document sign conventions | Add comment header to harness matching architecture spec §6.4 |

**Verification:**
- `initWorkspace` runs without error
- `dive_profiles('square_18m')` returns valid struct
- `compute_bcd_init_moles(20)` ≈ 0.298 mol

**Checkpoint 0:** Infrastructure ready; interface contract frozen; profile functions tested.

---

### Phase 1: Breathing Generator Subsystem
**Goal:** Create a reusable subsystem that generates realistic breath_effort signal  
**Duration:** 2 hours

| Step | Operation | Details |
|------|-----------|---------|
| 1.1 | Design waveform | Sinusoidal: `effort = -A × sin(2π × f × t)` where f = rate/60, A = 200 Pa |
| 1.2 | Add asymmetry option | Optional: inhale faster than exhale (duty cycle 40/60 split) |
| 1.3 | Add depth scaling | Work of breathing increases with gas density: A_eff = A × (1 + depth/40) |
| 1.4 | Parameterize | Inputs: breathing_rate [bpm], amplitude [Pa], depth [m] |
| 1.5 | Build subsystem | Simulink subsystem with Clock → sin function → Gain → output |
| 1.6 | Test standalone | Drive with constant depth, verify waveform shape and frequency |

**Waveform specification:**

```
breath_effort(t) = -A_base × (1 + depth/40) × sin(2π × (rate/60) × t)

Where:
  A_base = 200 Pa (peak muscular pressure, Held & Pendergast 2013)
  rate = 15 bpm (default)
  depth = current depth from plant output [m]
  
Negative half-cycle = inhale (creates suction, opens 2nd stage)
Positive half-cycle = exhale (creates pressure, opens exhale valve)
```

**Verification:**
- At surface (depth=0): peak effort = ±200 Pa, frequency = 0.25 Hz
- At 30m: peak effort = ±350 Pa (depth scaling active)
- 2nd stage opens during negative half-cycle (verified in plant)

**Checkpoint 1:** Breathing subsystem produces correct waveform; plant responds with gas flow.

---

### Phase 2a: Dive Profile State Machine
**Goal:** Stateflow chart that sequences through dive phases and outputs depth_target  
**Duration:** 3 hours

| Step | Operation | Details |
|------|-----------|---------|
| 2a.1 | Define states | SURFACE → DESCEND → BOTTOM → ASCEND → SAFETY_STOP → FINAL_ASCENT → SURFACED |
| 2a.2 | Define transitions | Time-based or depth-based triggers per profile struct |
| 2a.3 | Implement depth_target ramp | Linear interpolation between waypoints at prescribed rates |
| 2a.4 | Add phase output | Enum signal indicating current phase (for BCD controller) |
| 2a.5 | Parameterize from profile struct | All depths, durations, rates come from workspace struct |
| 2a.6 | Test with ideal depth follower | Verify profile timing matches `dive_profiles()` output |

**State machine design:**

```
SURFACE (t < t_start)
  → DESCEND [on: t ≥ t_start]
     depth_target ramps from start_depth to target_depth at descent_rate
  → BOTTOM [on: depth_target reached]
     depth_target = bottom_depth (constant)
     For multi-level: sequence of sub-targets
  → ASCEND [on: bottom_time elapsed]
     depth_target ramps up at ascent_rate (max 9 m/min)
     For stepped: hold at intermediate depths
  → SAFETY_STOP [on: depth_target = safety_depth]
     Hold at 5m for safety_duration
  → FINAL_ASCENT [on: safety time elapsed]
     depth_target ramps to 1m at 3 m/min
  → SURFACED [on: depth_target = 1m]
     Simulation continues until stable or stop time
```

**Verification:**
- Profile timing matches `dive_profiles()` specification
- Ascent rate never exceeds 0.167 m/s (10 m/min) in output
- State transitions occur at correct times/depths

---

### Phase 2b: BCD Controller
**Goal:** Controller that manages inflate/purge to track depth_target  
**Duration:** 3 hours

| Step | Operation | Details |
|------|-----------|---------|
| 2b.1 | Define control law | Proportional + rate-limited BCD commands based on depth error and velocity |
| 2b.2 | Phase-dependent gains | Different behavior for descent (allow sink), hold (tight), ascent (vent) |
| 2b.3 | Implement in Stateflow or MATLAB Function | Inputs: depth, vel, depth_target, phase → Outputs: inflate_cmd, purge_cmd |
| 2b.4 | Add safety overrides | Max ascent rate limiter: force purge if ascending > 10 m/min |
| 2b.5 | Anti-windup | Don't continuously inflate when at surface (depth < 2m) |
| 2b.6 | Tune gains | Iterate until Scenario 1 shows < ±0.5m depth error in hold |

**Control law design:**

```
depth_error = depth_target - depth  (positive = too shallow, need to descend)
vel_error = desired_vel - vel       (desired_vel from depth_target derivative)

DESCENT phase:
  inflate_cmd = 0 (let gravity pull down)
  purge_cmd = 0
  If vel > max_descent_rate: inflate_cmd = K_brake × (vel - max_descent_rate)

HOLD phase:
  If depth_error > deadband:   inflate_cmd = 0; purge_cmd = K_p × depth_error
  If depth_error < -deadband:  inflate_cmd = K_p × |depth_error|; purge_cmd = 0
  If |depth_error| < deadband: inflate_cmd = 0; purge_cmd = 0
  Velocity damping: purge_cmd += K_d × max(0, -vel)  (if rising, vent a bit)
                    inflate_cmd += K_d × max(0, vel)   (if sinking, inflate a bit)

ASCEND phase:
  purge_cmd = K_ascent × max(0, P_boyle_expansion_rate)  (preemptive venting)
  If |vel| > max_ascent_rate: purge_cmd = 1.0 (emergency vent)
  inflate_cmd = 0

SAFETY_STOP phase:
  Same as HOLD but tighter deadband (0.2m)

Parameters:
  K_p = 2.0 (1/m) — proportional gain
  K_d = 5.0 (s/m) — velocity damping
  K_brake = 10.0 (s/m) — descent rate braking
  K_ascent = 0.5 — ascent vent gain
  deadband = 0.3 m — depth error tolerance
  max_descent_rate = 0.5 m/s
  max_ascent_rate = 0.167 m/s (10 m/min)
```

**Verification:**
- In HOLD at 20m: depth oscillation < ±0.5m
- During ASCENT: velocity never exceeds 0.167 m/s for more than 2s
- During DESCENT: velocity stays below 0.5 m/s
- No chattering (inflate and purge not simultaneously active)

---

### Phase 3: Harness Integration
**Goal:** Assemble `full_dive_test.slx` with all subsystems wired to plant  
**Duration:** 3 hours

| Step | Operation | Details |
|------|-----------|---------|
| 3.1 | Create new model | `models/full_dive_test.slx` — blank Simulink model |
| 3.2 | Add Model Reference | Reference `Scuba_Diver.slx` as plant |
| 3.3 | Wire breathing generator | depth output → breathing gen → breath_effort input |
| 3.4 | Wire dive profile | Profile chart → depth_target → BCD controller |
| 3.5 | Wire BCD controller | depth, vel, depth_target, phase → inflate_cmd, purge_cmd |
| 3.6 | Add monitoring | Gas consumption integrator, safety monitor, scopes |
| 3.7 | Configure solver | ode23t, RelTol=1e-4, MaxStep=0.1 |
| 3.8 | Add initialization callback | Model InitFcn: `initWorkspace; profile = dive_profiles('square_18m');` |
| 3.9 | Add stop conditions | Depth < 0 OR tank_moles < 1 (reserve pressure) |
| 3.10 | Add logging | To Workspace blocks or Simscape logging for truth outputs |

**Verification:**
- Model compiles without errors
- Runs Scenario 1 (square 18m) to completion
- Depth, velocity, tank pressure signals look physically reasonable
- No solver failures or NaN values

**Checkpoint 3:** Harness runs end-to-end for at least one scenario.

---

### Phase 4: Multi-Scenario Validation
**Goal:** Run all 4 scenarios, validate against acceptance criteria from system spec  
**Duration:** 2–3 hours

| Step | Operation | Details |
|------|-----------|---------|
| 4.1 | Run Scenario 1 | Square 18m, 45 min — validate SAC, depth stability |
| 4.2 | Run Scenario 2 | Multi-level 30→20→10m — validate level transitions |
| 4.3 | Run Scenario 3 | Deep bounce 40m — validate large BCD changes, OPRV |
| 4.4 | Run Scenario 4 | Shallow 10m, 60 min — validate endurance, low activity |
| 4.5 | Create `run_scenarios.m` | Script that runs all 4 and generates comparison plots |
| 4.6 | Tune controller | Adjust gains if any scenario fails acceptance criteria |
| 4.7 | Document results | Record actual metrics vs targets in test plan |

**Checkpoint 4:** All 4 scenarios pass acceptance criteria; results documented.

---

## 6. Parameter Table

### Plant Parameters (from `scuba_params.m`)

| Parameter | Symbol | Value | Unit | Source | Block Path |
|-----------|--------|-------|------|--------|------------|
| Tank volume | V_tank | 0.012 | m³ | AL80 spec (Catalina catalog) | Plant/GasTank |
| Tank start pressure | P_tank_0 | 200e5 | Pa | Standard fill | Plant/GasTank |
| Tank start moles | n_tank_0 | 98.47 | mol | PV/RT derived | Plant/GasTank |
| Gas molar mass | M_gas | 0.029 | kg/mol | Air (78% N₂ + 21% O₂) | Plant/GasTank |
| 1st stage IP offset | IP_offset | 10e5 | Pa | EN 250 typical (8-11 bar) | Plant/FirstStageReg |
| 1st stage resistance | R_1st | 1e3 | Pa·s/mol | Tuned for realistic flow | Plant/FirstStageReg |
| IP volume | V_ip | 1e-4 | m³ | Hose volume (~100 mL) | Plant/GasVolume |
| 2nd stage cracking | P_crack_2nd | 100 | Pa | EN 250 limit (~1 mbar) | Plant/SecondStageReg |
| 2nd stage resistance | R_2nd | 6000 | Pa·s/mol | Tuned for 15 L/min SAC | Plant/SecondStageReg |
| Lung residual moles | n_lungs_0 | 0.0624 | mol | ~1.5L at surface | Plant/Lungs |
| Exhale cracking | P_crack_exh | 50 | Pa | Low resistance exhale | Plant/ExhaleValve |
| Exhale resistance | R_exh | 9000 | Pa·s/mol | Tuned to balance 2nd stage | Plant/ExhaleValve |
| BCD max volume | V_max | 0.015 | m³ | 15L typical recreational | Plant/BCDBladder |
| BCD wall stiffness | K_wall | 1e7 | Pa/m³ | Stiff bladder material | Plant/BCDBladder |
| BCD inflate R | R_inflate | 5e6 | Pa·s/mol | Slow inflation rate | Plant/BCDInflateValve |
| Purge valve R | R_purge | 1e4 | Pa·s/mol | Fast dump rate | Plant/PurgeValve |
| Purge dump bias | P_dump | 5000 | Pa | ~50cm water column | Plant/PurgeValve |
| OPRV cracking | P_crack_oprv | 20684 | Pa | 3.0 psi gauge | Plant/OPRV |
| OPRV resistance | R_oprv | 5000 | Pa·s/mol | Fast relief | Plant/OPRV |
| Diver mass | m_diver | 80 | kg | Average adult male | Plant/DiverBody |
| Diver body volume | V_body | 0.078 | m³ | ~78L displacement | Plant/DiverBody |
| Drag coefficient | Cd | 1.1 | — | Passmore & Rickers 2002 | Plant/DiverBody |
| Frontal area | A_frontal | 0.12 | m² | Horizontal trim | Plant/DiverBody |
| Water density | ρ_water | 1025 | kg/m³ | Seawater standard | Plant/DiverBody |
| Weight belt | m_weights | 4 | kg | Recreational typical | Plant/Weights |
| Gear mass | m_gear | 5 | kg | Fins, mask, reg, BCD | Plant/Weights |
| Gas constant | R_gas | 8.314 | J/(mol·K) | NIST | Domain |
| Temperature | T | 293.15 | K | 20°C isothermal | Domain |
| Gravity | g | 9.81 | m/s² | Standard | MechProps |

### Harness Controller Parameters (new)

| Parameter | Symbol | Value | Unit | Source | Block Path |
|-----------|--------|-------|------|--------|------------|
| Breathing rate | f_breath | 15 | bpm | Buzzacott 2014 (relaxed) | BreathingGen |
| Breath amplitude | A_breath | 200 | Pa | Held & Pendergast 2013 | BreathingGen |
| Depth effort scaling | K_depth | 1/40 | 1/m | Approx. gas density effect | BreathingGen |
| BCD proportional gain | K_p | 2.0 | 1/m | Tuned | BCDController |
| BCD velocity damping | K_d | 5.0 | s/m | Tuned | BCDController |
| BCD deadband | db | 0.3 | m | From scuba_params | BCDController |
| Max descent rate | v_desc_max | 0.5 | m/s | US Navy (30 m/min limit) | BCDController |
| Max ascent rate | v_asc_max | 0.167 | m/s | US Navy (10 m/min modern) | BCDController |
| Safety stop depth | d_safety | 5 | m | PADI/SSI standard | DiveProfile |
| Safety stop duration | t_safety | 180 | s | 3 minutes minimum | DiveProfile |

---

## 7. Sync Points

After each phase:
1. Model compiles without error
2. Visual inspection of block diagram matches architecture
3. Run sanity simulation (even partial)
4. Compare key signals against physical expectations
5. Update Progress Summary in this document

---

## 8. Definition of Done

### Phase 0 Complete
- [ ] Plant interface verified (3 in, 2 out)
- [ ] `dive_profiles.m` returns valid structs for all 4 scenarios
- [ ] `compute_bcd_init_moles.m` works for depths 5–40m
- [ ] Surface-start parameters added to `scuba_params.m`

### Phase 1 Complete
- [ ] Breathing subsystem generates correct frequency and amplitude
- [ ] Depth scaling active and reasonable
- [ ] Plant responds to breathing (gas flows in/out of lungs)

### Phase 2 Complete
- [ ] Dive profile sequences through all phases correctly
- [ ] BCD controller achieves < ±0.5m error during hold
- [ ] Ascent rate limited to 10 m/min
- [ ] No simultaneous inflate + purge commands

### Phase 3 Complete
- [ ] `full_dive_test.slx` runs Scenario 1 end-to-end
- [ ] All signals logged and plottable
- [ ] No solver failures, NaN, or unphysical values
- [ ] Stop conditions work (depth < 0 terminates)

### Phase 4 Complete
- [ ] All 4 scenarios run to completion
- [ ] SAC rate within ±15% of target for each scenario
- [ ] Depth tracking RMS < 0.3m in all hold phases
- [ ] Tank never goes negative
- [ ] `run_scenarios.m` produces comparison report

---

## 9. Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Plant interface mismatch | Phase 0 explicitly verifies ports before any building |
| BCD controller instability | Start with conservative gains; add derivative damping; test hold phase first |
| Solver failure during ascent (Boyle expansion) | Preemptive venting in ascent logic; reduce max step size to 0.05s |
| Gas consumption unrealistic | Validate against SAC formula early (Phase 1 + breathing test) |
| Long sim time (36+ min) | Target ode23t variable-step; accept 2-5 min wall-clock |
| Surface start instability | Begin at 1m (not 0) to avoid hard-stop contact at t=0 |

---

## Appendix A: Solver Configuration

| Setting | Value | Rationale |
|---------|-------|-----------|
| Solver type | Variable-step | Simscape requires; faster for varying dynamics |
| Solver | ode23t | L-stable implicit, handles stiff DAE; required by Simscape custom domain |
| Max step size | 0.1 s | Fast enough for breathing (0.25 Hz) and BCD dynamics |
| Relative tolerance | 1e-4 | Balance accuracy vs speed; tighten to 1e-5 if needed |
| Stop time | Scenario-dependent | 2700s (45min), 2400s (40min), 1200s (20min), 3600s (60min) |
| Simscape logging | All | For truth outputs and debugging |

---

## Appendix B: Dive Profile Specifications

### Scenario 1: Square 18m (45 min)

| Phase | Start Depth | End Depth | Rate | Duration |
|-------|-------------|-----------|------|----------|
| Descent | 1 m | 18 m | 0.5 m/s | 34 s |
| Bottom | 18 m | 18 m | — | 40 min |
| Ascent | 18 m | 5 m | 0.15 m/s | 87 s |
| Safety stop | 5 m | 5 m | — | 3 min |
| Final ascent | 5 m | 1 m | 0.05 m/s | 80 s |

**Expected gas consumption:** SAC=15 L/min × (18/10+1) = 42 L/min actual × 40 min ≈ 1680 L ≈ 74% of AL80

### Scenario 2: Multi-Level (30→20→10)

| Phase | Start Depth | End Depth | Rate | Duration |
|-------|-------------|-----------|------|----------|
| Descent | 1 m | 30 m | 0.5 m/s | 58 s |
| Level 1 | 30 m | 30 m | — | 10 min |
| Transit | 30 m | 20 m | 0.15 m/s | 67 s |
| Level 2 | 20 m | 20 m | — | 15 min |
| Transit | 20 m | 10 m | 0.15 m/s | 67 s |
| Level 3 | 10 m | 10 m | — | 15 min |
| Ascent | 10 m | 5 m | 0.15 m/s | 33 s |
| Safety stop | 5 m | 5 m | — | 3 min |
| Final ascent | 5 m | 1 m | 0.05 m/s | 80 s |

**Expected gas consumption:** Weighted average ~35 L/min × 40 min ≈ 1400 L ≈ 62% of AL80

### Scenario 3: Deep Bounce (40m, 5 min)

| Phase | Start Depth | End Depth | Rate | Duration |
|-------|-------------|-----------|------|----------|
| Descent | 1 m | 40 m | 0.5 m/s | 78 s |
| Bottom | 40 m | 40 m | — | 5 min |
| Deep stop | 40 m → 20 m | 20 m | 0.15 m/s | 133 s |
| Hold | 20 m | 20 m | — | 2 min |
| Ascent | 20 m | 5 m | 0.15 m/s | 100 s |
| Safety stop | 5 m | 5 m | — | 3 min |
| Final ascent | 5 m | 1 m | 0.05 m/s | 80 s |

**Expected gas consumption:** SAC=15 × 5 ATA × 5 min + shallower phases ≈ 600 L ≈ 26% of AL80

### Scenario 4: Shallow 10m (60 min)

| Phase | Start Depth | End Depth | Rate | Duration |
|-------|-------------|-----------|------|----------|
| Descent | 1 m | 10 m | 0.3 m/s | 30 s |
| Bottom | 10 m | 10 m | — | 55 min |
| Ascent | 10 m | 5 m | 0.15 m/s | 33 s |
| Safety stop | 5 m | 5 m | — | 3 min |
| Final ascent | 5 m | 1 m | 0.05 m/s | 80 s |

**Expected gas consumption:** SAC=12 × 2 ATA × 55 min ≈ 1320 L ≈ 58% of AL80 (low SAC for relaxed diver)
