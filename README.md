# AllForOne

A minimal, PvP-focused UI for World of Warcraft 3.3.5 (Wrath of the Lich King).

### Install
1. Download this repository (**Code → Download ZIP**) and unzip it.
2. Put the unzipped folder into `World of Warcraft/Interface/AddOns/` and **rename it to `AllForOne`**. WoW only loads an addon whose folder name matches its `.toc` file (`AllForOne.toc`), so a folder called `OneForAll-main` won't load.
3. If you installed an earlier test version, delete any old `MinimalPvP` folder there.
4. Restart the game (or `/reload`) and enable **AllForOne** on the character screen.
5. Type `/afo test` to see every frame with sample arena data.

### What's on screen
- **Left:** you, then your party, each with PvP trinket, health/power, class icon, pet bar, cast bar, key cooldowns, and dispellable / CC debuffs.
- **Right:** arena enemies 1–5, mirrored: spec, health/power, trinket, pet bar, cast bar, tracked cooldowns, diminishing-returns tracker. Right-click an enemy frame to set focus.
- **Center:** target frame (cast bar, your debuffs, dispellable buffs, combo points), target of target, focus with cast bar, your cast bar. The middle of the screen stays clear for your character.
- **Swing timer:** two thin bars under your cast bar (main hand, off hand) while you auto-attack; Auto Shot / wand Shoot for ranged. Handles dual-wield, parry haste, Heroic Strike/Cleave/Maul/Raptor Strike, Slam and haste changes.
- **Next to your character:** proc alerts (Fingers of Frost, Hot Streak, Predator's Swiftness, …) and a loss-of-control alert when you are CC'd.
- **Nameplates:** class colors, arena number, your debuffs, big CC from anyone, combo points; friendly plates are thin and only show dispellable CC.
- **Bottom:** 3 action bars in the middle (bar 1 at the bottom, bar 2 above, bar 3 on top) with the XP/rep bar under them; stance/forms/auras above their left corner and the pet bar above their right corner; 2 vertical bars bottom-right above bags and game menu (faded until hovered). Your Blizzard keybinds keep working.
- **Top:** arena map, bracket and match timer, big gates countdown; buffs (up to 16) and debuffs (up to 8) next to a square minimap with clock and latency.

### Move and resize anything
Type `/afo unlock`. Every part gets a labeled box: drag it to move, use the mouse wheel to resize (50–200%), right-click to put that part back. Type `/afo lock` to finish. Positions are saved per character; `/afo reset` restores the default layout. Moving only works out of combat (a game rule), and combat ends move mode automatically.

### Choose which procs to show
Procs appear as glowing icons next to your character. Nothing is tracked until you pick it: type `/afo procs` to open the proc window.
- **Add box:** type a buff name or spell ID and press Enter.
- **Tracked:** your list, with × to remove.
- **Suggested for your class:** common procs for your class, + to add.
- **Your buffs right now:** whatever is on you this moment, + to add (handy when a proc pops and you don't know its exact name).

Your list is saved for your account. Commands also work: `/afo procs add <name or ID>`, `/afo procs remove <name or ID>`, `/afo procs reset` (clears the list).

### Commands
| Command | What it does |
|---|---|
| `/afo unlock` / `/afo lock` | Move mode on / off |
| `/afo reset` | Put every part back to the default layout |
| `/afo test` | Toggle sample data on every frame |
| `/afo procs` | Open the proc window |
| `/afo scale 0.9` | Resize the whole UI (0.5–2) |
| `/afo colors` | Class-colored bars on/off |
| `/afo menu 0.4` | Idle opacity of bags + menu (0–1) |
| `/afo font` | Bundled font on/off (turn off for Cyrillic or Asian names) |
| `/afo nameplates`, `actionbars`, `minimap`, `chat` | Turn a module off/on (needs `/reload`) |

### Notes for 3.3.5
- 3.3.5 has no nameplate API, so enemy debuffs on nameplates come from the combat log: exact when the enemy is your target/focus/arena unit, estimated otherwise.
- Enemy spec is detected from the spells they cast.
- The arena gates countdown reads the English system messages.
- Font: Barlow Condensed (SIL Open Font License, see `Media/OFL.txt`).
