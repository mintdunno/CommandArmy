COMMAND ARMY — MODULAR BUILD
============================

WHY THIS EXISTS
---------------
The old script was one very large file. That made it hard to isolate bugs and
some executors may reject or truncate large pasted scripts.

This build does NOT refactor the automation logic yet. The current hardened
source was cut into smaller files in the exact same order. loader.lua reads the
parts, concatenates them, then compiles the reconstructed source with loadstring.
That means we can now fix one area at a time without rewriting the whole script.

HOW TO RUN
----------
1. Put the entire "CommandArmy" folder inside the local workspace used by your
   executor's readfile()/isfile() functions.
2. Execute CommandArmy/loader.lua.
3. Do NOT execute files inside parts/ directly.

If your executor stores the folder under a different path, edit this line at the
top of loader.lua:

    local ROOT = "CommandArmy"

Example:

    local ROOT = "scripts/CommandArmy"

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
From now on, fix ONE subsystem at a time. For example, if troop cycling is wrong,
work only in parts/08_troops.lua and test before touching lobby/pathfinding.

Keep a copy of the last working folder before every change.
