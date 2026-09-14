# ADR-001: Server Authority for Economy, Inventory, and Combat Validation

* **Status:** Accepted
* **Date:** 2026-09-03
* **Context:**
  In a multiplayer Roblox experience, the client environment is completely untrusted. Exploiters have direct access to local memory, can fire arbitrary RemoteEvents with forged arguments, and can modify local GUI states.
* **Decision:**
  All mutations of player inventory, currencies (`Cash`, `Coins`, `Bricks`, `Gems`), item purchases, gacha unboxings, trade confirmations, and projectile origin validations are strictly authoritative on the Server.
  - The client only requests intent (e.g., `BuyItem`, `EquipSkin`, `TradeReady`).
  - The server verifies requirements, deducts resources, validates ownership, updates the session cache/DataStore, and replicates results back to clients.
* **Rejected Alternatives:**
  - Client-authoritative currency updates (rejected due to trivial exploitation via memory injectors).
  - Optimistic client-side inventory commits without server validation.
* **Consequences:**
  - High security and economy stability; zero trust in client inputs.
  - Requires all game controllers to handle asynchronous server responses and potential transaction rejection gracefully.
