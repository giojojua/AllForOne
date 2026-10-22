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
- **Nameplates:** class colors, health and percentage inside the bar (`23.1k · 74%`), arena number, your debuffs, big CC from anyone, combo points; friendly plates are thin and only show dispellable CC. Totems (Tremor, Grounding, Earthbind…) get half-size plates with the totem's icon.
- **Bottom:** 3 action bars in the middle (bar 1 at the bottom, bar 2 above, bar 3 on top) with the XP/rep bar under them; stance/forms/auras above their left corner and the pet bar above their right corner; 2 vertical bars bottom-right above bags and game menu (faded until hovered). Your Blizzard keybinds keep working. Button icons turn **red** when your target is out of range for that spell, **blue** when you don't have enough mana / rage / energy / runic power, and **dark** when it can't be used right now; this works for macros too (turn it off in `/afo` settings).
- **Top:** arena bar with map, bracket, match timer and players alive (`3 v 3`); the gates countdown is shown inside that bar (`GATES 0:31`), also in battlegrounds; buffs (up to 16) and debuffs (up to 8) next to a square minimap (mouse wheel zooms) with small tracking, calendar, world map and addon buttons, clock and latency under it. The addon button (gear, with a count) opens a dropdown holding every other addon's minimap button, so they don't clutter the map; Esc or another click closes it.

### Kill target helper (arena 2s, 3s, solo queue)
Puts a **red cross** right next to the health % of the enemy to kill (on their frame and nameplate) and, when it matters, a **blue square** on their healer to crowd-control. When the target should change, the cross simply moves. Hover an enemy frame to see the reasons.
- **Raises an enemy's score:** low health, PvP trinket used, big defensives on cooldown (Divine Shield, Ice Block, Cloak, Evasion, Pain Suppression, Barkskin, Shield Wall, Deterrence, Icebound Fortitude...), a class/spec with few escapes, no stun diminishing returns yet, their healer crowd-controlled. In 2s a healer next to a very tanky partner leans toward KILL; a drinking healer gets pushed up.
- **Your team counts too:**
  - a Priest (Mass Dispel) or Warrior (Shattering Throw) on your team makes Ice Block and Divine Shield removable: Mages and Paladins score higher, and when one of them blocks or bubbles, the cross **stays** on them and the tooltip says what to use;
  - two or more melee on your team: cloth targets (Mage, Warlock, Priest) score higher;
  - mostly physical team: once their Paladin's Hand of Protection is on cooldown, everyone else scores higher — and against a caster team Hand of Protection doesn't count as an immunity at all.
- **Lowers it:** a defensive up right now. Immune (Divine Shield, Ice Block, Deterrence, Hand of Protection) means **SWAP**: the mark moves to someone else at once.
- **CC** goes on their healer when your kill target drops under 60%.
- It doesn't flip back and forth: a new target has to be clearly better before the mark moves.
- **Party announce:** short messages in party chat. `Kill Warrior` when the helper makes its first call of the match. When it later suggests another target, the cross moves, and `Switch Priest` is only sent once **you** target that enemy (with two of the same class it adds the name: `Kill Grimtusk Warrior`), so the party follows your actual swap. If a teammate also runs AllForOne and just called it, you stay quiet.
- Turn the helper or the announcements off in `/afo` settings (ARENA).
- It's a strong hint, not an order: it can't see positioning or line of sight, and the enemy spec is only known once they cast something spec-specific.

### Arena analyzer
Every arena you play is recorded from the combat log. When the match ends a small popup shows the result and how many notes there are; **OPEN REPORT** (or `/afo arena`) opens the report. Each character keeps its own history: the **last 50 arenas** of the character you're playing; older ones are deleted automatically.

