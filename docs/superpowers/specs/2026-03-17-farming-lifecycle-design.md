# Design Spec: Farming Lifecycle

## 1. Objective
Complete the farming lifecycle by implementing tilling, planting, watering, growth stages, and harvesting. This will move the project from basic object interaction to a functional farming prototype for mobile.

## 2. Architecture & Components

### 2.1 Inventory Management (`InventoryManager.lua`)
A new singleton to track player resources.
*   **State:**
    *   `seeds = { beetroot = 5, cabbage = 5, carrot = 5, cauliflower = 5, kale = 5 }`
    *   `harvested = { beetroot = 0, cabbage = 0, carrot = 0, cauliflower = 0, kale = 0 }`
*   **Methods:**
    *   `addSeed(type, count)` / `removeSeed(type, count)`
    *   `addItem(type, count)` / `getItemCount(type)`
    *   `hasSeed(type)` -> boolean

### 2.2 Crop Logic (`CropObject.lua`)
A specialized class for individual plants.
*   **Properties:**
    *   `cropType` (string): e.g., "beetroot"
    *   `growthStage` (int): 0-5
    *   `isWatered` (boolean): Reset daily or after growth.
    *   `growthTimer` (float): Seconds until next stage.
    *   `decayTimer` (float): For empty tilled soil.
*   **Methods:**
    *   `update(dt)`: Advance timers and growth stages.
    *   `water()`: Set `isWatered = true`.
    *   `harvest()`: Returns crop item and reverts tile to tilled soil.

### 2.3 Growth Manager (`CropManager.lua` or Integrated into `GameStateManager`)
Manages the collection of all `CropObject`s.
*   **Responsibility:**
    *   Tick all crops in `love.update`.
    *   Handle "Soil Decay": Remove empty tilled tiles (`dugTiles`) after 120 seconds of inactivity.

## 3. Interaction & UI

### 3.1 Seed Picker Tray
A new UI element that appears when a tilled tile is selected and the **"Plant"** button is tapped.
*   **Layout:** A horizontal scrolling tray above the main action buttons.
*   **Content:** Dynamic list of seeds with counts from `InventoryManager`.
*   **Action:** Tapping a seed button selects it for planting.

### 3.2 Main Action Updates (`ButtonManager.lua` & `GameStateManager.lua`)
*   **Tilled Tile Selected:** Show **"Plant"**, **"Move To"**, and **"Cancel"**.
*   **Planted Crop Selected:**
    *   Stage 0-4: Show **"Water"** and **"Cancel"**.
    *   Stage 5 (Grown): Show **"Harvest"** and **"Cancel"**.
*   **Player Animations:**
    *   **Planting:** Use `DIG` animation as a placeholder or a new frame if found.
    *   **Watering:** Use `WATERING` sprites (`base_watering_strip5.png`, etc.).

## 4. Visual Assets
*   **Crops:** `Sunnyside_World_Assets/Elements/Crops/[type]_[00-05].png`.
*   **Wet Soil:** Apply a dark tint `(0.7, 0.7, 1.0)` to the tilled tile sprite when `isWatered == true`.
*   **UI Icons:** Use crop stage 5 icons or dedicated item sprites if available.

## 5. Success Criteria
1.  Player can till soil using the shovel (existing).
2.  Tapping tilled soil allows selecting a seed from a "Seed Picker".
3.  Player moves to tile and plants the seed (Inventory count decreases).
4.  Crops only grow if watered.
5.  Watering soil changes its visual state (darker).
6.  Fully grown crops can be harvested (Inventory count increases).
7.  Empty tilled soil reverts to grass after 2 minutes.

## 6. Testing Strategy
*   **Unit Tests:** Mock timers to verify growth stage transitions.
*   **Manual Verification:**
    1.  Till 3 tiles.
    2.  Plant 3 different crops.
    3.  Water only 1 crop; verify only that one grows.
    4.  Harvest grown crop and check inventory.
    5.  Leave 1 tile empty and verify it reverts to grass.
