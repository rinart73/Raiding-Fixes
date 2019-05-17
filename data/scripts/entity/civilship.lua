package.path = package.path .. ";data/scripts/lib/?.lua"

local config, Log, isModified

if onServer() then
    local Azimuth = include("azimuthlib-basic")
    if not Azimuth then return end -- can't work without it

    local configOptions = {
      _version = { default = "1.0", comment = "Config version. Don't touch." },
      LogLevel = { default = 2, min = 0, max = 4, format = "floor", comment = "0 - Disable, 1 - Errors, 2 - Warnings, 3 - Info, 4 - Debug." },
      RaidingPenalty = { default = 15000, min = 0, max = 100000, format = "floor", comment = "During successful raiding you lose relations 3 times. This option allows to adjust how much you lose." }
    }
    config, isModified = Azimuth.loadConfig("RaidingFixes", configOptions)
    if isModified then
        Azimuth.saveConfig("RaidingFixes", config, configOptions)
    end

    Log = Azimuth.logs("RaidingFixes", config.LogLevel)
end


local dialogStates = {} -- current dialog state for each faction
local dialogState = 0 -- for clientside

local Dialogs = { Ridiculous = 1, Flee = 2, Giveup = 3, Giveup_Threaten = 4, Attack = 5, Attack_Threaten = 6 }
local dumpCargo = {
  onStart = "Giveup_dumpCargo",
  text = "Dumping the cargo. I hope you're happy you damn pirate."%_t
}
local dialogs = {
  -- Ridiculous
  {
    text = "Hahahahaha!"%_t,
    answers = {
      {answer = "I'm serious!"%_t, followUp = {
        text = "And how are you planning on doing that?"%_t,
        answers = {
          {answer = "I'm going to destroy you!"%_t, text = "This is ridiculous. Go away."%_t},
          {answer = "Leave"%_t }
        }
      }},
      {answer = "Okay, sorry, wrong ship."%_t},
    }
  },
  -- Flee
  {
    text = "We'll be out of here before you even get to us!"%_t
  },
  -- Giveup
  {
    text = "..."%_t,
    followUp = {
      text = "Leave us alone!"%_t,
      answers = {
        {answer = "Dump your cargo or you'll be destroyed!"%_t, followUp = {
          onStart = "onGiveup_Threaten",
          text = "Please don't shoot! We will dump the cargo, but then you leave us alone!"%_t,
        }},
        {answer = "Okay, sorry, wrong ship."%_t},
      }
    }
  },
  -- Giveup_Threaten
  {
    text = "Please don't shoot! We will dump the cargo, but then you leave us alone!"%_t,
    answers = {
      {answer = "Dump your cargo and you will be spared."%_t, followUp = dumpCargo},
      {answer = "If you cooperate, I might spare your lives."%_t, followUp = dumpCargo},
      {answer = "I'm going to destroy you!"%_t, followUp = dumpCargo},
      {answer = "At second thought I don't need anything of you."%_t, text = "What kind of sick joke is this!?"%_t }
    }
  },
  -- Attack
  {
    text = "..."%_t,
    followUp = {
      text = "You should leave."%_t,
      answers = {
        {answer = "Dump your cargo or you'll be destroyed!"%_t, followUp = {
          onStart = "Attack_Threaten",
          text = "I will not give up my cargo freely to some petty pirate!"%_t
        }},
        {answer = "Okay, sorry, wrong ship."%_t},
      }
    }
  },
  -- Attack_Threaten
  {
    text = "I will not give up my cargo freely to some petty pirate!"%_t,
    answers = {
      {answer = "So be it then!"%_t, onSelect = "attackPlayer"},
      {answer = "I'm going to destroy you!"%_t, onSelect = "attackPlayer"},
      {answer = "Oops, sorry, wrong ship, carry on!"%_t},
    }
  },
}

local function invalidPlayerCraft()
    local player = Player(callingPlayer)
    if not player.craftIndex or not valid(player.craftIndex) then
        Log.Error("Player '%i' - invalid craft", player.index)
        dialogStates[callingPlayer] = -1
        invokeClientFunction(player, "receiveDialog", -1)
        return true
    end
end