**The report**
- **Notes** — likely mistakes, most important first:
  - trinket used with no crowd control, on a root/silence/disarm, or with under 1.5s left
  - sat in a long crowd control with your trinket ready while a teammate was under 30%
  - died with your trinket or a life-saving defensive ready (Ice Block, Divine Shield, Cloak, Evasion, Pain Suppression, Shield Wall, Deterrence...)
  - big defensive used above 70% health with little damage coming in
  - interrupts that missed (dodged, or the target wasn't casting)
  - interrupted on long casts you started while their interrupt was ready
  - your crowd control wasted (immune from diminishing returns, reflected, grounded), landed at a quarter duration, broken early by your own team, or overlapping a teammate's
  - out of your healer's range for a large part of the fight (or, as a healer, teammates out of yours)
  - little of your damage on the marked kill target
- **Deaths** — who died when, first death, and for your team a recap of the 10 seconds before: damage by spell and source, crowd control on them / your healer, cooldowns they used.
- **Stats** — crowd control on you (by type) and yours; trinket and defensive timings; interrupts (landed on heals / crowd control / damage, how far into the cast); damage done per target and on the kill target, damage taken by spell, biggest 3-second burst on you; healing and overhealing; dispels and purges; range.
- **Enemies** — per enemy: died / died first, how fast they went down, trinketed (early?), defensives used or died with one unused, time crowd-controlled.
- **Timeline** — gates, trinkets, defensives, interrupts, deaths.
- **Trends (last 50)** — win rate, record against each enemy comp, average time crowd-controlled, interrupt success, and mistakes that repeat in your last 10 games.

**Enemy history** — the analyzer remembers what each enemy player did in your stored matches (died first, wasted trinket, died with defensives up, used defensives early). Once you've faced someone twice, the kill target helper gives them a bonus and shows why (`died first 3/4`), and a note appears under known enemies (`faced 5× · died first 4×`). Newer games count more; since it's built from the stored 50 matches, it ages out with them.

`/afo arena test` shows a sample report; `/afo arena reset` (twice) deletes this character's history. Settings: ARENA → *Arena analyzer* and *Report popup after each arena*.

Limits: only what the combat log shows within about 50 yards; no line of sight or positioning; notes are hints, not a grade.

### Battlegrounds
- **Raid frames:** in a battleground (or any raid) the party rows on the left hide and a compact grid takes their place under your own frame: one column per group (in Alterac Valley and Isle of Conquest: 10 players per column, so 40 players fit in 4 columns), class-colored health, the most important debuff on each player (crowd control first, then anything you can dispel), a white ring on your target, faded when out of range. Left-click targets, right-click opens the usual raid menu. Move it as "RAID / BATTLEGROUND"; turn it off in `/afo` settings.
- **Flag carriers (Warsong Gulch, Eye of the Storm):** two rows under the minimap: **EFC** (enemy carrying your flag) and **FFC** (your carrier) with class color, health when known (raid member, or an enemy you target/focus/mouse over) and how long they've held it. Click a row to target that carrier. WoW doesn't let addons change click targets during combat, so if a carrier changes mid-fight, the click updates once you leave combat.
- **Score:** Blizzard's battleground score at the top is movable ("BATTLEGROUND SCORE") and uses the UI font.
- **Capture timers:** bases, towers and graveyards being taken (Arathi Basin, Isle of Conquest: 1 min; Alterac Valley: 4 min) count down under the score in the capturing faction's color.
- **Gates countdown** also works in battlegrounds (in a small bar at the top, gone once the gates open).
- **Arenas after a battleground:** arenas always use the party rows, even if you come straight from a raid or the server puts the arena team in a raid group.
- `/afo test bg` shows a sample battleground (raid grid, flag carriers, timers).
- Flag, capture and countdown events come from the English system messages, so they need an English game client.

### Settings
Type `/afo` to open the settings window (UI size, class-colored bars, menu opacity, font, which parts of the UI are on, move mode, reset, test mode, procs). It's also under **Interface → AddOns → AllForOne**. `/afo help` lists every command.

### Profiles (save different versions of your UI)
A profile is a snapshot of your whole UI: where every part sits and how big it is, plus everything in the settings window. Profiles are shared by all your characters, so you can set the UI up once and load it on an alt.
- In the settings window (`/afo`), under **PROFILES**: type a name and press **SAVE CURRENT UI**. Saving under an existing name updates it. **LOAD** switches to a profile; **×** deletes it (click twice to confirm). The profile in use is highlighted.
- Or type `/afo profile save Arena 3v3`, `/afo profile load Arena 3v3`, `/afo profile delete Arena 3v3`, `/afo profile list`.
- Loading a profile doesn't save your current UI first, so save it before switching if you want to keep it. Profiles can't be loaded in combat, and font / turned-off parts change after a `/reload`. Your proc list isn't part of a profile; it stays the same in all of them.

### Red error messages
`/afo` → LOOK → **Hide red error messages** turns off the red text in the middle of the screen ("Not enough rage", "Out of range", "Spell is not ready yet"). Yellow information (quest progress, "joined the queue", battleground messages) keeps showing. Off by default; saved in profiles.

### Clicking frames
- **Left-click** any frame: target. **Shift + left-click**: set focus.
- **Right-click** an enemy arena frame: set focus. Right-click your **focus frame**: clear focus. Right-click your own / party / raid frames: the usual menu.
- The menus no longer have "Set Focus" / "Clear Focus": WoW blocks those for addon frames ("AllForOne has been blocked from an action only available to the Blizzard UI").

### Move and resize anything
Type `/afo unlock`. Every part gets a labeled box: drag it to move, use the mouse wheel to resize (50–200%), right-click to put that part back. Type `/afo lock` to finish. Positions are saved per character; `/afo reset` restores the default layout. Moving only works out of combat (a game rule), and combat ends move mode automatically.

### Choose which procs to show
Procs appear as glowing icons next to your character. Nothing is tracked until you pick it: type `/afo procs` to open the proc window.
- **Add box:** type a buff name or spell ID and press Enter.
- **Tracked:** your list, with × to remove.
- **Suggested for your class:** common procs for your class, + to add.
- **Your buffs right now:** whatever is on you this moment, + to add (handy when a proc pops and you don't know its exact name).

Each character has its own list (a new character starts from your old shared list, without other classes' procs). Commands also work: `/afo procs add <name or ID>`, `/afo procs remove <name or ID>`, `/afo procs reset` (clears this character's list).

### Commands
| Command | What it does |
|---|---|
| `/afo` | Open the settings window |
| `/afo help` | List every command |
| `/afo profile save/load/delete <name>`, `/afo profile list` | Save and switch versions of your UI |
| `/afo arena` | Arena analyzer (this character's last 50 matches); `test` = sample report, `reset` = delete this character's history |
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
