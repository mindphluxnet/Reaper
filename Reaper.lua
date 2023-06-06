ReaperData = {}
ReaperBlacklist = {}
SeenPlayers = {}

local timer_running = false
local hc_version = "0.11.31"
local reaper_prefix = "|cffFF9933Reaper:|r"
local GREEN = "|cff00ff33"
local RED = "|cffff3300"

local CLASSES = {
    -- Classic:
    [1] = "Warrior",
    [2] = "Paladin",
    [3] = "Hunter",
    [4] = "Rogue",
    [5] = "Priest",
    [6] = "Death Knight", -- new Death Knight ID
    [7] = "Shaman",
    [8] = "Mage",
    [9] = "Warlock",
    [11] = "Druid",
}

local environment_damage = {
    [-2] = "Drowning",
    [-3] = "Falling",
    [-4] = "Fatigue",
    [-5] = "Fire",
    [-6] = "Lava",
    [-7] = "Slime",
}

local function PlayerData(name, guild, source_id, race_id, class_id, level, instance_id, map_id, map_pos, date,
                          last_words)
    return {
        ["name"] = name,
        ["guild"] = guild,
        ["source_id"] = source_id,
        ["race_id"] = race_id,
        ["class_id"] = class_id,
        ["level"] = level,
        ["instance_id"] = instance_id,
        ["map_id"] = map_id,
        ["map_pos"] = map_pos,
        ["date"] = date,
        ["last_words"] = last_words,
    }
end

local function ReloadTimer(minutes)
    -- warns the player after $minutes have passed so they don't forget to save their progress
    -- first call sets the minutes to 30, repeat warnings are issued with a much shorter frequency
    if timer_running then return end
    timer_running = true
    C_Timer.After(minutes * 60, function ()
        timer_running = false
        PlaySoundFile(568587)
        print(reaper_prefix .. "Time to save your progress! Please use /reload when it is safe to do so.")
        ReloadTimer(5)
    end)
end

