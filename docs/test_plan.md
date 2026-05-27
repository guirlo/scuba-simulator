# Scuba Buoyancy Simulation — Test Plan

## Overview

This test plan validates the physics of the scuba diver buoyancy simulation against analytical solutions, real-world scuba dive behavior, and conservation laws. Tests are organized into four tiers:

1. **Component-level** — Isolated Simscape components
2. **Integration** — Basic maneuvers with full coupling
3. **Dive profiles** — Realistic multi-phase scenarios
4. **Physics validation** — Closed-form analytical comparisons

Tests are implemented as `matlab.unittest.TestCase` classes in `tests/`.

---

## Reference Parameters

All tests use the default parameter set unless noted:
- Water: saltwater ρ=1025 kg/m³, T=293.15 K
- Tank: 12 L, 200 bar, Air
- Diver: 80 kg, 0.078 m³ body volume, Cd=1.1, A=0.12 m²
- Wetsuit: 5 mm, 1.8 m², 70% gas fraction, compression exponent=0.7
- Weights: 4 kg belt + 5 kg gear (0.003 m³)
- BCD: 15 L max
- Breathing: 15 bpm, 0.5 L tidal, 1.5 L residual
- 1st stage: IP = P_amb + 10 bar
- 2nd stage: P_crack = 100 Pa, R_open = 5e4 Pa·s/mol
- Exhale valve: P_crack = 50 Pa

**Derived:**
- V_wetsuit_surface = 1.8 × 0.005 × 0.70 = 0.0063 m³
- n_tank_initial = 200e5 × 0.012 / (8.314 × 293.15) = 984.6 mol
- Total mass (m_total) = 80 + 4 + 5 = 89 kg

---

## 1. Component-Level Unit Tests

### 1.1 Gas Domain Conservation (`tGasDomainBasic`)

**Description:** Verify molar flow is conserved at every junction node.

**Setup:** Tank → fixed orifice → AmbientReference. Log flow at tank outlet and ambient inlet.

**Stimulus:** Run 60 s, tank at 200 bar, ambient at 1 atm.

**Expected:** `n_dot_tank_out == n_dot_ambient_in` at every time step.

**Pass criteria:** `max(|n_dot_out − n_dot_in|) < 1e-10 mol/s`

**Validates:** Conservation of moles in custom gas domain.

---

### 1.2 Tank Pressure Depletion (`tGasDomainBasic`)

**Description:** Tank pressure follows ideal gas law as moles are drawn.

**Setup:** Tank (12 L, 200 bar) connected to fixed-rate sink at 0.01 mol/s.

**Stimulus:** Run 100 s (removes 1 mol).

**Expected:**
- n₀ = 984.6 mol → n_final = 983.6 mol
- P_final = 983.6 × 8.314 × 293.15 / 0.012 = 199.8 bar
- Linear decay: dP/dt = −0.00203 bar/s

**Pass criteria:** `|P_tank(100) − 199.8e5| < 0.01e5 Pa`

**Validates:** Ideal gas law for rigid container with depletion.

---

### 1.3 First Stage Regulator Set Point (`tRegulatorSetPoint`)

**Description:** 1st stage maintains outlet at P_amb + 10 bar.

**Setup:** Tank at 200 bar, test at depths 0, 10, 20, 30, 40 m with small downstream demand.

**Expected:**
| Depth | P_amb (Pa) | P_IP expected (Pa) |
|-------|-----------|-------------------|
| 0 m | 101,325 | 1,101,325 |
| 10 m | 201,880 | 1,201,880 |
| 20 m | 302,435 | 1,302,435 |
| 30 m | 402,990 | 1,402,990 |
| 40 m | 503,545 | 1,503,545 |

Also test depleted tank (12 bar): P_IP should be limited to 12e5 Pa.

**Pass criteria:** `|P_IP_measured − P_IP_expected| < 0.05e5 Pa`

**Validates:** Downstream-referenced regulator; supply exhaustion mode.

---

### 1.4 Second Stage Demand Valve (`tRegulatorSetPoint`)

**Description:** 2nd stage only passes flow when downstream pressure drops below P_amb − P_crack.

**Setup:** IP source at P_amb + 10 bar; downstream node pressure controlled.

**Stimulus:**
- Phase A (0–5 s): downstream = P_amb → no demand
- Phase B (5–15 s): downstream = P_amb − 200 Pa → demand exceeds P_crack
- Phase C (15–20 s): downstream = P_amb → demand ceases

