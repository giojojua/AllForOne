# WoW 3.3.5 Addons

## AllForOne

A minimal, PvP-focused UI for World of Warcraft 3.3.5 (Wrath of the Lich King).

### Install
1. Copy the `AllForOne` folder into `World of Warcraft/Interface/AddOns/`. If you installed the earlier test version, delete the old `MinimalPvP` folder there first.
2. Restart the game (or `/reload`) and enable **AllForOne** on the character screen.
3. Type `/afo test` to see every frame with sample arena data.

### What's on screen
- **Left:** you, then your party, each with PvP trinket, health/power, class icon, pet bar, cast bar, key cooldowns, and dispellable / CC debuffs.
- **Right:** arena enemies 1–5, mirrored: spec, health/power, trinket, pet bar, cast bar, tracked cooldowns, diminishing-returns tracker. Right-click an enemy frame to set focus.
- **Center:** target frame (cast bar, your debuffs, dispellable buffs, combo points), target of target, focus with cast bar, your cast bar. The middle of the screen stays clear for your character.
- **Swing timer:** two thin bars under your cast bar (main hand, off hand) while you auto-attack; Auto Shot / wand Shoot for ranged. Handles dual-wield, parry haste, Heroic Strike/Cleave/Maul/Raptor Strike, Slam and haste changes.
- **Next to your character:** proc alerts (Fingers of Frost, Hot Streak, Predator's Swiftness, …) and a loss-of-control alert when you are CC'd.
- **Nameplates:** class colors, arena number, your debuffs, big CC from anyone, combo points; friendly plates are thin and only show dispellable CC.
- **Bottom:** 3 action bars + XP/rep bar in the middle, 2 vertical bars bottom-right above bags and game menu (faded until hovered). Your Blizzard keybinds keep working.
- **Top:** arena map, bracket and match timer, big gates countdown; buffs/debuffs next to a square minimap with clock and latency.

### Commands
| Command | What it does |
|---|---|
| `/afo test` | Toggle sample data on every frame |
| `/afo scale 0.9` | Resize the whole UI (0.5–2) |
| `/afo colors` | Class-colored bars on/off |
| `/afo menu 0.4` | Idle opacity of bags + menu (0–1) |
| `/afo font` | Bundled font on/off (turn off for Cyrillic or Asian names) |
| `/afo nameplates`, `actionbars`, `minimap`, `chat` | Turn a module off/on (needs `/reload`) |

### Notes for 3.3.5
- 3.3.5 has no nameplate API, so enemy debuffs on nameplates come from the combat log: exact when the enemy is your target/focus/arena unit, estimated otherwise.
- Enemy spec is detected from the spells they cast.
- The arena gates countdown reads the English system messages.
- Font: Barlow Condensed (SIL Open Font License, see `AllForOne/Media/OFL.txt`).
