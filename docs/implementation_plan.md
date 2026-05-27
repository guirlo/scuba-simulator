# Scuba Diver Buoyancy Simulation — Implementation Plan

## Context

Build a 1D vertical buoyancy simulation of a scuba diver in Simulink/Simscape (R2026a). The simulation models breath-by-breath gas consumption, BCD control, wetsuit compression with depth, and multiple gas mixes (Air, Nitrox 32%). The goal is to explore and understand scuba buoyancy dynamics interactively.

---

## Architecture: Simscape Plant (Custom Gas Domain) + Simulink Control

- **Plant (100% Simscape)**: Custom `scuba.gas` domain with conserving connections models the gas flow path (tank → regulators → lungs/BCD → water). Position-Based Translational domain for 1-DOF vertical mechanics. Coupling between domains via Physical Signal (PS) ports.
- **Control (Simulink/Stateflow)**: Breathing state machine (outputs muscular effort pressure), BCD command logic, dashboard, mode switching.
- **Key principle**: Gas flow is driven by pressure differentials through the physical network — not by command signals. The breathing effort creates pressure drops that physically open the demand valve. The BCD inflate command opens a valve exposing the bladder to IP pressure.

---

## Custom Gas Domain

### Domain Definition: `+scuba/+gas/gas.ssc`

| Variable | Type | Unit | Role | Analogy |
|----------|------|------|------|---------|
| `p` | Across | Pa | Pressure at node | Voltage |
| `n_dot` | Through (Balancing) | mol/s | Molar flow into node | Current |

**Conservation law**: Sum of molar flows into each node = 0 (automatic via Simscape engine).

**Domain parameters**: `R_gas` (8.314 J/mol·K), `T` (gas temperature, K) — shared across all components on the network.

---

## Gas Flow Topology

```
[GasTank] ══A══ [1st Stage Reg] ══B══╤══ [2nd Stage Reg] ══B══ [Lungs] ══B══ [ExhaleValve] ══B══╗
            HP                    IP  │     (demand valve)        (breath_effort)                  ║
                                      │                                                           ║
                                      ╰══ [BCD Inflate Valve] ══B══ [BCD Bladder] ══B══ [Purge] ══╣
                                           (cmd: inflate_btn)                     (cmd: purge_btn) ║
                                                                                                  ║
                                                                                    [AmbientReference]
                                                                                    (P_amb from depth)

    ════  Gas domain conserving connections (pressure across, mol/s through)
```

### Node Summary

| Node | Connects | Typical Pressure |
|------|----------|-----------------|
| HP | Tank outlet, 1st stage inlet | 50–200 bar |
| IP | 1st stage outlet, 2nd stage inlet, BCD inflate inlet | P_amb + 10 bar |
| Breathing | 2nd stage outlet, Lung inlet | ~P_amb (±breath effort) |
| Lung Exhaust | Lung outlet, Exhale valve inlet | P_amb + exhale effort |
| BCD Internal | BCD inflate outlet, Bladder inlet, Bladder outlet, Purge inlet | ~P_amb |
| Ambient | Exhale valve outlet, Purge valve outlet, AmbientReference | P(depth) |

---

## Custom Simscape Components

### Gas Domain Infrastructure

| File | Purpose |
|------|---------|
| `+scuba/+gas/gas.ssc` | Domain definition (p across, n_dot through, R_gas, T params) |
| `+scuba/+gas/branch.ssc` | Two-port base class (A→B, p_diff, n_dot) |
| `+scuba/+gas/+elements/GasDomainProperties.ssc` | Sets R_gas, T for connected network |

### Gas Components