**Expected:**
- A: n_dot = 0
- B: n_dot > 0, steady-state = ΔP / R_open
- C: n_dot returns to 0

**Pass criteria:** Phase A: `max(|n_dot|) < 1e-8`. Phase B: flow within 5% of analytical.

**Validates:** Demand-valve cracking pressure; physically-driven gas delivery.

---

### 1.5 Lung Volume Response (`tBreathingCycle`)

**Description:** Lung volume oscillates correctly at depth.

**Setup:** Full breathing circuit at fixed 20 m. 15 bpm, 0.5 L tidal.

**Stimulus:** Breathing effort for 30 s.

**Expected:**
- P(20) = 302,470 Pa
- Physical lung volume swing = V_tidal = 0.5 L at all depths
- Moles per breath = P(20) × V_tidal / (R×T) = 302470 × 0.5e-3 / 2437.4 = 0.0620 mol

**Pass criteria:** Peak-to-peak V_lungs within 10% of 0.5e-3 m³. Moles per breath within 5% of 0.0620 mol.

**Validates:** Boyle's law lung mechanics; molar consumption per breath.

---

### 1.6 BCD Inflate/Deflate (`tBCDInflateDeflate`)

**Description:** BCD responds correctly to inflate and purge commands.

**Setup:** BCD empty at 20 m, IP source available.

**Stimulus:**
- Phase A (0–5 s): inflate ON
- Phase B (5–15 s): hold
- Phase C (15–20 s): purge ON

**Expected:**
- A: V_bcd monotonically increasing
- B: V_bcd constant (within 1%)
- C: V_bcd monotonically decreasing
- Volume never exceeds 0.015 m³

**Pass criteria:** Monotonicity in A and C; constancy in B; max volume clamped.

**Validates:** Pressure-driven fill/vent; bladder volume limits.

---

### 1.7 Wetsuit Compression Curve (`tWetsuitDrag`)

**Description:** Wetsuit volume follows modified Boyle's law.

**Setup:** Compute V_wetsuit at depths 0, 5, 10, 15, 20, 25, 30, 35, 40 m.

**Expected:**
| Depth | P(d) (Pa) | V_wetsuit (L) |
|-------|----------|--------------|
| 0 m | 101,325 | 6.30 |
| 10 m | 201,880 | 3.75 |
| 20 m | 302,435 | 2.72 |
| 30 m | 402,990 | 2.18 |
| 40 m | 503,545 | 1.88 |

Formula: `V = 0.0063 × (101325 / P(d))^0.7`

**Pass criteria:** Relative error < 1% at each depth.

**Validates:** Neoprene compression model (constrained gas cells).

---

### 1.8 Drag Force Characteristics (`tWetsuitDrag`)

**Description:** Drag follows quadratic law with correct sign.

**Setup:** Measure drag at velocities: −2, −1, −0.5, 0, 0.5, 1, 2 m/s.

**Expected:**
- `F_drag = −0.5 × 1025 × 1.1 × 0.12 × v × |v|`
- At v = 1 m/s: F = −67.65 N (opposes descent)
- At v = −1 m/s: F = +67.65 N (opposes ascent)
- Quadratic: |F(2v)| = 4×|F(v)|

**Pass criteria:** `|F_measured − F_analytical| < 0.5 N`

**Validates:** Quadratic drag; correct sign convention.

---

## 2. Integration Tests — Basic Maneuvers

### 2.1 Neutral Buoyancy Hold (`tBuoyancyManeuvers`)

**Description:** Properly trimmed diver holds depth.

**Setup:** Diver at 20 m, initial velocity = 0. BCD pre-charged for neutral buoyancy:
- Required V_total = m_total / ρ_w = 89 / 1025 = 0.08683 m³
- V_bcd_required ≈ 0.00252 m³ (2.52 L)

**Stimulus:** 60 s, normal breathing, no BCD commands.

**Expected:** Depth oscillates around 20 m due to breathing cycles but mean does not drift.

**Pass criteria:**
- `|mean(depth, last 30s) − 20| < 0.1 m`
- `|max(depth) − min(depth)| < 0.5 m` (breathing oscillation only)

**Validates:** Archimedes equilibrium; breathing perturbation stability.

---

### 2.2 Controlled Descent — Negative Buoyancy (`tBuoyancyManeuvers`)

**Description:** Under-inflated BCD: diver sinks; descent accelerates as wetsuit compresses.

**Setup:** Diver at surface, BCD empty.

**Stimulus:** 60 s, breathing active.

