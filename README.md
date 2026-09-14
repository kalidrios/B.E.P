# B.E.P — Destruction Simulator Engine (Roblox / Luau)

[![Luau](https://img.shields.io/badge/Language-Luau-00A2FF?style=flat-square&logo=lua)](https://luau-lang.org/)
[![Roblox](https://img.shields.io/badge/Platform-Roblox%20Studio-EE3124?style=flat-square&logo=roblox)](https://www.roblox.com/)
[![Genre](https://img.shields.io/badge/Genre-Destruction%20Simulator-orange?style=flat-square)](#core-loop--game-design)
[![Architecture](https://img.shields.io/badge/Architecture-Server%20Authoritative%20%7C%20Zero--Physics%20Server-success?style=flat-square)](#zero-server-lag-physics-pipeline)
[![License](https://img.shields.io/badge/License-Proprietary-red?style=flat-square)](#)

A high-throughput **Destruction Simulator** engine built with Luau for Roblox. Engineered for scalability, rock-solid server tick rates, and smooth performance on low-end hardware (mobile and budget PCs). It pairs client-side staggered physics debris and purely numerical block accounting with a perpetual, float-driven skin market economy.

---

## Core Loop & Game Design

```
[ Block Farming ] ────> [ Backpack Limit ] ────> [ Sell Zone ] ────────> [ Upgrades & Rebirth ]
 (Weapon + Mine +        (Sets session pacing     (Converts to Cash +     (Resets weapons/areas,
  Skin Float Mult)        by returning to base)    XP w/ Backpack Mult)    preserves Skins and RAP)
```

### 1. Setup & Farm (Action & Retention Phase)
- **Immediate Retention:** A lightweight introductory modal grants a free *StarterBooster*, maximizing retention during critical early minutes without predatory gamepass prompts.
- **Weapons and Mines:** Players destroy destructible geometry across zones using primary weapons and deployable mines.
- **Zero-Lag Server Accounting:** Collected blocks are **never physical server parts**. They are processed purely as atomic numeric values in player data profiles, keeping server memory footprint minimal.
- **Weapon Skin Multipliers:** The **Float** value of equipped weapon skins dynamically multiplies the block yield generated per detonation.

### 2. Storage (Pacing & Flow Control)
- The player's **Backpack** capacity defines the maximum block payload, dictating gameplay cadence and requiring strategic returns to the base.

### 3. Sell & Reward (Economic Conversion)
- **Sell Zone:** Instantly liquidates stored blocks into **Cash** and **XP**.
- **Backpack Skin Multipliers:** The **Float** value of equipped backpack skins acts as a dedicated financial multiplier applied directly to final Cash payouts.

### 4. Reinvestment & Rebirth (Perpetual Economy & Anti-Inflation)
- **Progression Upgrades:** Players reinvest Cash into higher tiers of Weapons, Mines, and Backpacks.
- **Asset-Preserving Rebirths:** Rebirthing resets tool unlocks and area progression but **permanently preserves 100% of acquired Skins**, safeguarding player time investment and market RAP (Recent Average Price).
- **Perpetual Demand for Starter Skins:** Equipping a skin post-rebirth requires repurchasing the corresponding base weapon. This creates sustained end-game demand for starter-tier skins, allowing veterans to rapidly accelerate subsequent rebirth cycles.
- **Deflationary Item Sink:** Excess skins are burned in the **Fusion** system based on statistical weight, mitigating asset inflation while sustaining market scarcity and liquidity.

---

## Zero-Server-Lag Physics Pipeline

Simulating destruction across dense environments (10,000 to 50,000+ parts) creates catastrophic physics bottlenecks when processed server-side. The pipeline completely decouples simulation from the server:

```
[Blast / Detonation Trigger]
             │
             ▼
[Server Spatial Query] ──────── (GetPartBoundsInRadius / Tag Filter)
             │
             ├──> [Server State] ──> Numeric Block Increment (No physics, 0 Server Lag)
             │
             └──> [RemoteEvent]  ──> Broadcasts CFrame / Color to Nearby Streamed Clients
                                            │
                                            ▼
                                  [Client Micro-Batch Pipeline]
                                  (Staggered unanchoring: 30 parts / 0.03s)
                                            │
                                            ▼
                                  [Visual Debris / Particles / SFX]
```

- **Server Efficiency:** The server restricts overlap queries strictly to instances tagged via `CollectionService`, converts damage into numeric credits, and removes parts without waking physical collision listeners.
- **Client Micro-Batching:** To eliminate framerate stutter on mobile and entry-level PCs, visual debris is unanchored in micro-batches (**30 parts every 0.03 seconds**), ensuring smooth framerates under sustained detonation.

---

## Repository Structure

```
├── docs/                       # Architectural specifications and system documentation
│   ├── ARCHITECTURE.md         # In-depth physics pipeline, progression curves, and persistence
│   ├── adr/                    # Architecture Decision Records
│   └── systems/                # Subsystem specifications (Trading Protocol, Inventory, etc.)
├── ReplicatedStorage/          # Shared data modules, asset configs, and network definitions
├── ServerScriptService/        # Authoritative game services (Combat, Economy, Persistence)
├── StarterGui/                 # Interface components and ViewportFrame 3D rendering
├── StarterPlayer/              # Client controllers, camera logic, and micro-batch debris
└── README.md                   # Repository overview and technical summary
```
