# Player System - Sunville Game

## Overview
The player system has been implemented to make the human character the main protagonist of the game. The player can now move to selected trees and perform axe actions with proper animations.

## Features

### 1. Player Movement
- **Automatic Pathfinding**: When a tree is selected and the axe action is chosen, the player automatically moves to the tree
- **Collision Detection**: Player avoids obstacles and other objects while moving
- **Visual Feedback**: Green target indicator shows where the player is moving
- **Smooth Movement**: Player moves at a consistent speed towards the target

### 2. Axe Action System
- **Tree Selection**: Click on a tree to select it
- **Action Button**: Click the axe button to start the action
- **Player Movement**: Player automatically moves to the tree
- **Axe Animation**: 10-frame axe chopping animation plays when reaching the tree
- **Action Completion**: Tree is removed after the animation completes

### 3. Visual Elements
- **Movement Indicator**: Green circle and line show the target and path
- **Axe Animation**: Uses dedicated axe animation sprites from the assets
- **HUD Information**: Shows player position, movement status, and action progress
- **Facing Direction**: Player automatically faces the direction they're moving

## How to Use

1. **Select a Tree**: Click on any tree in the game world
2. **Choose Axe Action**: Click the axe button that appears
3. **Watch Player Move**: The player will automatically walk to the tree
4. **Axe Animation**: When reaching the tree, the axe chopping animation plays
5. **Tree Removal**: After the animation completes, the tree is removed

## Technical Details

### Player States
- **Idle**: Player stands still with idle animation
- **Moving**: Player walks to a target with walking animation
- **Performing Action**: Player plays action-specific animation (e.g., axe chopping)

### Animation System
- **Walking**: 8-frame walking animation
- **Idle**: 9-frame idle animation  
- **Axe**: 10-frame axe chopping animation
- **Smooth Transitions**: Animations blend seamlessly between states

### Movement System
- **Pathfinding**: Direct line movement to target
- **Collision Avoidance**: Player navigates around obstacles
- **Boundary Checking**: Player stays within the game world
- **Speed Control**: Configurable movement speed

## Files Modified

- `main.lua`: Main game logic and player system
- `GameStateManager.lua`: Action handling and object management
- `ButtonManager.lua`: Button action type identification

## Future Enhancements

- **Multiple Actions**: Support for watering, mining, and other actions
- **Inventory System**: Collect resources from chopped trees
- **Sound Effects**: Audio feedback for actions
- **Particle Effects**: Visual effects for tree chopping
- **Pathfinding**: More sophisticated obstacle avoidance

## Troubleshooting

If the player doesn't move to trees:
1. Check that trees are properly loaded as ActionableObjects
2. Verify the axe button appears when selecting trees
3. Check console for debug messages about player movement
5. Ensure the player sprites are loading correctly

## Performance Notes

- Player movement is optimized with efficient collision detection
- Animation frames are managed to prevent memory leaks
- Debug output is limited to avoid console spam
- Movement calculations use efficient math operations