**Expected:**
- At surface: V_total ≈ 0.0891 m³ → F_buoy ≈ 895 N vs W = 873 N → floats initially (wetsuit buoyancy)
- Wetsuit compresses with any small perturbation downward → positive feedback
- After reaching ~5–10 m: net negative → descent accelerates
- Terminal velocity reached where drag balances net weight

**Pass criteria:** Depth increases after initial period. Velocity stabilizes (terminal velocity).

**Validates:** Wetsuit compression positive feedback; buoyancy transition with depth.

---

### 2.3 Controlled Ascent — Positive Buoyancy (`tBuoyancyManeuvers`)

**Description:** Excess BCD gas at depth causes accelerating ascent (runaway expansion).

**Setup:** Diver at 30 m with BCD giving +2 kg net positive buoyancy.

**Stimulus:** 120 s, no BCD adjustments.

**Expected:**
- Ascent accelerates as BCD gas expands
- Ascent rate at 10 m > rate at 25 m
- Diver reaches surface

**Pass criteria:** Velocity magnitude increases during ascent. Diver surfaces within sim time.

**Validates:** Gas expansion positive feedback during ascent.

---

### 2.4 BCD Inflate at Depth → Ascent (`tBuoyancyManeuvers`)

**Description:** Inflating BCD creates positive buoyancy, initiating ascent.

**Setup:** Diver neutral at 25 m.

**Stimulus:** t=10 s: inflate for 3 s.

**Expected:** Net buoyancy goes positive → diver ascends → BCD expands further (feedback).

**Pass criteria:** Depth decreases after inflate. Ascent rate increases with decreasing depth.

**Validates:** BCD as buoyancy control; pressure-driven inflation.

---

### 2.5 BCD Purge → Descent (`tBuoyancyManeuvers`)

**Description:** Venting BCD decreases buoyancy, causing descent.

**Setup:** Diver neutral at 15 m.

**Stimulus:** t=10 s: purge for 2 s.

**Expected:** V_bcd drops → net negative buoyancy → descent. Remaining BCD gas compresses further at depth (feedback).

**Pass criteria:** Depth increases after purge. V_bcd decreases step-wise then further from compression.

**Validates:** BCD dump procedure; compression feedback.

---

### 2.6 Emergency Free Ascent — Runaway (`tBuoyancyManeuvers`)

**Description:** Uncontrolled ascent from 40 m with BCD at 5 L. Dangerous scenario.

**Setup:** Diver at 40 m, V_bcd = 5 L (n_bcd = 1.033 mol), no venting.

**Expected:**
| Depth | V_bcd |
|-------|-------|
| 40 m | 5.0 L |
| 20 m | 8.3 L |
| 10 m | 12.5 L |
| 0 m | 15.0 L (clamped) |

Ascent rate should exceed safe limits (>0.3 m/s) well before surface.

**Pass criteria:**
- V_bcd follows n×R×T/P(d) within 2% (or clamped at 15 L)
- Ascent rate at 10 m > ascent rate at 30 m
- Peak velocity > 3 m/s near surface

**Validates:** Boyle's law runaway; why divers must vent during ascent.

---

### 2.7 Surface Float — Hardstop (`tBuoyancyManeuvers`)

**Description:** Ascending diver stops at surface (depth = 0).

**Setup:** Diver at 5 m with positive buoyancy.

**Stimulus:** Let diver reach surface.

**Expected:** Depth stops at 0. Velocity → 0. Hardstop holds.

**Pass criteria:** `min(depth) ≥ −0.01 m`. Velocity < 0.01 m/s within 5 s of contact.

**Validates:** Mechanical hardstop; surface boundary condition.

---

## 3. Dive Profile Tests

### 3.1 Square Profile — 20 m for 30 min (`tDiveProfiles`)

**Description:** Standard recreational dive.

**Sequence:**
| Phase | Time | Depth | BCD Action |
|-------|------|-------|------------|
| Descent | 0–2 min | 0→20 m | Empty (suit compression assists) |
| Bottom | 2–32 min | 20 m | Trimmed neutral |
| Ascent | 32–34 min | 20→5 m | Vent to control rate ~9 m/min |
| Safety stop | 34–37 min | 5 m | Trimmed neutral |
| Surface | 37–38 min | 5→0 m | — |

**Expected gas consumption:**
- At 20 m (3 atm): SCR × 3 × 30 min = 7.5 × 3 × 30 = 675 L
- Total including transitions: ~750 L
- Tank remaining: 2400 − 750 = 1650 L → ~138 bar

