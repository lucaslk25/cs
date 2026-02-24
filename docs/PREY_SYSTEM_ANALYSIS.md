# Prey System — Full Analysis

> **Purpose:** Reference documentation for designing the Instance Hunt system.
> **Created:** 2026-02-07
> **Source:** Crystal Server codebase analysis

---

## 1. Overview

The Prey system gives players 3 slots where they select a monster to hunt with a bonus (damage, defense, XP, or loot). Each slot has a 2-hour timer and a grid of 9 monsters to choose from. Rerolling the list costs gold; rerolling the bonus costs prey wildcard cards.

This document serves as a reference for designing the Instance Hunt system, which adapts the Prey's UI patterns, slot management, and timer mechanics.

---

## 2. Files

### Server (C++)

| File | Purpose |
|------|---------|
| `src/io/ioprey.hpp` | `PreySlot` class and enums |
| `src/io/ioprey.cpp` | `PreySlot` logic and `IOPrey` manager |
| `src/creatures/players/player.hpp` / `.cpp` | Player prey methods |
| `src/server/network/protocol/protocolgame.cpp` | `sendPreyData` (0xE8), `parsePreyAction`, `sendPreyPrices` (0xE9), `sendPreyTimeLeft` (0xE7) |
| `src/io/functions/iologindata_save_player.cpp` | Database save |
| `src/io/functions/iologindata_load_player.cpp` | Database load |
| `src/lua/functions/creatures/player/player_functions.cpp` | Lua bindings |
| `src/creatures/combat/combat.cpp` | Bonus application in combat |

### Server (Lua)

| File | Purpose |
|------|---------|
| `data/scripts/eventcallbacks/monster/ondroploot_prey.lua` | Loot bonus handler |
| `data/events/scripts/player.lua` | Experience bonus application |

### Client (OTClient)

| File | Purpose |
|------|---------|
| `modules/game_prey/prey.otmod` | Module definition |
| `modules/game_prey/prey.lua` | Main UI logic (1926 lines) |
| `modules/game_prey/prey.otui` | UI layout (845 lines) |

### Database

| Table | Purpose |
|-------|---------|
| `player_prey` | Persists slot state, selected monster, bonus, timer |

---

## 3. Data Structures

### PreySlot (C++)

```cpp
class PreySlot {
    PreySlot_t id;                    // 0, 1, or 2
    PreyBonus_t bonus;                // Damage, Defense, Experience, Loot
    PreyDataState_t state;            // Current state (see below)
    PreyOption_t option;              // None, AutomaticReroll, Locked
    std::vector<uint16_t> raceIdList; // Monster grid (9 monsters)
    uint8_t bonusRarity;              // 1-10 (stars)
    uint16_t selectedRaceId;          // Selected monster race ID
    uint16_t bonusPercentage;         // Bonus percentage value
    uint16_t bonusTimeLeft;           // Time remaining in seconds
    int64_t freeRerollTimeStamp;      // Next free reroll timestamp
};
```

### Enums

```cpp
enum PreySlot_t { PreySlot_One = 0, PreySlot_Two = 1, PreySlot_Three = 2 };

enum PreyDataState_t {
    Locked,                   // Slot not available (needs premium/purchase)
    Inactive,                 // Available but no monster selected
    Active,                   // Monster selected, bonus running
    Selection,                // Showing 9-monster grid
    SelectionChangeMonster,   // Changing monster while keeping bonus
    ListSelection,            // Full bestiary list (costs cards)
    WildcardSelection         // Wildcard selection mode
};

enum PreyBonus_t { Damage, Defense, Experience, Loot };

enum PreyAction_t {
    ListReroll,               // Reroll the 9-monster list
    BonusReroll,              // Reroll bonus type (keep monster)
    MonsterSelection,         // Select from grid (index 0-8)
    ListAll_Cards,            // Request full monster list
    ListAll_Selection,        // Select from full list (raceId)
    Option                    // Toggle auto-reroll or lock
};
```

