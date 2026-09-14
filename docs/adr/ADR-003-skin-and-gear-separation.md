# ADR-003: Strict Decoupling of Skins from Base Weapons

* **Status:** Accepted
* **Date:** 2026-09-03
* **Context:**
  Players can obtain weapon skins through various channels (gacha unboxing, trading, codes, battle pass) without having unlocked the underlying weapon base in the GearShop. An AI agent or developer might instinctively assume that obtaining a skin should automatically grant the base weapon, or that possessing a skin entitles the player to equip it immediately.
* **Decision:**
  Skins and Base Weapons are strictly decoupled:
  1. **Base Weapons (`Weapons` in DataStore):** Represent tools purchased in the GearShop (or starter items). They define functionality, stats, and gameplay mechanics.
  2. **Skins (`Skins` in DataStore):** Represent cosmetic overlays and stat float multipliers.
  3. **Invariable Rule (`INV-001` & `INV-002`):**
     - Possessing a Skin **NEVER** automatically grants the Base Weapon.
     - Equipping a Skin **REQUIRES** the player to already own the Base Weapon.
     - If a player attempts to equip a skin without the base weapon, the server rejects the request with an error, no data is written to DataStore, and the client displays `GearShop Required`.
* **Rejected Alternatives:**
  - Auto-granting the base weapon upon obtaining a skin (rejected because it breaks progression pacing, rendering the GearShop obsolete for high-tier skins).
  - Allowing skin equip without owning the base weapon (rejected because it breaks character tool loading and game balance).
* **Consequences:**
  - Preserves the player progression loop and in-game economy.
  - Requires clear UI notifications (`GearShop Required`) to guide players to purchase the base tool.