**Pass criteria:**
- Depth within 1 m of target during each hold phase
- Tank pressure at end: 130–145 bar
- Ascent rate never exceeds 18 m/min (0.3 m/s)

**Validates:** Realistic gas budgeting; BCD control authority; profile fidelity.

---

### 3.2 Multi-Level Profile (`tDiveProfiles`)

**Description:** 30 m (10 min) → 15 m (15 min) → 5 m safety stop (3 min).

**Sequence:**
| Phase | Time | Depth |
|-------|------|-------|
| Descent | 0–3 min | 0→30 m |
| Level 1 | 3–13 min | 30 m |
| Transition | 13–14 min | 30→15 m |
| Level 2 | 14–29 min | 15 m |
| Transition | 29–30 min | 15→5 m |
| Safety stop | 30–33 min | 5 m |
| Surface | 33–34 min | 5→0 m |

**Expected gas consumption:**
- 30 m (4 atm, 10 min): 7.5 × 4 × 10 = 300 L
- 15 m (2.5 atm, 15 min): 7.5 × 2.5 × 15 = 281 L
- 5 m (1.5 atm, 3 min): 7.5 × 1.5 × 3 = 34 L
- Transitions: ~50 L
- Total: ~665 L → remaining ~145 bar

**Pass criteria:**
- Each level maintained within 1 m for >80% of hold time
- Tank pressure decreases faster at deeper levels
- Final tank: 140–150 bar
- BCD volume at 30 m < BCD volume at 15 m < BCD volume at 5 m (neutral trim)

**Validates:** Depth-dependent consumption; multi-level gas budgeting; BCD retrimming.

---

### 3.3 Yo-Yo Profile — Stability Test (`tDiveProfiles`)

**Description:** Oscillation between 10 m and 20 m with fixed BCD. Demonstrates instability.

**Setup:** Diver neutral at 15 m. BCD fixed (no commands after initial trim).

**Stimulus:** Push diver to 10 m, release. Observe 5 cycles over 10 min.

**Expected:**
- Without BCD correction, each excursion tends to amplify (positive feedback)
- At 10 m: BCD expands → more positive → wants to keep rising
- At 20 m: BCD compresses → more negative → wants to keep sinking
- Drag is the only passive damping
- V_bcd(10m) / V_bcd(20m) = P(20)/P(10) = 1.498

**Pass criteria:**
- Oscillation amplitude does not damp to zero (feedback sustains it)
- BCD volume ratio between extremes matches P ratio within 5%
- With drag: steady-state amplitude determined by drag equilibrium

**Validates:** Boyle's law instability; importance of active BCD trim; drag as damping.

---

## 4. Physics Validation Tests

### 4.1 Tank Consumption Rate vs Depth (`tPhysicsValidation`)

**Description:** Consumption scales linearly with absolute pressure.

**Setup:** Steady breathing (15 bpm, 0.5 L) at fixed depths 0, 10, 20, 30, 40 m for 2 min each.

**Expected:**
| Depth | P/P_atm | mol/breath | mol/s |
|-------|---------|-----------|-------|
| 0 m | 1.0 | 0.0208 | 0.0052 |
| 10 m | 2.0 | 0.0414 | 0.0104 |
| 20 m | 3.0 | 0.0620 | 0.0155 |
| 30 m | 4.0 | 0.0826 | 0.0207 |
| 40 m | 5.0 | 0.1034 | 0.0259 |

**Pass criteria:** Average consumption rate at each depth within 5% of `(P(d)/P_atm) × 0.0052 mol/s`.

**Validates:** The fundamental diver's rule: gas lasts 1/N times as long at N atmospheres.

---

### 4.2 Breath Volume at Depth (`tPhysicsValidation`)

**Description:** Physical lung volume swing (tidal volume) is constant at all depths.

**Setup:** Measure peak-to-peak V_lungs at 0, 10, 20, 30, 40 m.

**Expected:** V_tidal = 0.5 L physical volume at every depth (same chest expansion). The gas is denser at depth but the volume is the same.

**Pass criteria:** Peak-to-peak V_lungs = 0.5e-3 m³ ± 10% at all depths.

**Validates:** Lung mechanics; regulator delivers gas at ambient pressure so lungs expand normally.

---

### 4.3 BCD Boyle's Law (`tPhysicsValidation`)

**Description:** Fixed BCD moles: volume inversely proportional to pressure.

**Setup:** Inflate to known moles at 10 m (V = 5 L). Quasi-static depth sweep 5–35 m.

