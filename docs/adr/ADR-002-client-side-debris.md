# ADR-002: Client-Sided Debris and Visual Destruction Physics

* **Status:** Accepted
* **Date:** 2026-09-03
* **Context:**
  In a high-intensity destruction game, hundreds of blocks can be destroyed simultaneously by rocket explosions or bomb blasts. Simulating physics for dozens of fragmented unanchored parts on the server causes immense physics lag, server heartbeat drops below 30 FPS, and network replication saturation.
* **Decision:**
  Block destruction logic is cleanly split into two distinct tiers:
  1. **Server Tier (Logical State):** The server validates blast radius, calculates damage, updates the block health grid, and replicates only the destroyed block IDs/positions to clients.
  2. **Client Tier (Physical & Visual Presentation):** Each local client receives the destruction signal and generates cosmetic debris parts, unanchored fragments, particle emitters, and sound effects locally. Debris parts are cleared locally using TweenService or DebrisService.
* **Rejected Alternatives:**
  - Replicating physical debris parts from the server (rejected due to severe server tick performance degradation and high network bandwidth consumption).
* **Consequences:**
  - Game runs smoothly at 60 FPS even during massive block collapses.
  - Minimal network bandwidth consumption.
  - Tradeoff: Different clients may see cosmetic debris bounce or settle in slightly different positions, which has zero impact on core gameplay.