local function invalidDialogState(dialogState, correctValue)
    local player = Player(callingPlayer)
    if dialogState ~= correctValue then
        Log.Warn("Player %i (%s) tried to chose suspiciously incorrect dialog option, state: %i, correct: %i", player.index, player.name, dialogState, correctValue)
        dialogStates[callingPlayer] = -1
        invokeClientFunction(player, "receiveDialog", -1)
        return true
    end
end

function CivilShip.initialize()
    if onClient() then
        local entity = Entity()
        InteractionText(entity.index).text = Dialog.generateShipInteractionText(entity, random())
        -- request current dialog
        invokeServerFunction("sendDialog")
    else -- onServer
        -- 50% chance that a civil ship will just run
        willFlee = math.random() > 0.5

        -- player/alliance ships should never run, since run == delete
        local faction = Faction()
        if faction and (faction.isPlayer or faction.isAlliance) then
            willFlee = false
        end
    end
end

function CivilShip.interactionPossible(playerIndex, option)
    if option == 1 then
        local ship = Entity()

        local cargos = ship:getCargos()

        if tablelength(cargos) == 0 or dialogState == -1 then
            return false
        end
    end

    return true
end

function CivilShip.onRaid()
    if onClient() then
        if dialogState == 0 then -- start fresh dialog
            ScriptUI():interactShowDialog({ text = "..."%_t }, false) -- and wait for server response
            invokeServerFunction("onRaid")
        else
            ScriptUI():interactShowDialog(dialogs[dialogState], false) -- resume a dialog
        end
        return
    end

    -- evaluate strength of own ship vs strength of player
    if invalidPlayerCraft() then return end

    local me = Entity()
    local player = Player(callingPlayer)
    local playerCraft = Entity(player.craftIndex)
    -- Don't allow to reset a dialog
    local dialogState = dialogStates[callingPlayer] or 0
    if invalidDialogState(dialogState, 0) then return end
    
    local myDps = me.firePower
    local playerDps = playerCraft.firePower

    local meDestroyed = me.durability / playerDps
    local playerDestroyed = playerCraft.durability / myDps

    local dialog

    if myDps == 0 and meDestroyed / 60 > 2 then
        -- player can't do anything
        dialog = Dialogs.Ridiculous
    elseif meDestroyed * 2.0 < playerDestroyed then
        -- "okay I'm dead"
        if willFlee == true then
            dialog = Dialogs.Flee
            deferredCallback(4, "flee")
        else
            dialog = Dialogs.Giveup
        end
    elseif meDestroyed < playerDestroyed then
        -- "I might be in trouble"
        if willFlee == true then
            dialog = Dialogs.Flee
            deferredCallback(4, "flee")
        else
            if math.random() > 0.5 then
                dialog = Dialogs.Giveup
            else
                dialog = Dialogs.Attack
            end
        end
    elseif meDestroyed * 0.5 > playerDestroyed then
        -- "I will take you on!" / "I might get out of this"
        dialog = Dialogs.Attack
    end

    dialogStates[callingPlayer] = dialog
    Log.Debug("onRaid - player %i, new dialog state %i", player.index, dialog)

    callingPlayer = nil
    CivilShip.worsenRelations(nil, playerCraft.factionIndex)

    invokeClientFunction(player, "receiveDialog", dialog)
end
callable(CivilShip, "onRaid")

function CivilShip.onGiveup_Threaten()
    if onClient() then
        invokeServerFunction("onGiveup_Threaten")
        return
    end

    if invalidPlayerCraft() then return end

    local player = Player(callingPlayer)
    local playerCraft = Entity(player.craftIndex)
    local dialogState = dialogStates[callingPlayer] or 0
    if invalidDialogState(dialogState, Dialogs.Giveup) then return end

    local dialog = Dialogs.Giveup_Threaten
    dialogStates[callingPlayer] = dialog
    
    callingPlayer = nil
    CivilShip.worsenRelations(nil, playerCraft.factionIndex)
    
    Log.Debug("onGiveup_Threaten - player %i, new dialog state %i", player.index, dialog)
    invokeClientFunction(player, "receiveDialog", dialog)
end
callable(CivilShip, "onGiveup_Threaten")