| Component | Type | Ports | State | Key Behavior |
|-----------|------|-------|-------|--------------|
| **GasTank** | Capacitive | 1 gas (outlet) | `n_tank` [mol] (init: 98.47) | `P = n·R·T/V_tank`; `der(n) = -n_dot_out` |
| **FirstStageRegulator** | Regulated restrictor | 2 gas + PS(P_amb) | — | Maintains B.p = P_amb + IP_offset (or A.p if tank low) |
| **SecondStageRegulator** | Demand valve | 2 gas + PS(P_amb) | — | Opens when B.p < P_amb - P_crack; flow ∝ ΔP/R_open |
| **Lungs** | Variable chamber | 2 gas + PS(P_amb, breath_effort) | `n_lungs` [mol] | Sets node pressure = P_amb + breath_effort; `V = n·R·T/P_amb` |
| **ExhaleValve** | Check valve | 2 gas | — | Opens when A.p > B.p + P_crack; one-way flow |
| **BCDInflateValve** | Commanded valve | 2 gas + PS(cmd) | — | `cmd>0.5`: R_open; else: R_leak (∞) |
| **BCDBladder** | Variable accumulator | 2 gas + PS(P_amb) | `n_bcd` [mol] | Flexible: internal P = P_amb; `V = n·R·T/P_amb` clamped to V_max |
| **PurgeValve** | Commanded valve | 2 gas + PS(cmd) | — | Same as BCDInflateValve |
| **AmbientReference** | Pressure source/sink | 1 gas + PS(P_amb) | — | Sets port pressure = P_amb; absorbs all flow (infinite sink) |

### Mechanical & Coupling Components

| Component | Domain | Purpose |
|-----------|--------|---------|
| **AmbientPressure** | Translational | Reads depth (R.x), outputs P_amb as PS. Zero force (sensor). |
| **BuoyancyForceSource** | Translational | Inputs: V_bcd, V_lungs, P_amb (PS). Computes V_wetsuit internally. Applies Archimedes force. |
| **HydrodynamicDrag** | Translational | Quadratic drag: `f = -0.5·ρ·Cd·A·v·|v|` |

---

## How Demand Breathing Works (Physical)

1. Stateflow outputs `breath_effort` (PS signal):
   - Inhale: `breath_effort ≈ -200 Pa` (muscular suction)
   - Exhale: `breath_effort ≈ +200 Pa` (muscular compression)
   - Pause: `breath_effort = 0`
2. **Lungs** component sets its gas port pressure to `P_amb + breath_effort`
3. During inhale: lung node drops to `P_amb - 200`. The 2nd stage sees `demand = P_amb - (P_amb-200) = 200 > P_crack (100)` → valve opens → gas flows from IP to lungs.
4. During exhale: lung node rises to `P_amb + 200`. ExhaleValve sees `p_diff = 200 > P_crack (50)` → valve opens → gas vents to AmbientReference (lost to water).
5. Conservation: moles enter lungs from tank path, moles leave lungs to water. Net consumption = inhaled moles (tank depletes).

---

## Domain Coupling (Gas ↔ Mechanical)

```
MECHANICAL DOMAIN                              GAS DOMAIN
────────────────                               ──────────

[World]─[Mass(β=90°)]─[Hardstop]─[World]      [GasTank]═[1stStg]═╤═[2ndStg]═[Lungs]═[ExhValve]═╗
            │                                                      │                              ║
   ┌────────┼───────┐                                    [BCDInfl]═[Bladder]═[Purge]══════════════╣
   │        │       │                                                                             ║
[Buoy]  [Drag] [AmbPress]─── P_amb (PS) ───────────────────────────────────────► [AmbientRef]   ║
  ↑PS              │                                                                              ║
  │                ├──► 1stStageReg.P_amb                                                        ║
  │                ├──► 2ndStageReg.P_amb                                                        ║
  │                ├──► Lungs.P_amb                                                              ║
  │                └──► BCDBladder.P_amb                                                         ║
  │                                                                                              ║
  ├─── V_bcd (PS) ◄──── BCDBladder.V_bcd                                                        
  ├─── V_lungs (PS) ◄── Lungs.V_lungs                                                           
  └─── P_amb (PS) ◄──── (same signal)                                                           
```

**PS bridges between domains:**
- `P_amb` (mechanical → gas): AmbientPressure reads depth, computes P(d), feeds all gas components
- `V_bcd`, `V_lungs` (gas → mechanical): Volume outputs from gas accumulator components feed BuoyancyForceSource
- `breath_effort`, `inflate_cmd`, `purge_cmd` (Simulink → gas): Control signals to Lungs and valves

---

## Key Physics & Equations

### Hydrostatic Pressure
```
P(d) = P_atm + ρ_water · g · d
```

