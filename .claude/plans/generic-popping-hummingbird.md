# Frogger: Fix Arrow Hint Touch Areas and Remove Keyboard Control

## Context
The Frogger game has arrow triangle hints in the HUD to indicate touch zones for movement. However:
1. The arrow visuals are tiny 6-pixel triangles, while the actual touch zones are entire thirds of the screen
2. The visual arrow positions don't clearly match the touch zone boundaries
3. PRD states "keyboard support is optional/secondary" and "touch-first" is required

## Issues to Fix

### Issue 1: Remove Keyboard Control
- **Location**: `lib/games/frogger.dart`, lines 530-559 (`onKeyEvent` method)
- **Action**: Remove the `KeyboardEvents` mixin and the `onKeyEvent` method entirely
- **Rationale**: Touch-first mobile design, keyboard is optional per PRD

### Issue 2: Arrow Hint Touch Area Mismatch
- **Location**: `lib/games/frogger.dart`, `_HudRenderer` class, lines 1036-1127
- **Problem**: Arrow triangles (size=6) are drawn at zone centers, but touch zones are full thirds of screen
- **Current positions**:
  - UP: (128, 40) - center of top third
  - DOWN: (128, 200) - center of bottom third
  - LEFT: (42.67, 120) - center of middle-left
  - RIGHT: (213.33, 120) - center of middle-right
- **Solution**: Make arrow hints larger and better positioned to clearly indicate zones

## Files to Modify
- `lib/games/frogger.dart`

## Implementation Plan

### Step 1: Remove Keyboard Support
1. Remove `KeyboardEvents` from class mixin on line 79
2. Delete `onKeyEvent` method (lines 530-559)

### Step 2: Fix Arrow Hint Visual Alignment
1. Increase arrow size from 6 to 12 pixels for better visibility
2. Adjust arrow positions to better represent zone boundaries:
   - UP arrow: Keep at top-center but perhaps lower in the zone
   - DOWN arrow: Move higher in the zone
   - LEFT/RIGHT arrows: Better positioned at zone boundaries
3. Add subtle zone outline hints to make touch areas more obvious

### Step 3: Verify Touch Detection Logic
The touch detection in `onTapDown` (lines 506-524) divides screen into thirds:
- `ly < thirdY` (80) → UP
- `ly > thirdY * 2.0` (160) → DOWN
- `thirdY <= ly <= thirdY*2` AND `lx < thirdX` → LEFT
- `thirdY <= ly <= thirdY*2` AND `lx > thirdX*2` → RIGHT

This logic is correct and doesn't need changes.

## Verification
1. Run the game and test touch controls in all 4 directions
2. Verify arrow hints visually align with where taps register
3. Confirm keyboard no longer controls frog movement