local function decodeMessage(msg)
    local values = {}
    for w in msg:gmatch("(.-)~") do table.insert(values, w) end
    if #values < 9 then
        -- Return something that causes the calling function to return on the isValidEntry check
        --print("Malformed deathlog message with " .. #values .. " data values")
        local malformed_player_data = PlayerData("MalformedData", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil)
        return malformed_player_data
    end
    local date = time()
    local last_words = nil
    local name = values[1]
    local guild = values[2]
    local source_id = tonumber(values[3])
    local race_id = tonumber(values[4])
    local class_id = tonumber(values[5])
    local level = tonumber(values[6])
    local instance_id = tonumber(values[7])
    local map_id = tonumber(values[8])
    local map_pos = values[9]
    local player_data = PlayerData(name, guild, source_id, race_id, class_id, level, instance_id, map_id, map_pos, date,
        last_words)
    return player_data
end

function JoinDeathLogChannel()
    JoinChannelByName("hcdeathalertschannel", "hcdeathalertschannelpw", nil, false)
---@diagnostic disable-next-line: redundant-parameter
    local channel_num, _, _, _ = GetChannelName("hcdeathalertschannel")
    if channel_num == 0 then
        print(reaper_prefix .. " Failed to join DeathLog channel")
    else
        print(reaper_prefix .. " Successfully joined Deathlog channel")
    end
end

function InTable(table, value)
    for i = 1, #table do
        if table[i]["name"] == value["name"]
            and table[i]["class_id"] == value["class_id"]
            and table[i]["race_id"] == value["race_id"]
            and table[i]["level"] == value["level"]
            and table[i]["source_id"] == value["source_id"]
            and table[i]["map_id"] == value["map_id"]
        then
            return true
        end
    end
    return false
end

function AddToBlacklist(player)
    ReaperBlacklist.insert(player)
    print(reaper_prefix .. string.format(" Added player %s to blacklist for dying more than once.", player))
end

function IsRepeatDeath(data)
    -- since there is no unique identifier to a player we need to make do with the little information we have
    -- this of course doesn't really work well with players who always remake the exact same character
    -- so checking the time since the last death might help
    for i = 1, #ReaperData do
        if ReaperData[i]["name"] == data["name"]
        and ReaperData[i]["level"] >= data["level"]
        and ReaperData[i]["race_id"] == data["race_id"]
        and ReaperData[i]["class_id"] == data["class_id"]
        -- if the death is less than 8 + 1.5 hours per level > 10 ago treat this as a repeat death
        and ReaperData[i]["date"] ~=nil and ReaperData[i]["date"] < time.time() - (60 * 60 * (8 + 1.5 * (math.max(10, ReaperData[i]["level"]) - 10)))
        then
            return true
        end
    end
    return false
end

function IsBlacklisted(name)
    for i= 1, #ReaperBlacklist do
        if ReaperBlacklist[i] == name then return true end
    end
    return false
end

local function handleEvent(self, event, ...)
    local arg = { ... }
    if event == "PLAYER_ENTERING_WORLD" then
        ReloadTimer(30)
        C_Timer.After(5, function ()
            JoinDeathLogChannel()
        end)
    end

    if event == "CHAT_MSG_ADDON" then
        local pulse = arg[2]
        local player = arg[4]

        if SeenPlayers[player] == nil then
            SeenPlayers[player] = pulse
        end

        if SeenPlayers[player] ~= nil and SeenPlayers[player] ~= pulse then
            SeenPlayers[player] = pulse
        end
    end

    if event == "PLAYER_QUITING" then
        PlaySoundFile(568165)
        print(reaper_prefix .. " Warning! Using Exit instead of Logout causes Hardcore addon data loss, please click Cancel NOW!")
    end

    if event == "GUILD_ROSTER_UPDATE" then
        local total, _, _ = GetNumGuildMembers()
        for i = 1, total do
            local name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, isOnline, status, class, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid = GetGuildRosterInfo(i)
            if not isOnline and SeenPlayers[name] ~= nil then
                SeenPlayers[name] = nil
            end
        end

    end

    if event == "CHAT_MSG_CHANNEL" then
        local _, channel_name = string.split(" ", arg[4])
        if channel_name ~= "hcdeathalertschannel" then return end
        local command, msg = string.split("$", arg[1])

        if command == "1" then
            local player_name_short, _ = string.split("-", arg[2])
            if msg == nil then return end
            local decoded_data = decodeMessage(msg)
            if player_name_short ~= decoded_data["name"] then return end

            if IsBlacklisted(decoded_data["name"]) then return end
            if IsRepeatDeath(decoded_data) then AddToBlacklist(decoded_data["name"]) return end

            local out = string.format(reaper_prefix .. " %s", decoded_data["name"])
            if decoded_data["guild"] and decoded_data["guild"] ~= "" then
                out = out .. string.format(" <%s>", decoded_data["guild"])
            end
            local source = id_to_npc[decoded_data["source_id"]]
            local killer = nil
            if source then
                killer = source
            elseif environment_damage[source] then
                killer = environment_damage[source]
            end
            if not killer then killer = "unknown" end
            local race_info = C_CreatureInfo.GetRaceInfo(decoded_data["race_id"])
            local race = "unknown"
            if race_info then
                race = race_info.raceName
            end
            out = out .. string.format(", level %d %s %s died to %s", decoded_data["level"], race, CLASSES[decoded_data["class_id"]], killer)
            if decoded_data["map_id"] then
                local map_info = C_Map.GetMapInfo(decoded_data["map_id"])
                if map_info then out = out .. string.format(" in %s", map_info.name) end
                if decoded_data["map_pos"] then out = out .. string.format(" (%s)", decoded_data["map_pos"]) end
            end

            if not InTable(ReaperData, decoded_data) then
                table.insert(ReaperData, decoded_data)
                PlaySoundFile(568992)
                print(out)
            end
        end
    end
end

local ReaperForm = CreateFrame("Frame", "reaperframe", nil, "BackdropTemplate")
ReaperForm:RegisterEvent("CHAT_MSG_CHANNEL")
ReaperForm:RegisterEvent("PLAYER_ENTERING_WORLD")
ReaperForm:RegisterEvent("PLAYER_LOGIN")
ReaperForm:RegisterEvent("CHAT_MSG_ADDON")
ReaperForm:RegisterEvent("PLAYER_QUITING")
ReaperForm:RegisterEvent("GUILD_ROSTER_UPDATE")

if not C_ChatInfo.IsAddonMessagePrefixRegistered("HardcoreAddon") then
    C_ChatInfo.RegisterAddonMessagePrefix("HardcoreAddon")
end

ReaperForm:SetScript("OnEvent", handleEvent)

SLASH_REAPER1 = "/reaper"

local function ReaperCommandHandler(msg)
    msg = string.lower(msg)
    if msg == "audit" then
        print(reaper_prefix .. " Player audit")
        for key, value in pairs(SeenPlayers) do
            local version = string.sub(value, 7)
            local col = RED
            if version == hc_version then
                col = GREEN
            end
            print(string.format("%s: %s%s|r", key, col, version))
        end

    end
    if msg == "recent" then

    end
end

local function SlashCmdHandler(msg)
    ReaperCommandHandler(msg)
end

SlashCmdList["REAPER"] = SlashCmdHandler
