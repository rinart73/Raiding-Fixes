package.path = package.path .. ";data/scripts/lib/?.lua"

local Azimuth, RaidingTweaksConfig

if onServer() then


Azimuth = include("azimuthlib-basic")

local configOptions = {
  _version = { default = "1.0", comment = "Config version. Don't touch." },
  RaidingPenalty = { default = 15000, min = 0, max = 100000, format = "floor", comment = "During raiding you lose relations. This option allows to adjust how much you lose." },
  MinRelationsToVictim = { default = -70000, min = -100000, max = 100000, format = "floor", comment = "If witness relation to victim is lower than this threshold, they will not hate you for raiding the civil ship." },
  HazardZoneScoreIncrease = { default = 15, min = 0, max = 100, format = "floor", comment = "Sector hazard zone score will increase by this value, potentially turning sector into a hazard zone." }
}
local isModified
RaidingTweaksConfig, isModified = Azimuth.loadConfig("RaidingFixes", configOptions)
if isModified then
    Azimuth.saveConfig("RaidingFixes", RaidingTweaksConfig, configOptions)
end
configOptions = nil

function CivilShip.worsenRelations(delta) -- overridden
    delta = delta or -RaidingTweaksConfig.RaidingPenalty
    if delta > 0 then return end
    if not callingPlayer then return end

    local sector = Sector()
    local crafts = {sector:getEntitiesByComponent(ComponentType.Crew)}
    local factions = {}
    for _, entity in pairs(crafts) do
        -- only change relations to ai factions
        if entity.aiOwned then
            factions[entity.factionIndex] = 1
        end
    end
    local shipFaction = getInteractingFaction(callingPlayer)
    local thisFaction = Entity().factionIndex
    for factionIndex, _ in pairs(factions) do
        local faction = Faction(factionIndex)
        if faction and faction:getRelations(thisFaction) >= RaidingTweaksConfig.MinRelationsToVictim then
            changeRelations(faction, shipFaction, delta, RelationChangeType.Raiding, true, true)
        end
    end
    sector:invokeFunction("warzonecheck.lua", "increaseScore", RaidingTweaksConfig.HazardZoneScoreIncrease)
end


end