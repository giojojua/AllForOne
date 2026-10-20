# AllForOne

A minimal, PvP-focused UI for World of Warcraft 3.3.5 (Wrath of the Lich King).

### Install
1. Download this repository (**Code → Download ZIP**) and unzip it.
2. Put the unzipped folder into `World of Warcraft/Interface/AddOns/` and **rename it to `AllForOne`**. WoW only loads an addon whose folder name matches its `.toc` file (`AllForOne.toc`), so a folder called `OneForAll-main` won't load.
3. If you installed an earlier test version, delete any old `MinimalPvP` folder there.
4. Restart the game (or `/reload`) and enable **AllForOne** on the character screen.
5. Type `/afo test` to see every frame with sample arena data.

**Updating:** after replacing the addon files with a newer version, fully restart the game (exit and launch again). A `/reload` doesn't pick up files that are new in that version.

**Reloading in combat:** WoW locks unit frames and action bars during combat, so if you `/reload` mid-fight (e.g. on a training dummy) the UI loads as soon as combat ends.

### What's on screen
- **Left:** you, then your party, each with PvP trinket, health/power, class icon, pet bar, cast bar, key cooldowns, and dispellable / CC debuffs. Your class resource sits right above your own frame (Death Knight runes, Shaman totems with timers, Druid mana in cat/bear form, Warlock soul shards).
- **Who targets whom:** right of every pet bar: the icon + label of who that player is targeting (`#2` = arena 2, `YOU`), and a badge with how many of the other team are targeting them (red on your side, amber on the enemy side).
- **Drinking:** a player who is drinking shows `DRINKING` instead of their health %.
- **Right:** arena enemies 1–5, mirrored: spec, health/power, trinket, pet bar, cast bar, tracked cooldowns, diminishing-returns tracker. Right-click an enemy frame to set focus.
- **Center:** target frame (cast bar, your debuffs, dispellable buffs, combo points), target of target, focus with cast bar, your cast bar. The middle of the screen stays clear for your character.
- **Swing timer:** two thin bars under your cast bar (main hand, off hand) while you auto-attack; Auto Shot / wand Shoot for ranged. Handles dual-wield, parry haste, Heroic Strike/Cleave/Maul/Raptor Strike, Slam and haste changes.
- **Next to your character:** proc alerts (Fingers of Frost, Hot Streak, Predator's Swiftness, …) and a loss-of-control alert when you are CC'd.
- **Nameplates:** class colors, arena number, your debuffs, big CC from anyone, combo points; friendly plates are thin and only show dispellable CC. Totems (Tremor, Grounding, Earthbind…) get half-size plates with the totem's icon.
- **Bottom:** 3 action bars in the middle (bar 1 at the bottom, bar 2 above, bar 3 on top) with the XP/rep bar under them; stance/forms/auras above their left corner and the pet bar above their right corner; 2 vertical bars bottom-right above bags and game menu (faded until hovered). Your Blizzard keybinds keep working.
- **Top:** arena map, bracket and match timer, big gates countdown; buffs (up to 16) and debuffs (up to 8) next to a square minimap (mouse wheel zooms) with small tracking, calendar, world map and addon buttons, clock and latency under it. The addon button (gear, with a count) opens a dropdown holding every other addon's minimap button, so they don't clutter the map; Esc or another click closes it.

### Battlegrounds
- **Raid frames:** in a battleground (or any raid) the party rows on the left hide and a compact grid takes their place under your own frame: one column per group, class-colored health, the most important debuff on each player (crowd control first, then anything you can dispel), a white ring on your target, faded when out of range. Left-click targets, right-click opens the usual raid menu. Move it as "RAID / BATTLEGROUND"; turn it off in `/afo` settings.
- **Flag carriers (Warsong Gulch, Eye of the Storm):** two rows under the minimap: **EFC** (enemy carrying your flag) and **FFC** (your carrier) with class color, health when known (raid member, or an enemy you target/focus/mouse over) and how long they've held it. Click a row to target that carrier. WoW doesn't let addons change click targets during combat, so if a carrier changes mid-fight, the click updates once you leave combat.
- **Score:** Blizzard's battleground score at the top is movable ("BATTLEGROUND SCORE") and uses the UI font.
- **Capture timers:** bases, towers and graveyards being taken (Arathi Basin, Isle of Conquest: 1 min; Alterac Valley: 4 min) count down under the score in the capturing faction's color.
- **Gates countdown** also works in battlegrounds.
- `/afo test bg` shows a sample battleground (raid grid, flag carriers, timers).
- Flag, capture and countdown events come from the English system messages, so they need an English game client.

### Settings
Type `/afo` to open the settings window (UI size, class-colored bars, menu opacity, font, which parts of the UI are on, move mode, reset, test mode, procs). It's also under **Interface → AddOns → AllForOne**. `/afo help` lists every command.

### Profiles (save different versions of your UI)
A profile is a snapshot of your whole UI: where every part sits and how big it is, plus everything in the settings window. Profiles are shared by all your characters, so you can set the UI up once and load it on an alt.
- In the settings window (`/afo`), under **PROFILES**: type a name and press **SAVE CURRENT UI**. Saving under an existing name updates it. **LOAD** switches to a profile; **×** deletes it (click twice to confirm). The profile in use is highlighted.
- Or type `/afo profile save Arena 3v3`, `/afo profile load Arena 3v3`, `/afo profile delete Arena 3v3`, `/afo profile list`.
- Loading a profile doesn't save your current UI first, so save it before switching if you want to keep it. Profiles can't be loaded in combat, and font / turned-off parts change after a `/reload`. Your proc list isn't part of a profile; it stays the same in all of them.

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
| `/afo` | Open the settings window |
| `/afo help` | List every command |
| `/afo profile save/load/delete <name>`, `/afo profile list` | Save and switch versions of your UI |
| `/afo unlock` / `/afo lock` | Move mode on / off |
| `/afo reset` | Put every part back to the default layout |
| `/afo test` | Toggle sample arena data on every frame |
| `/afo test bg` | Sample battleground: raid frames, flag carriers, capture timers |
| `/afo procs` | Open the proc window |
| `/afo scale 0.9` | Resize the whole UI (0.5–2) |
| `/afo colors` | Class-colored bars on/off |
| `/afo menu 0.6` | Idle opacity of bags + menu (0–1, default 0.6) |
| `/afo font` | Bundled font on/off (turn off for Cyrillic or Asian names) |
| `/afo nameplates`, `raid`, `actionbars`, `minimap`, `chat` | Turn a module off/on (needs `/reload`) |

### Notes for 3.3.5
- 3.3.5 has no nameplate API, so enemy debuffs on nameplates come from the combat log: exact when the enemy is your target/focus/arena unit, estimated otherwise.
- Enemy spec is detected from the spells they cast.
- The arena gates countdown reads the English system messages.
- Font: Barlow Condensed (SIL Open Font License, see `Media/OFL.txt`).
