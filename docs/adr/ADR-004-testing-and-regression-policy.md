# ADR-004: Automated Testing, Regression Strategy, and TestService Policy

* **Status:** Accepted
* **Date:** 2026-09-03
* **Context:**
  When using AI agents (LLMs) for high-velocity software engineering, the primary risk is not syntax errors, but subtle behavioral regressions. An AI can produce technically plausible code that silently breaks existing business rules. Without structured tests and clear acceptance criteria, regressions go unnoticed until production.
* **Decision:**
  1. **Pure Modules & Testable Units:** All stateless or algorithmic modules (`InventoryUtil`, `SkinMath`, `LevelModule`, `SanitizeInput`, `RAP_Validator`) must be designed for testability and evaluated via `TestService` or standalone test scripts in Roblox Studio.
  2. **Regression Rule for Bug Fixes:** Every bug fixed by an AI agent or human must define a concrete regression check: a test or verification step that would fail before the fix and pass after it.
  3. **Invariable Verification:** Test scenarios must explicitly assert that system invariants (`INV-001` through `INV-008`) remain intact during mutations.
  4. **Manual Studio Playtest:** Any change impacting gameplay mechanics, character physics, or UI state must be executed in Roblox Studio at least once prior to declaring completion.
* **Rejected Alternatives:**
  - Blind merging based solely on AI code output without test execution (rejected as fundamentally unsafe).
* **Consequences:**
  - Dramatically reduces regression bugs and unintended side-effects.
  - Ensures changes are verifiable, repeatable, and robust against future refactoring.