**Expected:**
- n_bcd = 0.414 mol
- V(d) = 0.414 × 2437.4 / P(d)
- V(5m) = 6.66 L, V(20m) = 3.34 L, V(35m) = 2.23 L
- Ratio V(5)/V(35) = 2.99

**Pass criteria:** Relative error < 2% at each sampled depth.

**Validates:** Ideal gas law (Boyle's) for BCD bladder.

---

### 4.4 Total Buoyancy Force — Analytical (`tPhysicsValidation`)

**Description:** At a precisely known state, verify Archimedes force exactly.

**Setup:** Depth = 15 m, n_bcd = 0.3 mol, n_lungs = 0.1 mol.

**Expected:**
- P(15) = 252,207 Pa
- V_body = 0.078, V_gear = 0.003
- V_wetsuit = 0.0063 × (101325/252207)^0.7 = 0.003153 m³
- V_bcd = 0.3 × 2437.4 / 252207 = 0.002899 m³
- V_lungs = 0.1 × 2437.4 / 252207 = 0.000966 m³
- V_total = 0.088018 m³
- F_buoyancy = 1025 × 9.81 × 0.088018 = 885.2 N
- F_net = 885.2 − (89 × 9.81) = 885.2 − 873.1 = 12.1 N

**Pass criteria:** `|F_buoy − 885.2| < 1 N`, `|F_net − 12.1| < 1 N`

**Validates:** Archimedes' principle; correct volume summation; domain coupling.

---

### 4.5 Terminal Velocity (`tPhysicsValidation`)

**Description:** Under constant net force, diver reaches drag-limited terminal velocity.

**Setup:** Constant depth, net downward force = 20 N.

**Expected:**
- v_t = √(2 × 20 / (1025 × 1.1 × 0.12)) = √(40 / 135.3) = 0.544 m/s

**Stimulus:** Let diver sink from rest for 60 s.

**Pass criteria:** `|v_final − 0.544| < 0.027 m/s` (5%)

**Validates:** Drag-limited terminal velocity; force balance at steady state.

---

### 4.6 Mass Balance Over Full Dive (`tPhysicsValidation`)

**Description:** Total moles leaving tank equals moles exhaled + moles remaining in BCD/lungs changes.

**Setup:** Run any dive profile (e.g., square profile from test 3.1).

**Expected:**
```
Δn_tank = ∫n_dot_exhale·dt + (n_bcd_final − n_bcd_initial) + (n_lungs_final − n_lungs_initial)
```

**Pass criteria:** `|imbalance| < 1e-6 mol`

**Validates:** Gas domain conservation over extended simulation; no moles created or destroyed.

---

### 4.7 Energy Balance — Descent (`tPhysicsValidation`)

**Description:** For a free descent (no breathing/BCD changes), PE loss = KE gain + drag dissipation.

**Setup:** Diver drops from 0 to 20 m without breathing or BCD.

**Expected:**
```
m·g·Δh = ½·m·v²_final + ∫(F_drag · v)·dt
```

**Pass criteria:** Energy balance within 5%.

**Validates:** Mechanical energy conservation in translational domain.

---

## Test Infrastructure

### File Organization

| File | Tests Covered |
|------|--------------|
| `tests/tGasDomainBasic.m` | 1.1, 1.2 |
| `tests/tRegulatorSetPoint.m` | 1.3, 1.4 |
| `tests/tBreathingCycle.m` | 1.5 |
| `tests/tBCDInflateDeflate.m` | 1.6 |
| `tests/tWetsuitDrag.m` | 1.7, 1.8 |
| `tests/tBuoyancyManeuvers.m` | 2.1–2.7 |
| `tests/tDiveProfiles.m` | 3.1–3.3 |
| `tests/tPhysicsValidation.m` | 4.1–4.7 |

### Running Tests

```matlab
% Run all tests
results = runtests('tests');
disp(results);

% Run specific suite
results = runtests('tests/tPhysicsValidation.m');
```

### Signal Logging

All tests extract signals via:
```matlab
simOut = sim(simIn);
depth = simOut.logsout.get('depth').Values;
P_tank = simOut.logsout.get('P_tank').Values;
```

### Tolerance Convention

| Tier | Typical Tolerance |
|------|------------------|
| Component (tier 1) | 1–2% relative |
| Integration (tier 2) | 5–10% |
| Profiles (tier 3) | 10–15% on aggregates |
| Physics validation (tier 4) | 1–5% |
