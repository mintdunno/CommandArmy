-- CONFIG

--==================================================

local CONFIG = {
    MovementMode = "Walk",
    AutoVote = true,
    AutoJoin = true,
    AutoNextRound = true,
    AutoCamp = true,
    AutoSpawn = true,
    AutoAttack = true,
    AutoContinue = true,
    MapFallback = "Available",
    MapEnabled = {THERMOPYLAE=true, PLAINS=true, FORTRESS=true},
    CampMode = "Nearest",
    SelectedCamp = "",
    SlotOrder = {1,2,3,4},
    SlotsEnabled = {true,true,true,true},
    UIScale = 1,
    UITransparency = 0,
    UIHotkey = "RightControl",

    -- Highest available map wins.

    MapPriority = {

        "THERMOPYLAE",

        "PLAINS",

        "FORTRESS",

    },

    Team = "Attackers",

    LobbyMarker = "Play",

    PostTeleportDelay = 0.5,

    -- Bounded physical movement; MoveToFinished is not a vote acknowledgement.
    MoveTimeout = 12,

    VoteHoldTime = 0.6,

    VoteSearchTimeout = 10,
    VoteStableTime = 0.35,
    VoteRetries = 3,
    VotePartNames = { "Trigger", "Hitbox", "VotePart", "Pad", "Button" },

    ActiveMapCheckInterval = 0.2,

    JoinTimeout = 12,
    AreaConfirmTime = 0.6,
    FlowRetryDelay = 3,
    ContinueCheckInterval = 0.4,
    ContinueClickInterval = 1.5,

    -- Pathfinding

    AgentRadius = 3,

    AgentHeight = 5,

    AgentCanJump = true,

    AgentCanClimb = true,

    WaypointSpacing = 4,

    WaypointTolerance = 3,

    StuckTimeout = 2.5,

    StuckDistance = 1,

    MaxRepaths = 6,
    BlockedGraceTime = 1.2,
    WaypointTimeout = 20,
    CampRetryDelay = 3,
    IgnoreTroopsInPathfinding = true,

    CampEnterTimeout = 3,

    -- Supply / troop

    MenuTimeout = 5,

    CheckInterval = 0.6,

    -- Re-verify the real player position against the selected
    -- camp every 25 seconds. If outside, walk back.
    CampCheckInterval = 25,

    -- Keep the currently spawned troop in Attack state.
    AttackInterval = 5,

    -- Failsafe only; native Cancel/progress always keeps a request pending.
    SpawnPendingTimeout = 30,

}

--==================================================

-- RUNTIME STATE

--==================================================

local function copySettings(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copySettings(item) end
    return result
end
local DEFAULT_CONFIG = copySettings(CONFIG)

local STATE = {

    enabled = false,
    ready = false,
    initReason = "Đang tải thành phần game...",
    initWorker = nil,
    phase = "WAITING",
    location = nil,
    lobbyPlayRequested = false,
    lobbyCycleActive = false,
    joinRequest = nil,
    roundFinished = false,
    finishedMap = nil,
    lobbyVoteName = nil,
    lobbyVoteChoice = nil,
    runId = 0,
    worker = nil,
    continueWorker = nil,
    continueVisible = false,
    continueRelease = nil,
    roundTeam = nil,
    movementConnections = {},
    connections = {},
    troopPathConnections = {},
    troopPathModifiers = {},

    lastSlot = nil,
    troopMap = nil,
    activeSlot = nil,
    zeroSince = nil,

    pendingSlot = nil,

    pendingUntil = 0,

    currentCamp = nil,

    -- True only after a living troop is confirmed by the UI.
    troopActive = false,
    lastAttackAt = 0,

}

--==================================================

-- PLAYER

--==================================================

local function getCurrentTeam()

    local team = player.Team

    return team and team.Name or nil

end



--==================================================

