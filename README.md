Nips Roll (NRG) – Release v1.0.1
🎲 Overview

Nips Roll (NRG) is a lightweight WoW 3.3.5a addon for Project Epoch (and other Wrath private servers) that makes hosting fun roll-based betting games easy. Inspired by Cross Gambling, it adds Hi/Lo roll games and 1v1 Death Rolls, with automatic announcements, player joins, and result tracking.

Open the panel with /nrg.

✨ Features

Hi/Lo Mode

Host sets gold bet and roll range (default 1–100).

Players join by typing 1 in the chosen channel (SAY, PARTY, RAID, or BATTLEGROUND).

“Last Call” option to announce a final join reminder.

Host clicks Start Rolling! → addon listens for rolls and auto-announces results.

Settlement announced: lowest roller pays highest roller the bet amount.

Death Roll Mode

Classic 1v1 elimination roll game.

Host sets starting max (default 1000).

Players alternate /roll 1-X. The roll sets the new max for the next turn.

First player to roll 1 loses, pays the opponent the bet amount.

Addon enforces turn order and announces each step.

Channel Support

Works in SAY, PARTY, RAID, and BATTLEGROUND chats.

Listens to both normal and leader variations (e.g. RAID_LEADER).

Join System

Players don’t need the addon — they just type 1 in chat.

Host sees a live roster of who joined and their rolls.

Robust Roll Parsing

Compatible with Wrath 3.3.5 roll messages (Name rolls 42 (1-100)).

Filters invalid ranges and duplicate rolls.

UI Host Panel

Easy buttons for New Game, Last Call, Join (Self), Start Rolling, Cancel/Reset.

Editable bet, roll range, starting max, and death roll participants.

Drag/movable panel with roster box showing game state.

🛠 Fixes in v1.0.1

Slash Command Reliability
/nrg now always works, even if other parts of the addon fail.

3.3.5a Compatibility

Added event support for *_LEADER chat events.

Roll parser tightened for Wrath-era format.

UI Safety
Built only after ADDON_LOADED to prevent nil errors.

Channel Fallback
If chosen channel is unavailable (e.g., RAID not in a raid), announcements echo locally with a warning.

General Stability
Removed fragile API calls, ensured legacy string helpers exist, hardened state resets.

🚀 Install

Extract into:

World of Warcraft\Interface\AddOns\NipsRoll\


So you have:

...\NipsRoll\NipsRoll.toc
...\NipsRoll\NipsRoll.lua


On the character AddOns screen, check Load out of date AddOns.

In-game, type /nrg to open the host panel.

🧩 Planned Features

Stats tracking (lifetime wins/losses by player).

Tie-breaker automation for Hi/Lo ties.

Auto-timers for join phase with countdown announcements.

Optional whisper trade reminders to winner/loser.

Guild and Raid Warning channel support.

Localized roll parser for non-English clients.