### Buoyancy Force (Archimedes)
```
F_buoyancy = ρ_water · g · V_total
V_total = V_body + V_gear + V_wetsuit(d) + V_bcd(d,t) + V_lungs(d,t)
```

### Wetsuit Compression (computed inside BuoyancyForceSource)
```
V_wetsuit(d) = V_ws_surface · (P_atm / P(d))^0.7
```

### Gas Volumes (ideal gas at ambient pressure)
```
V_bcd = n_bcd · R · T / P(d)        (clamped to V_max)
V_lungs = n_lungs · R · T_body / P(d)
```

### Tank Pressure
```
P_tank = n_tank · R · T / V_tank
```

### Regulator Behavior
- 1st stage: maintains outlet at P_amb + 10 bar (or tank pressure if depleted)
- 2nd stage: opens when downstream demand > P_crack; flow = ΔP / R_open

### 1-DOF Vertical Dynamics
```
m · a = F_buoyancy - m·g - F_drag
F_drag = 0.5 · ρ_water · Cd · A · v · |v|
```
Hard-stop at surface (z ≥ 0), depth positive downward (β = 90°).

---

## Project Structure

```
L:\Projects\scuba\
├── scuba-buoyancy.prj
├── startup.m
├── shutdown.m
├── .gitignore
├── +scuba/
│   ├── +gas/
│   │   ├── gas.ssc                         % Domain definition
│   │   ├── branch.ssc                      % Two-port base class
│   │   └── +elements/
│   │       ├── GasDomainProperties.ssc     % Domain parameter block
│   │       ├── GasTank.ssc                 % HP reservoir
│   │       ├── FirstStageRegulator.ssc     % HP → IP
│   │       ├── SecondStageRegulator.ssc    % IP → ambient (demand valve)
│   │       ├── Lungs.ssc                   % Variable volume chamber
│   │       ├── ExhaleValve.ssc             % Check valve to water
│   │       ├── BCDInflateValve.ssc         % Commanded valve
│   │       ├── BCDBladder.ssc              % Variable volume accumulator
│   │       ├── PurgeValve.ssc              % Commanded dump valve
│   │       └── AmbientReference.ssc        % Depth-dependent pressure sink
│   ├── AmbientPressure.ssc                 % Translational sensor → P_amb
│   ├── BuoyancyForceSource.ssc             % Volumes → Archimedes force
│   └── HydrodynamicDrag.ssc                % Quadratic drag
├── models/
│   ├── scuba_buoyancy_sim.slx              % Top-level model
│   └── subsystems/
│       ├── breathing_controller.slx        % Stateflow (outputs breath_effort)
│       └── bcd_controller.slx              % BCD command logic
├── parameters/
│   ├── scuba_params.m                      % Master configuration
│   ├── gas_properties.m                    % Gas mix data
│   └── diver_configs.m                     % Preset configurations
├── scripts/
│   ├── run_simulation.m
│   ├── build_library.m                     % sscbuild('scuba')
│   ├── plot_results.m
│   └── create_input_profiles.m
├── tests/
│   ├── tGasDomainBasic.m                   % Tank depletion, flow conservation
│   ├── tRegulatorSetPoint.m                % Pressure regulation
│   ├── tBreathingCycle.m                   % Demand valve + lung oscillation
│   ├── tBCDInflateDeflate.m                % BCD volume changes
│   └── tFullIntegration.m                  % End-to-end buoyancy dynamics
└── docs/
    └── implementation_plan.md
```

---

## User Controls (Simulink Dashboard)

| Control | Type | Function |
|---------|------|----------|
| Breathing Rate | Knob | 6–30 breaths/min |
| Breath Depth | Slider | Controls tidal volume (shallow ↔ deep breath) |
| BCD Inflate | Push Button | Opens BCDInflateValve while pressed |
| BCD Purge | Push Button | Opens PurgeValve while pressed |
| Mode Switch | Toggle | Manual vs. pre-programmed profile |
| Gas Mix | Switch | Air / Nitrox 32% (changes T domain param) |

**Indicators**: Depth gauge, tank pressure (bar), BCD fill %, net buoyancy (N), vertical speed (m/s), lung volume (L), breathing phase lamp, real-time scopes.

