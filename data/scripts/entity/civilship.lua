package.path = package.path .. ";data/scripts/lib/?.lua"

local raidingFixes_config
local raidingFixes_threatenStates = {}
local raidingFixes_insist, raidingFixes_threaten -- extended functions

if onServer() then


local Azimuth = include("azimuthlib-basic")

local configOptions = {
  _version = { default = "1.0", comment = "Config version. Don't touch." },
  RaidingPenalty = { default = 15000, min = 0, max = 100000, format = "floor", comment = "During raiding you lose relations. This option allows to adjust how much you lose." },
  MinRelationsToVictim = { default = -70000, min = -100000, max = 100000, format = "floor", comment = "If witness relation to victim is lower than this threshold, they will not hate you for raiding the civil ship." }
}
local isModified
raidingFixes_config, isModified = Azimuth.loadConfig("RaidingFixes", configOptions)
if isModified then
    Azimuth.saveConfig("RaidingFixes", raidingFixes_config, configOptions)
end
configOptions = nil


raidingFixes_insist = CivilShip.insist
function CivilShip.insist(...)
    threatenState = raidingFixes_threatenStates[callingPlayer]
    raidingFixes_insist(...)
    raidingFixes_threatenStates[callingPlayer] = threatenState
end

raidingFixes_threaten = CivilShip.threaten
function CivilShip.threaten(...)
    threatenState = raidingFixes_threatenStates[callingPlayer]
    raidingFixes_threaten(...)
    raidingFixes_threatenStates[callingPlayer] = threatenState
end

function CivilShip.worsenRelations(delta) -- overridden
    delta = delta or -raidingFixes_config.RaidingPenalty
    if delta > 0 then return end
    if not callingPlayer then return end

    local crafts = {Sector():getEntitiesByComponent(ComponentType.Crew)}

    local factions = {}
    for _, entity in pairs(crafts) do
        -- only change relations to ai factions
        if entity.aiOwned then
            factions[entity.factionIndex] = 1
        end
    end

    local shipFaction = getInteractingFaction(callingPlayer)
    local thisFaction = Entity().factionIndex
    local faction, relationsToVictim
    local galaxy = Galaxy()
    for factionIndex, _ in pairs(factions) do
        faction = Faction(factionIndex)
        if faction then
            relationsToVictim = faction:getRelations(thisFaction)
            if relationsToVictim >= raidingFixes_config.MinRelationsToVictim then
                galaxy:changeFactionRelations(faction, shipFaction, delta)
            end
        end
    end
end


end