---

## 4. System Flow

### Initialization (on login)

1. `Player::initializePrey()` creates 3 slots
2. Slot 1: always available (if `PREY_ENABLED`)
3. Slot 2: requires Premium
4. Slot 3: requires `PREY_FREE_THIRD_SLOT` config or store purchase
5. Each slot starts in `Selection` state with a generated 9-monster grid

### Player Opens Prey Dialog

1. Client sends `parsePreyAction` request
2. Server calls `Game::playerPreyAction()` -> `IOPrey::parsePreyAction()`
3. Server sends `sendPreyData()` for each slot (opcode 0xE8)
4. Server sends `sendPreyPrices()` (opcode 0xE9) with costs

### Monster Selection

1. Player clicks a monster in the 3x3 grid
2. Client sends `PreyAction_MonsterSelection` with index (0-8)
3. Server validates: slot not occupied, monster not already selected, monster is preyable
4. Server generates bonus (`reloadBonusType()`, `reloadBonusValue()`)
5. Sets state to `Active`, `bonusTimeLeft` to `PREY_BONUS_TIME` (default 7200s = 2h)
6. Sends updated slot data to client

### Reroll Mechanism

**List reroll:**
- Free if `freeRerollTimeStamp` has expired
- Otherwise costs: `playerLevel * PREY_REROLL_PRICE_LEVEL` gold (default: level * 200)
- Regenerates the 9-monster grid
- Resets free reroll timer to `PREY_FREE_REROLL_TIME` (default 20h)

**Bonus reroll:**
- Costs `PREY_BONUS_REROLL_PRICE` prey cards (default 1)
- Rerolls bonus type and value, resets timer to full duration

### Timer System

- `player:removePreyStamina(amount)` calls `IOPrey::checkPlayerPreys(player, amount)`
- Decrements `bonusTimeLeft` by amount (typically 1 second per call)
- When timer expires:
  - `AutomaticReroll` option: auto-rerolls if player has cards
  - `Locked` option: extends timer if player has cards
  - Otherwise: erases bonus, regenerates grid, sets state to Selection

---

## 5. Protocol

### Server -> Client

| Opcode | Name | Format |
|--------|------|--------|
| 0xE8 (232) | sendPreyData | `[U8: slot][U8: state][...state-specific data]` |
| 0xE7 (231) | sendPreyTimeLeft | `[U8: slot][U16: timeLeft]` (seconds) |
| 0xE9 (233) | sendPreyPrices | `[U32: rerollPrice][U8: wildcardPrice][U8: directPrice]` |
| 0xE6 (230) | sendPreyFreeRerolls | `[U8: slot][U16: timeLeft]` (minutes) |

**State-specific data for sendPreyData:**

- **Active:** `[String: name][Outfit][U8: bonusType][U16: bonusValue][U8: bonusGrade][U16: timeLeft][U32: nextFreeReroll][U8: wildcards][U8: option]`
- **Selection:** `[U8: count][...monsters: name+outfit][U32: nextFreeReroll][U8: wildcards]`
- **Locked:** `[U8: unlockState][U32: nextFreeReroll][U8: wildcards]`
- **Inactive:** `[U32: nextFreeReroll][U8: wildcards]`
- **ListSelection:** `[U16: count][...U16: raceIds][U32: nextFreeReroll][U8: wildcards]`

### Client -> Server

| Opcode | Name | Format |
|--------|------|--------|
| 0xEB (235) | sendPreyAction | `[U8: slot][U8: actionType][U8/U16: index]` |
| 0xED (237) | sendPreyRequest | `[U8: opcode]` |

---

## 6. Bonus Calculation

### Rarity (Stars)

- Range: 1-10
- On reroll: `uniform_random(currentRarity + 1, 10)`
- At rarity 9+, guaranteed to reach 10

### Percentage by Type

| Type | Formula | At rarity 10 |
|------|---------|-------------|
| Damage | `2 * rarity + 5` | 25% |
| Defense | `2 * rarity + 10` | 30% |
| Experience | `3 * rarity + 10` | 40% |
| Loot | `3 * rarity + 10` | 40% |