---

## Implementation Phases

### Phase 1: Domain Foundation
1. Create `+scuba/+gas/gas.ssc` (domain definition)
2. Create `+scuba/+gas/branch.ssc` (two-port base class)
3. Create `GasDomainProperties.ssc`
4. Create `GasTank.ssc` and `AmbientReference.ssc`
5. Build with `sscbuild('scuba')` — verify domain compiles
6. Minimal test model: Tank → fixed resistor → AmbientRef — verify pressure decay and flow conservation

### Phase 2: Regulators
1. Implement `FirstStageRegulator.ssc`
2. Implement `SecondStageRegulator.ssc`
3. Wire: Tank → 1st Stage → 2nd Stage → AmbientRef (with constant P_amb)
4. Verify: IP holds at set point; 2nd stage only passes flow when downstream demand exists

### Phase 3: Breathing Circuit
1. Implement `Lungs.ssc` and `ExhaleValve.ssc`
2. Wire: 2nd Stage → Lungs → ExhaleValve → AmbientRef
3. Drive `breath_effort` with sinusoidal test signal
4. Verify: Gas flows during inhale (tank depletes), exhaled gas exits to ambient, lung volume oscillates

### Phase 4: BCD Circuit
1. Implement `BCDInflateValve.ssc`, `BCDBladder.ssc`, `PurgeValve.ssc`
2. Wire: IP node → BCDInflateValve → BCDBladder → PurgeValve → AmbientRef
3. Test inflate/deflate independently with command signals
4. Verify: Bladder fills, volume correct at given P_amb, purge empties it

### Phase 5: Mechanical Domain & Coupling
1. Implement `AmbientPressure.ssc`, `BuoyancyForceSource.ssc`, `HydrodynamicDrag.ssc`
2. Build translational network: World — Mass — Hardstop — World
3. Connect P_amb from AmbientPressure to all gas components
4. Connect V_bcd, V_lungs from gas components to BuoyancyForceSource
5. Verify: Full depth-pressure-volume-buoyancy coupling; diver ascends/descends correctly

### Phase 6: Controllers (Stateflow + Simulink)
1. Breathing controller: Stateflow cycling INHALE/PAUSE/EXHALE/PAUSE, outputs `breath_effort` waveform
2. BCD controller: button inputs → valve command outputs
3. Wire controllers to plant via Simulink-PS converters
4. Full integration verification

### Phase 7: Dashboard, Visualization & Profiles
1. Full Simulink Dashboard (controls + indicators + scopes)
2. Post-simulation plots (`plot_results.m`)
3. Pre-programmed dive profiles with mode switch
4. Real-time pacing for interactive mode

### Phase 8: Testing & Polish
1. Formal test suite (analytical verification)
2. Parameter tuning for realistic behavior
3. Gas mix switching support
4. Documentation

---

## Solver Settings
- Solver: `ode23t` (trapezoidal, good for Simscape DAE systems)
- Max step size: 0.01 s (resolve breath transitions and valve dynamics)
- Simulation time: configurable (60–3600 s)
- Real-time pacing: ON for interactive, OFF for batch

---

## Algebraic Loop Resolution

The coupling loop (depth → P_amb → volumes → buoyancy → acceleration → depth) resolves naturally in the Simscape DAE solver. Differential states are:
- Mechanical: `x` (depth), `v` (velocity)
- Gas: `n_tank`, `n_bcd`, `n_lungs`

Volume computations are algebraic constraints solved simultaneously with the differential states.

---

## Verification Approach
1. **Flow conservation** — at every node, sum of n_dot = 0
2. **Regulator set points** — 1st stage holds IP; 2nd stage delivers at ambient
3. **Tank depletion rate** — proportional to depth (more moles per breath at depth)
4. **Breathing demand** — only flows during inhale; correct volume per breath
5. **BCD buoyancy** — inflate causes ascent, deflate causes descent
6. **Wetsuit compression** — buoyancy decreases with depth
7. **Free ascent** — expanding gas creates accelerating ascent (runaway effect)
8. **Neutral buoyancy** — properly weighted diver holds depth

---

## .gitignore
```
slprj/
*.slxc
*.mex*
codegen/
*.autosave
```
