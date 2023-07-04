ReaperData = {}
ReaperBlacklist = {}
SeenPlayers = {}
ReaperLevelRecords = {}

local CTL = _G.ChatThrottleLib
local timer_running = false
local hc_version = { 0, 11, 42 }
local reaper_prefix = "|cffFF9933Reaper:|r"
local GREEN = "|cff00ff33"
local RED = "|cffff3300"
local ORANGE = "|cffffa500"
local outdated_warning = false
local requested_character = nil
local CHEER_ALLIANCE = 568821
local CHEER_HORDE = 569085
local last_level = nil

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

local function IsQuestLineCompletable(quest_id)
    if CraftingQuests[quest_id] == nil then return true end

---@diagnostic disable-next-line: undefined-global
    for skillIndex = 1, GetNumSkillLines() do
---@diagnostic disable-next-line: undefined-global
        local skillName, isHeader = GetSkillLineInfo(skillIndex)
        if not isHeader then
            if skillName == CraftingQuests[quest_id] then return true end
        end
    end

    return false
end

local function GetRequiredProfession(quest_id)
    if CraftingQuests[quest_id] ~=nil then
        return CraftingQuests[quest_id]
    end

    return nil
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

function GetAddonVersionFromPulse(pulse)
    local version = string.sub(pulse, 7)
    local t = {}

    for i in string.gmatch(version, "%d+") do
        table.insert(t, tonumber(i))
    end

    local major = t[1]
    local minor = t[2]
    local build = t[3]

    return major, minor, build
end

function CompareAddonVersion(pulse, isOutdated)
    local major, minor, build = GetAddonVersionFromPulse(pulse)

    if major == nil or minor == nil or build == nil then return end

    if isOutdated then
        if major < hc_version[1] then return true end
        if minor < hc_version[2] then return true end
        if minor == hc_version[2] and build < hc_version[3] then return true end
    else
        if major > hc_version[1] then return true end
        if minor > hc_version[2] then return true end
        if minor == hc_version[2] and build > hc_version[3] then return true end
    end
    return false
end

local function handleEvent(self, event, ...)
    local arg = { ... }

    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(5, function ()
            JoinDeathLogChannel()
        end)
    end

    if event == "PLAYER_LEVEL_UP" then

        last_level = arg[1]
        C_Timer.After(2, function ()
            local class_name, _, class_id = UnitClass("player")

            if ReaperLevelRecords[class_id] ~= nil then
                if ReaperLevelRecords[class_id] < last_level then
                    print(reaper_prefix .. string.format(" You've achieved a new personal record: level %d on a %s!", last_level, class_name))
                    ReaperLevelRecords[class_id] = last_level
                    local faction = UnitFactionGroup("player")
                    if faction == "Alliance" then
                        PlaySoundFile(CHEER_ALLIANCE)
                    else
                        PlaySoundFile(CHEER_HORDE)
                    end
                end
            else
                print(reaper_prefix .. string.format(" You've achieved a new personal record: level %d on a %s!", last_level, class_name))
                ReaperLevelRecords[class_id] = last_level
                local faction = UnitFactionGroup("player")
                if faction == "Alliance" then
                    PlaySoundFile(CHEER_ALLIANCE)
                else
                    PlaySoundFile(CHEER_HORDE)
                end
            end
        end)

    end

    if event == "CHAT_MSG_ADDON" then
        local payload = arg[2]
        local player = arg[4]

        local cmd, _ = strsplit("$", payload)

        if cmd == "PULSE" then
            if SeenPlayers[player] == nil then
                SeenPlayers[player] = payload
            end

            -- update players who have updated their addon
            if SeenPlayers[player] ~= nil and SeenPlayers[player] ~= payload then
                SeenPlayers[player] = payload
            end

            if(CompareAddonVersion(payload, false)) and not outdated_warning then
                outdated_warning = true
                print(reaper_prefix .. string.format(" Your Hardcore addon is outdated! Player %s is using version %s; please update at your nearest convenience.", player, string.sub(payload, 7)))
            end
        elseif cmd == "CHARACTER_INFO" then
            if player ~= requested_character then return end
            requested_character = nil
            local version_str, creation_time, achievements_str, _, party_mode_str, _, _, team_str, hc_tag, passive_achievements_str, verif_status, verif_details = strsplit("|", payload)
            print(string.format(reaper_prefix .. " Hardcore Information for %s", player))
            local verify = "Passed"
            local col = GREEN
            if verif_status == "FAIL" then
                verify = "Failed: " .. verif_details
                col = RED
            elseif verif_status == "PENDING" then
                verify = "Pending appeal: " .. verif_details
                col = ORANGE
            elseif verif_status == nil then
                verify = "Unknown (unsupported version)"
                col = RED
            end
            print(string.format("Verification: %s%s|r", col, verify))
            print(string.format("Creation date: %s", date("%Y-%m-%d %H:%M:%S", creation_time)))
            print(string.format("Hardcore tag: %s", hc_tag))
            print(string.format("Group mode: %s", party_mode_str))
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

    if event == "QUEST_ACCEPTED" then
        local index = arg[1]
        local quest_id = arg[2]
        if IsQuestLineCompletable(quest_id) then return end