function CivilShip.Giveup_dumpCargo()
    if onClient() then
        invokeServerFunction("Giveup_dumpCargo")
        return
    end

    if invalidPlayerCraft() then return end

    local player = Player(callingPlayer)
    local playerCraft = Entity(player.craftIndex)
    local dialogState = dialogStates[callingPlayer] or 0
    if invalidDialogState(dialogState, Dialogs.Giveup_Threaten) then return end

    local dialog = -1 -- the end
    dialogStates[callingPlayer] = dialog
    Log.Debug("Giveup_dumpCargo - player %i, new dialog state %i", player.index, dialog)
    
    callingPlayer = nil
    CivilShip.worsenRelations(nil, playerCraft.factionIndex)

    invokeClientFunction(player, "receiveDialog", dialog)

    -- drop cargo
    local ship = Entity()

    local sector = Sector()
    for good, amount in pairs(ship:getCargos()) do
        good.stolen = true

        for i = 1, amount, 2 do
            sector:dropCargo(ship.translationf, player, Faction(ship.factionIndex), good, ship.factionIndex, 2)
        end

        ship:removeCargo(good, amount)
    end
end
callable(CivilShip, "Giveup_dumpCargo")

function CivilShip.Attack_Threaten()
    if onClient() then
        invokeServerFunction("Attack_Threaten")
        return
    end

    if invalidPlayerCraft() then return end

    local player = Player(callingPlayer)
    local playerCraft = Entity(player.craftIndex)
    local dialogState = dialogStates[callingPlayer] or 0
    if invalidDialogState(dialogState, Dialogs.Attack) then return end

    local dialog = Dialogs.Attack_Threaten
    dialogStates[callingPlayer] = dialog
    Log.Debug("Attack_Threaten - player %i, new dialog state %i", player.index, dialog)

    callingPlayer = nil
    CivilShip.worsenRelations(nil, playerCraft.factionIndex)

    invokeClientFunction(player, "receiveDialog", dialog)
end
callable(CivilShip, "Attack_Threaten")

function CivilShip.sendDialog()
    local dialog = dialogStates[callingPlayer] or 0

    invokeClientFunction(Player(callingPlayer), "receiveDialog", dialog, true)
end
callable(CivilShip, "sendDialog")

function CivilShip.receiveDialog(dialog, inBackground)
    if onServer() then return end

    dialogState = dialog
    if dialog > -1 and not inBackground then
        ScriptUI():interactShowDialog(dialogs[dialog], false)
    end
end

function CivilShip.flee()
    if callingPlayer then return end

    willFlee = false

    -- don't delete player ships
    local faction = Faction()
    if faction and (faction.isPlayer or faction.isAlliance) then
        return
    end

    Sector():deleteEntityJumped(Entity())
end

function CivilShip.attackPlayer()
    if onClient() then
        invokeServerFunction("attackPlayer")
        return
    end

    local player = Player(callingPlayer)

    local dialog = -1 -- the end
    dialogStates[callingPlayer] = dialog
    Log.Debug("attackPlayer - player %i, new dialog state %i", player.index, dialog)

    invokeClientFunction(player, "receiveDialog", dialog, true)

    local ai = ShipAI()
    ai:setPassiveShooting(1)
    ai:registerEnemyEntity(player.craftIndex)
end
callable(CivilShip, "attackPlayer")

function CivilShip.dumpCargo()
    -- just overwrite it empty so people will not exploit it
end

function CivilShip.worsenRelations(delta, factionIndex)
    if callingPlayer then return end
    local playerFaction = Faction(factionIndex)
    if not playerFaction then
        Log.Error("worsenRelations - faction '%s' doesn't exist", tostring(factionIndex))
        return
    end

    local crafts = {Sector():getEntitiesByComponent(ComponentType.Crew)}

    local factions = {}
    for _, entity in pairs(crafts) do
        -- only change relations to ai factions
        if entity.aiOwned then
            factions[entity.factionIndex] = 1
        end
    end

    local thisFaction = Entity().factionIndex
    local faction, relationsToVictim
    local galaxy = Galaxy()
    for factionIndex, _ in pairs(factions) do
        faction = Faction(factionIndex)
        
        if faction then
            -- if delta is not set, use config value
            if not delta then
                delta = -config.RaidingPenalty
            end

            relationsToVictim = faction:getRelations(thisFaction)
            
            if relationsToVictim >= -70000 then
                galaxy:changeFactionRelations(faction, playerFaction, delta)
            end
        end
    end
end

function CivilShip.secure()
    return {
      dialogStates = dialogStates
    }
end

function CivilShip.restore(values)
    if not values then values = {} end
    dialogStates = values.dialogStates or {}
end