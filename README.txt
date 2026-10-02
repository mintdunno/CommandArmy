COMMAND ARMY — MODULAR BUILD
============================

WHY THIS EXISTS
---------------
The old script was one very large file. That made it hard to isolate bugs and
some executors may reject or truncate large pasted scripts.

The source is split into ordered parts. loader.lua downloads those parts from
GitHub main, concatenates them, and compiles the source with loadstring. Lifecycle
guards combine audited GUI state with confirmed world location; UNKNOWN location
does not authorize another join or troop spawn.

HOW TO RUN
----------
1. Execute loader.lua in a Roblox client executor supporting HTTP and loadstring.
2. The loader fetches parts from mintdunno/CommandArmy on GitHub's main branch.
3. Do NOT execute files inside parts/ directly.

Local edits to parts are not used by this HTTP loader until published to the
configured GitHub branch. To target another published branch, edit BASE in loader.lua.

FILES
-----
loader.lua
    Tiny bootstrap. Reads every part, reports missing files / compile errors /
    startup runtime errors on screen, then launches the reconstructed script.

parts/00_shell.lua
    PlayerGui shell and startup wrapper.

parts/01_config_state.lua
    Configuration and runtime state.

parts/02_location.lua
    Character/team/map/area detection.

parts/03_gui_and_movement.lua
    Main UI helpers and basic movement/vote-pad movement.

parts/04_pathfinding.lua
    Path creation, waypoint walking, obstacle handling.

parts/05_lobby_and_join.lua
    Map voting and joining a team/match.

parts/06_camp.lua
    Supply/camp discovery and camp movement.

parts/07_supply_ui.lua
    Match supply menu discovery/opening.

parts/08_troops.lua
    Troop state, slot selection, spawn cycle, attack state.

parts/09_match_and_main.lua
    Match lifecycle, continue handling, main automation loop.

parts/10_controls_and_settings.lua
    START/STOP behavior and GUI settings controls.

parts/11_live_info_and_init.lua
    Live UI status and delayed game-component/remote initialization.

DEBUGGING RULE
--------------
Keep changes focused, and review shared lifecycle guards when a transition
affects joining, camp movement, and troops together. Player Spawn and MatchUI
SpawnTroops are separate processes. MatchResult pauses automation until return.

Keep a copy of the last working folder before every change.