---@diagnostic disable-next-line: undefined-global
        local title = GetQuestLogTitle(index)
        local required_profession = GetRequiredProfession(quest_id)
        if required_profession ~=nil then
            print(reaper_prefix .. string.format(" Heads up! The quest line starting with \"%s\" requires items made using the %s profession and can't be completed by you.", title, required_profession))
        end
    end

    if event == "CHAT_MSG_CHANNEL" then
        local _, channel_name = strsplit(" ", arg[4])
        if channel_name ~= "hcdeathalertschannel" then return end
        local command, msg = strsplit("$", arg[1])

        if command == "1" then
            local player_name_short, _ = strsplit("-", arg[2])
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
ReaperForm:RegisterEvent("QUEST_ACCEPTED")
ReaperForm:RegisterEvent("PLAYER_LEVEL_UP")

if not C_ChatInfo.IsAddonMessagePrefixRegistered("HardcoreAddon") then
    C_ChatInfo.RegisterAddonMessagePrefix("HardcoreAddon")
end

ReaperForm:SetScript("OnEvent", handleEvent)

SLASH_REAPER1 = "/reaper"

local function ReaperCommandHandler(msg)
    msg = string.lower(msg)
    if msg == "audit" then
        print(reaper_prefix .. " Player audit")
        local total, _, _ = GetNumGuildMembers()
        for i = 1, total do
            local name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, isOnline, status, class, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid = GetGuildRosterInfo(i)
            if isOnline then
                if SeenPlayers[name] == nil then
                    print(string.format("%s: %sNo addon detected|r", name, RED))
                else
                    local pulse = SeenPlayers[name]
                    local col = RED
                    if not CompareAddonVersion(pulse, true) then
                        col = GREEN
                    end
                    local major, minor, build = GetAddonVersionFromPulse(pulse)
                    print(string.format("%s: %s%d.%d.%d|r", name, col, major, minor, build))
                end
            end
        end
    end
    if msg == "inspect" then
        if not UnitIsPlayer("target") then
            print(reaper_prefix .. " You need to select a player target.")
            return
        end
        local name, realm = UnitName("target")
        if realm == nil then realm = GetNormalizedRealmName() end
        local target = name .. "-" .. realm
        requested_character = target
        CTL:SendAddonMessage("ALERT", "HardcoreAddon", "REQUEST_CHARACTER_INFO$", "WHISPER", target)

        -- if the target player's addon didn't respond after 2 seconds either the player doesn't have the Hardcore addon running
        -- so we'll reset the requested_character variable to enable inspection again
        C_Timer.After(2, function ()
            local target = requested_character
            if requested_character ~= nil then
                print(reaper_prefix .. " " .. target .. " does not seem to have the Hardcore addon active.")
                requested_character = nil
            end
        end)
    end
end

local function SlashCmdHandler(msg)
    ReaperCommandHandler(msg)
end

SlashCmdList["REAPER"] = SlashCmdHandler
