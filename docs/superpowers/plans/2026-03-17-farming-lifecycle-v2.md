# Farming Lifecycle Implementation Plan (V2 - Animation Safe)

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the farming cycle while preserving the integrity of character animations.

**Architecture:** 
- Centralize `dugTiles` and `crops` in `GameStateManager.lua`.
- Use `CropObject.lua` for individual plant state.
- Surgical updates to `main.lua` rendering to match the established animation pattern.

**Tech Stack:** Love2D (Lua).

---

### Task 1: Data Models & Managers

**Files:**
- Create: `Sunville/InventoryManager.lua`
- Create: `Sunville/CropObject.lua`
- Modify: `Sunville/main.lua`

- [ ] **Step 1: Create `InventoryManager.lua`**
  Implement seed/item tracking with methods: `hasSeed`, `removeSeed`, `addItem`.

- [ ] **Step 2: Create `CropObject.lua`**
  Implement growth logic (stages 0-5), watering state, and `harvest()` method.

- [ ] **Step 3: Surgical Init in `main.lua`**
  Require `InventoryManager` and init `_G.inventory` in `love.load()`.

- [ ] **Step 4: Commit**
```bash
# Manual check: Verify InventoryManager loads in game
```

---

### Task 2: Centralized Game State

**Files:**
- Modify: `Sunville/GameStateManager.lua`
- Modify: `Sunville/main.lua`

- [ ] **Step 1: Expand `GameStateManager:new()`**
  Add `dugTiles`, `crops`, `soilDecayTimers`, `selectedGridX/Y`, and `cropIcons`.

- [ ] **Step 2: Implement Soil/Crop methods in `GameStateManager.lua`**
  `addDugTile`, `removeDugTile`, `plant`, `update(dt)`, `setSelectedGrid`.

- [ ] **Step 3: Move Grid Selection logic from `main.lua` to `GameStateManager.lua`**
  Refactor `updateButtonStates` to handle "Plant", "Water", "Harvest" based on grid state.

- [ ] **Step 4: Update `main.lua` hooks**
  Call `gameStateManager:update(dt)` in `love.update`. Use `gameStateManager` for grid selection rendering.

---

### Task 3: Animation & Asset Integration (Surgical)

**Files:**
- Modify: `Sunville/main.lua`

- [ ] **Step 1: Load Assets in `love.load`**
  Load Watering animations and Crop stage images (00-05 for all 5 types).

- [ ] **Step 2: Initialize Animation Quads**
  Carefully add `wateringQuads` and `digQuads` to the `player` table. **Do not modify existing walking/idle quads.**

- [ ] **Step 3: Update `love.draw` Player Section**
  Add `elseif` blocks for `dig`, `water`, and `plant` action types.
  **MUST use the exact existing draw pattern:**
  ```lua
  local anchorX = 48
  local anchorY = 32
  local drawX = mapDrawOffsetX + player.x - anchorX
  local drawY = mapDrawOffsetY + player.y - anchorY
  if sx == -1 then drawX = drawX + player.width end
  -- ... draw calls ...
  ```

---

### Task 4: UI & Action Logic

**Files:**
- Modify: `Sunville/ButtonManager.lua`
- Modify: `Sunville/main.lua`

- [ ] **Step 1: Implement Seed Picker in `ButtonManager.lua`**
  Add `TYPE_SEED_PICKER` and `createSeedPickerButtons`.

- [ ] **Step 2: Link UI to Actions in `main.lua`**
  Update `mousepressed` to handle "Dig", "Plant", "Water", and "Harvest" button clicks.

- [ ] **Step 3: Implement Action Handlers**
  Start player movement and trigger action completion logic in `updatePlayerAction`.

- [ ] **Step 4: Render Crops & Wet Soil**
  Add crop rendering and soil tinting to `main.lua`'s `love.draw`.

---

### Task 5: Verification & Polish

- [ ] **Step 1: Manual Test Loop**
  Till -> Plant -> Water -> Grow -> Harvest.
- [ ] **Step 2: Verify Animations**
  Check walking, turning, and digging for any jumps/stretches.
- [ ] **Step 3: Verify Soil Decay**
  Wait 120s and ensure empty tiles revert.