### Bonus Application

- **Damage:** Applied in `Combat::doCombatHealth()` — increases damage to selected monster
- **Defense:** Applied in `Combat::doCombatHealth()` — reduces damage from selected monster
- **Experience:** Applied in `Player::onGainExperience()` (Lua) — multiplies XP gained
- **Loot:** Applied in `ondroploot_prey.lua` — chance for extra loot roll on corpse

---

## 7. Monster Grid Generation

Generates 9 monsters based on player level:

| Level Range | 1-star | 2-star | 3-star | 4+ star |
|-------------|--------|--------|--------|---------|
| 0-99 | 3 | 3 | 2 | 1 |
| 100-299 | 1 | 3 | 3 | 2 |
| 300-499 | 1 | 2 | 3 | 3 |
| 500+ | 1 | 1 | 3 | 4 |

Filters: must be preyable (`isPreyable`), not exclusive, has experience.

---

## 8. Configuration

From `config.lua.dist`:

```lua
preySystemEnabled = true
preyFreeThirdSlot = false
preyRerollPricePerLevel = 200       -- gold per level for list reroll
preySelectListPrice = 5             -- prey cards to open full list
preyBonusRerollPrice = 1            -- prey cards to reroll bonus
preyBonusTime = 2 * 60 * 60        -- 7200 seconds (2 hours)
preyFreeRerollTime = 20 * 60 * 60  -- 72000 seconds (20 hours)
```

---

## 9. Database Schema

```sql
CREATE TABLE `player_prey` (
    `player_id` int(11) NOT NULL,
    `slot` tinyint(1) NOT NULL,
    `state` tinyint(1) NOT NULL,
    `raceid` varchar(250) NOT NULL,
    `option` tinyint(1) NOT NULL,
    `bonus_type` tinyint(1) NOT NULL,
    `bonus_rarity` tinyint(1) NOT NULL,
    `bonus_percentage` varchar(250) NOT NULL,
    `bonus_time` varchar(250) NOT NULL,
    `free_reroll` bigint(20) NOT NULL,
    `monster_list` BLOB NULL,
    PRIMARY KEY (`player_id`, `slot`)
);
```

---

## 10. Client UI Structure (OTClient)

### Main Window (688x520)

Contains 3 slot panels side-by-side, each with 3 possible states:

**Inactive state:**
- 3x3 grid of `PreyCreatureBox` widgets (9 monsters)
- Full list view with search (scrollable, filterable)
- Preview panel for selected creature
- Buttons: reroll (with timer), select (wildcard), choose (confirm)

**Active state:**
- Creature display with outfit rendering
- Bonus icon and grade stars (1-10)
- Time left progress bar
- Buttons: reroll, select, bonus reroll
- Options: auto-reroll checkbox, lock prey checkbox

**Locked state:**
- Shop buttons for permanent/temporary unlock

### Prey Tracker (MiniWindow)

Compact sidebar view showing all 3 slots:
- Creature name and outfit (or inactive icon)
- Bonus type icon
- Time remaining progress bar
- Clickable to open main window

### Lua Bindings

```lua
g_game.preyAction(slot, actionType, index) -- send action to server
g_game.preyRequest()                       -- request data update
```

---

## 11. Key Takeaways for Instance Hunt

1. **Slot-based management** works well for tracking active state per player
2. **State machine** (Locked/Inactive/Active/Selection) provides clean UI transitions
3. **Binary protocol** is efficient but Extended Opcode JSON is faster to implement
4. **Timer decrement** is called from Lua, keeping logic flexible
5. **Database persistence** is essential for offline state and reconnection
6. **Grid UI** with search provides good UX for selection — adapt for hunt zones instead of monsters
7. **Prey tracker** miniwindow pattern is reusable for active hunt display
8. **Configuration via config.lua** keeps balancing values easy to adjust
