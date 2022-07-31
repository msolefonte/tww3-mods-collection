local cbac = require("script/cbac/lib/cbac");

function shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = cm:random_number(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
end

local function enforce_limit_on_ai_army(character)

  local unit_list = character:military_force():unit_list()
  local faction_string = character:faction():name()
  local culture = character:faction():culture()
  local current_unit_object = nil
  local current_unit_key = ""
  local replacement_unit_key = ""
  local possible_indices = {}
  local char_cqi = character:command_queue_index()
  local army_is_under_limit = false
  local random_number_replacement = 0
  --how much unit cost we have to reduce this army by to get under the limit?
  local effective_army_limit = cbac:get_config("army_limit_ai")
  if (cbac:get_config("dynamic_limit")) then
    local lord_rank = character:rank()
    local limit_rank = cbac:get_config("limit_rank")
    local limit_step = cbac:get_config("limit_step")
    local limit_deceleration = cbac:get_config("limit_deceleration")

    local total_deceleration_factor = 0
    local number_of_steps = (math.floor(lord_rank/limit_rank)) - 1
    local step = 1
    while step <= number_of_steps do
      if (limit_deceleration*step <= limit_step) then
        total_deceleration_factor = total_deceleration_factor + (limit_deceleration*step)
      else
        total_deceleration_factor = total_deceleration_factor + limit_step
      end
      step = step + 1
    end
    effective_army_limit = effective_army_limit + ((math.floor(lord_rank/limit_rank))*limit_step) - total_deceleration_factor
  end
  local cost_savings_required = get_army_cost(character) - effective_army_limit
  local units_to_remove = {}
  local units_to_add = {}
  --how much gold should AI get back because we took their elite units and gave them crappy ones?
  local reimbursement_amount = 0
  --create a table with the indices of the units in the army so we can shuffle them
  cbac:log("Army needs to save: "..cost_savings_required)
  cbac:log("Army unit list before changes:")
  for i=0, unit_list:num_items()-1 do
    table.insert(possible_indices, i)
    cbac:log("["..i.."]: ["..unit_list:item_at(i):unit_key().."]")
  end

  --shuffle the list of indices so we don't always change units in the same slots first
  possible_indices = shuffle(possible_indices)

  for j=1, (#possible_indices) do
    --index table is now shuffled, do replace for every item until cost no longer over limit
    --get the unit we want to examine
    current_unit_object = unit_list:item_at(possible_indices[j])
    current_unit_key = current_unit_object:unit_key()

    --only proceed if this unit has possible replacements
    if cbac_ai_replaceable_units[current_unit_key] then
      --add unit key to table of units to remove later
      table.insert(units_to_remove, current_unit_key)
      cbac:log("[PENDING REMOVAL]: Unit of type ["..current_unit_key.."] from army slot #"..possible_indices[j]..".")
      --find the replacement unit and add its name to table for later addition to army
      random_number_replacement = cm:random_number(2)
      replacement_unit_key = cbac_ai_replaceable_units[current_unit_key][random_number_replacement]
      table.insert(units_to_add, replacement_unit_key)
      cbac:log("[PENDING ADDITION]: Unit of type ["..replacement_unit_key.."] to army of character with cqi: "..char_cqi..".")
      --how much did that save us?
      for k=1, #cbac_units_cost do
        if cbac_units_cost[k][1] == replacement_unit_key then
          reimbursement_amount = reimbursement_amount + (current_unit_object:get_unit_custom_battle_cost() - cbac_units_cost[k][2])
          cost_savings_required = cost_savings_required - (current_unit_object:get_unit_custom_battle_cost() - cbac_units_cost[k][2])
          break
        end
      end
      --did we mark enough units for exchange to get under cost limit?
      if cost_savings_required <= 0 then
        cbac:log("This army is now under the cost limit, moving on.")
        army_is_under_limit = true
        break
      end
      --currently examined unit has no replacement
    else
      cbac:log("[IGNORED UNIT] Current unit with key: ["..current_unit_key.."] has no defined replacement, will be left unchanged.")
    end
  end

  --we have looped over units in army until cost savings were large enough to now be under the limit, or we looped over every unit and marked it for downgrade if suitable, now apply changes
  if not army_is_under_limit then
    cbac:log("Looped through all units in army once, but it is still over limit. We will apply unit changes now and then nerf it again next turn!")
  end
  --reimbursement
  if faction_string ~= "rebels" and faction_string ~= "wh2_dlc10_def_blood_voyage" and culture ~= "wh2_dlc09_tmb_tomb_kings" then
    cm:treasury_mod(faction_string, reimbursement_amount)
    cbac:log("[REIMBURSEMENT] Gold amount reimbursed to faction: "..reimbursement_amount)
  else
    cbac:log("Faction does not get reimbursed because it's the rebels.")
  end
  --removing units
  for i=1, (#units_to_remove) do
    cm:remove_unit_from_character(cm:char_lookup_str(char_cqi), units_to_remove[i])
    cbac:log("[REMOVED UNIT] of type: ["..units_to_remove[i].."].")
  end

  --add units, on a delay because aaaargh!
  cm:callback(function()
      for i=1, (#units_to_add) do
        cm:grant_unit_to_character(cm:char_lookup_str(char_cqi), units_to_add[i])
        cbac:log("[ADDED UNIT] of type: ["..units_to_add[i].."] to army of character with cqi: "..char_cqi..".")
      end
      cm:callback(function()
          local unit_list_new = character:military_force():unit_list()
          local unit_number_new = character:military_force():unit_list():num_items()
          if (#units_to_remove) > 1 then
            jlog("DOWNGRADE: Char["..(char_cqi).."]")
            for j=0, unit_list_new:num_items()-1 do
              cbac:log("["..j.."]: ["..unit_list_new:item_at(j):unit_key().."]")
            end
            if #unit_list ~= unit_number_new then
              jlog("******************** ERROR: ARMY ["..(char_cqi).."] HAS FEWER UNITS AFTER DOWNGRADE ********************")
            end
          end
        end, 0.2)
    end, 0.1)

end

local function upgrade_ai_army(character, limit)

  local turn_number = cm:model():turn_number()
  local unit_list = character:military_force():unit_list()
  local faction_string = character:faction():name()
  local culture = character:faction():culture()
  local current_unit_object = nil
  local current_unit_key = ""
  local replacement_unit_key = ""
  local possible_indices = {}
  local char_cqi = character:command_queue_index()
  local army_is_over_limit = false
  local random_number_replacement = 0

  --calculate effective army limit
  local effective_army_limit = cbac:get_config("army_limit_ai")
  if (cbac:get_config("dynamic_limit")) then
    local lord_rank = character:rank()
    local limit_rank = cbac:get_config("limit_rank")
    local limit_step = cbac:get_config("limit_step")
    local limit_deceleration = cbac:get_config("limit_deceleration")

    local total_deceleration_factor = 0
    local number_of_steps = (math.floor(lord_rank/limit_rank)) - 1
    local step = 1
    while step <= number_of_steps do
      if (limit_deceleration*step <= limit_step) then
        total_deceleration_factor = total_deceleration_factor + (limit_deceleration*step)
      else
        total_deceleration_factor = total_deceleration_factor + limit_step
      end
      step = step + 1
    end
    effective_army_limit = effective_army_limit + ((math.floor(lord_rank/limit_rank))*limit_step) - total_deceleration_factor
  end

  --how much unit cost do we have to add to this army to get to the army limit?
  local army_value_to_add = effective_army_limit - get_army_cost(character)
  local units_to_remove = {}
  local units_to_add = {}
  --how much gold does the AI need to pay for the unit upgrades?
  local surcharge_amount = 0
  --create a table with the indices of the units in the army so we can shuffle them
  cbac:log("------------------------------------------------------------------------------------------------------------------------------")
  cbac:log("------------------------------------------------------------------------------------------------------------------------------")
  cbac:log("["..turn_number.."] Army".."["..char_cqi.."] of "..faction_string.. " can add this unit value: "..army_value_to_add.." (Treasury: "..(character:faction():treasury())..")")
  cbac:log("Army unit list before changes:")
  for i=0, unit_list:num_items()-1 do
    table.insert(possible_indices, i)
    cbac:log("["..i.."]: ["..unit_list:item_at(i):unit_key().."]")
  end

  --shuffle the list of indices so we don't always change units in the same slots first
  possible_indices = shuffle(possible_indices)

  local units_replaced_count = 0
  local number_units_before_upgrade = unit_list:num_items()
  for j=1, (#possible_indices) do
    --index table is now shuffled, do replace for every item until cost no longer under limit
    --get the unit we want to examine
    current_unit_object = unit_list:item_at(possible_indices[j])
    current_unit_key = current_unit_object:unit_key()

    --only proceed if this unit has possible replacements
    if cbac_ai_upgradeable_units[current_unit_key] then
      --find the replacement unit and add its name to table for later addition to army
      random_number_replacement = cm:random_number(3)
      replacement_unit_key = cbac_ai_upgradeable_units[current_unit_key][random_number_replacement]
      if character:military_force():can_recruit_unit(replacement_unit_key) then
        if (character:faction():unit_cap_remaining(replacement_unit_key) == -1) or (character:faction():unit_cap_remaining(replacement_unit_key) > 0) then
          --add unit key to table of units to remove later
          table.insert(units_to_remove, current_unit_key)
          cbac:log("[PENDING REMOVAL]: Unit of type ["..current_unit_key.."] from army slot #"..possible_indices[j]..".")
          table.insert(units_to_add, replacement_unit_key)
          units_replaced_count = units_replaced_count + 1
          cbac:log("[PENDING ADDITION]: Unit of type ["..replacement_unit_key.."] to army of character with cqi: "..char_cqi..".")
          --how much did that cost us?
          for k=1, #cbac_units_cost do
            if cbac_units_cost[k][1] == replacement_unit_key then
              surcharge_amount = surcharge_amount + math.floor(((cbac_units_cost[k][2] - current_unit_object:get_unit_custom_battle_cost()) / 2))
              army_value_to_add = army_value_to_add - math.floor(((cbac_units_cost[k][2] - current_unit_object:get_unit_custom_battle_cost()) / 2))
              break
            end
          end
          --did we mark enough units for upgrade to get close enough to the cost limit?
          --we stop upgrading units if the limit is less than 1500 gold away AND we have upgraded at least one unit
          if army_value_to_add < 1500 and units_replaced_count > 0 then
            cbac:log("This army is now close to the limit. Replaced units: "..units_replaced_count)
            army_is_over_limit = true
            break
          end
          --we also have to stop adding units to the queue if we have already reached the allowed number
          if units_replaced_count >= limit then
            cbac:log("We have replaced the maximum allowed number of units per turn. Replaced units: "..units_replaced_count)
            break
          end
        else
          cbac:log("Would like to upgrade unit "..current_unit_key.." but faction is at the unit cap for chosen replacement unit "..replacement_unit_key)
        end
      else
        cbac:log("Would like to upgrade unit "..current_unit_key.." but faction is not currently able to recruit chosen replacement unit "..replacement_unit_key)
      end
      --currently examined unit has no replacement
    else
      cbac:log("[IGNORED UNIT] Current unit with key: ["..current_unit_key.."] has no defined replacement, will be left unchanged.")
    end
  end

  if not army_is_over_limit then
    cbac:log("Looped through all units in army once without reaching the limit for cost or number of exchanges.")
  end
  --charge upgrade costs
  if faction_string ~= "rebels" and faction_string ~= "wh2_dlc10_def_blood_voyage" and culture ~= "wh2_dlc09_tmb_tomb_kings"  then
    cbac:log("[REIMBURSEMENT] Gold amount charged for unit upgrades: "..surcharge_amount)
    cm:treasury_mod(faction_string, (surcharge_amount * (-1)))
  end

  --debug
  if units_replaced_count > 1 then
    cbac:log("Char["..(char_cqi).."] of faction "..(faction_string).." unit list before upgrade:")
    for i=0, unit_list:num_items()-1 do
      cbac:log("["..i.."]: ["..unit_list:item_at(i):unit_key().."]")
    end
  end

  --removing units
  for i=1, (#units_to_remove) do
    cbac:log("[REMOVED UNIT] of type: ["..units_to_remove[i].."].")
    cm:remove_unit_from_character(cm:char_lookup_str(char_cqi), units_to_remove[i])
  end

  --add units
  cm:callback(function()
      for i=1, (#units_to_add) do
        cbac:log("[ADDED UNIT] of type: ["..units_to_add[i].."] to army of character with cqi: "..char_cqi..".")
        cm:grant_unit_to_character(cm:char_lookup_str(char_cqi), units_to_add[i])
      end
      cm:callback(function()
          local unit_list_new = character:military_force():unit_list()
          local unit_number_new = character:military_force():unit_list():num_items()
          if units_replaced_count > 1 then
            jlog("UPGRADE: Char["..(char_cqi).."] of faction "..(faction_string).." # units before change, number upgraded, number after upgrade: "..(number_units_before_upgrade).." | "..(units_replaced_count).." | "..(unit_number_new))
            for j=0, unit_list_new:num_items()-1 do
              cbac:log("["..j.."]: ["..unit_list_new:item_at(j):unit_key().."]")
            end
            if number_units_before_upgrade ~= unit_number_new then
              jlog("******************** ERROR: ARMY ["..(char_cqi).."] HAS FEWER UNITS AFTER UPGRADE ********************")
            end
          end
        end, 0.2)

    end, 0.1)

end

--returns false if the AI character's faction is at war with the player and in one of his regions or close to one of his armies
local function is_allowed_to_upgrade(character)
  local result = true
  local region = character:region()
  if (not(cm:char_is_agent(character))) then
    local player_faction_key = cm:get_human_factions()[1]
    local player_faction = cm:model():world():faction_by_key(player_faction_key)
    if (character:faction():at_war_with(player_faction)) then
      cbac:log("AI character's faction is at war with the player.")
      if not (region:is_abandoned() or region:region_data_interface():is_sea()) then
        local region_owner = region:owning_faction()
        if (region_owner == player_faction) then
          cbac:log("AI character is in player-owned region.")
          result = false
        end
      end
      local player_characters = player_faction:character_list()
      for i=0, player_characters:num_items()-1 do
        if cm:char_is_mobile_general_with_army(player_characters:item_at(i)) then
          if (cm:character_can_reach_character(character, player_characters:item_at(i))) then
            result = false
            cbac:log("This AI character could reach a player army on the current turn.")
          end
          if (player_characters:item_at(i):has_region()) then
            if (player_characters:item_at(i):region() == region) then
              result = false
              cbac:log("Found player army in AI character's current region.")
            end
          end
        end
      end
    end
  end
  return result
end

--get how many units should be upgraded per army per turn maximum, depending on the turn number and the faction's finances
local function get_upgrade_limit(faction)
  local turn_number = cm:model():turn_number()
  local treasury = faction:treasury()
  local result = 2
  local upgrade_grace_period = cbac:get_config("upgrade_grace_period")

  if treasury > 100000 then result = 6
  elseif treasury > 60000 then result = 5
  elseif treasury > 40000 then result = 4
  elseif treasury > 20000 then result = 3
  end
  if turn_number < upgrade_grace_period then result = 0
  elseif turn_number < (upgrade_grace_period + 10) then result = 1
  elseif turn_number < (upgrade_grace_period + 25) and result > 2 then result = 2
  elseif turn_number < (upgrade_grace_period + 40) and result > 3 then result = 3
  elseif turn_number < (upgrade_grace_period + 60) and result > 4 then result = 4
  end
  return result
end

--this checks all armies of a faction if they are over the cost limit
local function check_ai_army_limit(faction)
  local characters = faction:character_list()
  for i=0, characters:num_items()-1 do
    local current_army_cost = 0
    local current_character = characters:item_at(i)
    if cm:char_is_mobile_general_with_army(current_character) then
      current_army_cost = get_army_cost(current_character)
      local current_army_size = current_character:military_force():unit_list():num_items()
      local effective_army_limit = cbac:get_config("army_limit_ai")
      if (cbac:get_config("dynamic_limit")) then
        local lord_rank = current_character:rank()
        local limit_rank = cbac:get_config("limit_rank")
        local limit_step = cbac:get_config("limit_step")
        local limit_deceleration = cbac:get_config("limit_deceleration")

        local total_deceleration_factor = 0
        local number_of_steps = (math.floor(lord_rank/limit_rank)) - 1
        local step = 1
        while step <= number_of_steps do
          total_deceleration_factor = total_deceleration_factor + (limit_deceleration*step)
          step = step + 1
        end
        effective_army_limit = effective_army_limit + ((math.floor(lord_rank/limit_rank))*limit_step) - total_deceleration_factor
      end
      if (faction:name() ~= "rebels") and (faction:name() ~= "wh2_dlc10_def_blood_voyage") and (not (faction:name():find("_intervention"))) and (not (faction:name():find("_incursion"))) then
        if (current_army_cost > effective_army_limit) then
          --apply punishment
          cbac:log("AI Army #"..i.." of faction "..faction:name().." is over AI cost limit ("..effective_army_limit.."), will be modified! (Value: "..current_army_cost..")")
          enforce_limit_on_ai_army(current_character)
        elseif (current_army_cost < (effective_army_limit - 1500)) then
          cbac:log("checking an army of culture Empire...")
          if (cbac:get_config("upgrade_ai_armies") and (not faction:losing_money()) and (faction:treasury() > 7000) and (current_army_size > 17)) then
            local upgrade_limit = get_upgrade_limit(faction)
            if (is_allowed_to_upgrade(current_character)) and (upgrade_limit > 0) then
              cbac:log("Will try to upgrade AI army...")
              upgrade_ai_army(current_character, upgrade_limit)
            else
              cbac:log("Can't upgrade this army currently.")
            end
          end
        end
      end
    end
  end --for army loop
end

--*****************
--END OF SECTION FOR AI
--*****************

--auto-leveling for AI lords
local character_level_xp = {
  0,900,1900,3000,4200,5500,6890,8370,9940,11510,					-- 1 - 10
  13080,14660,16240,17820,19400,20990,22580,24170,25770,27370,	-- 11 - 20
  28980,30590,32210,33830,35460,37100,38740,40390,42050,43710,	-- 21 - 30
  45380,47060,48740,50430,52130,53830,55540,57260,58990,60730		-- 31 - 40
};

local function get_autolevel_target()
  local turn_number = cm:model():turn_number()
  local modifier = 5
  if cbac:get_config("autolevel_ai_lords") == 1 then
    modifier = 8
  elseif cbac:get_config("autolevel_ai_lords") == 2 then
    modifier = 6
  elseif cbac:get_config("autolevel_ai_lords") == 4 then
    modifier = 4
  elseif cbac:get_config("autolevel_ai_lords") == 5 then
    modifier = 3
  end
  local result = math.ceil((turn_number - 20) / modifier)
  if result < 1 then
    result = 1
  elseif result > 40 then
    result = 40
  end
  return result
end

core:add_listener(
  "JCBAC_AILordCreated",
  "CharacterCreated",
  function(context)
    return cm:character_is_army_commander(context:character()) and not (context:character():faction():is_human()) and (cbac:get_config("autolevel_ai_lords") > 0);
  end,
  function(context)
    cbac:log("AI General Created!")
    local new_general = context:character()
    local target_rank = get_autolevel_target()
    cm:callback(function()
        local new_general_cqi = new_general:command_queue_index()
        local new_general_string = cm:char_lookup_str(new_general_cqi)
        local char_rank = new_general:rank()
        if target_rank > 1 then
          local current_xp = character_level_xp[char_rank]
          local target_xp = character_level_xp[target_rank]
          if target_rank > 40 then
            target_xp = character_level_xp[40]
          end
          if (target_xp-current_xp) > 0 then
            cm:add_agent_experience(new_general_string, (target_xp-current_xp))
          end
        end
      end, 0.2)
  end,
  true
)

core:add_listener(
  "JCBAC_AILordCompletedBattle",
  "CharacterCompletedBattle",
  function(context)
    return cm:character_is_army_commander(context:character()) and not (context:character():faction():is_human()) and (cbac:get_config("autolevel_ai_lords") > 0);
  end,
  function(context)
    cbac:log("AI General Completed Battle!")
    local new_general = context:character()
    local target_rank = get_autolevel_target()
    cm:callback(function()
        local new_general_cqi = new_general:command_queue_index()
        local new_general_string = cm:char_lookup_str(new_general_cqi)
        local char_rank = new_general:rank()
        if target_rank > 1 then
          local current_xp = character_level_xp[char_rank]
          local target_xp = character_level_xp[target_rank]
          if target_rank > 40 then
            target_xp = character_level_xp[40]
          end
          if (target_xp-current_xp) > 0 then
            cm:add_agent_experience(new_general_string, (target_xp-current_xp))
          end
        end
      end, 0.2)
  end,
  true
)

core:add_listener(
  "ArmyCostLimitsAI",
  "FactionTurnStart",
  function(context)
    return (not context:faction():is_human())
  end,
  function(context)
    check_ai_army_limit(context:faction())
  end,
  true
)
