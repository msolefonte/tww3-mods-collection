
--Log script to text
--v function(text: string | number | boolean | CA_CQI)
local function JADLOG(text)
  if not (__write_output_to_logfile or __enable_jadlog) then
    return;
  end

  local logText = tostring(text)
  local logTimeStamp = os.date("%d, %m %Y %X")
  local popLog = io.open("jadawin_cbac_log.txt","a")
  --# assume logTimeStamp: string
  popLog :write("JADAWIN_CBAC:  [".. logTimeStamp .. "]:  "..logText .. "  \n")
  popLog :flush()
  popLog :close()
end

--Reset the log at session start
--v function()
local function JADSESSIONLOG()
  if not (__write_output_to_logfile or __enable_jadlog) then
    return;
  end
  local logTimeStamp = os.date("%d, %m %Y %X")
  --# assume logTimeStamp: string

  local popLog = io.open("jadawin_cbac_log.txt","w+")
  popLog :write("NEW LOG ["..logTimeStamp.."] \n")
  popLog :flush()
  popLog :close()
end
JADSESSIONLOG()

--log text
local function jlog(text)
  JADLOG(tostring(text))
end

local function read_mct_values(ignore_setting_lock)
  --use values set in MCT, if available
  if (mct_cbac) then
    local mct_mymod = mct_cbac:get_mod_by_key("jadawin_cost_based_army_caps")
    if (ignore_setting_lock or (not(mct_mymod:get_option_by_key("settings_locked"):get_finalized_setting()))) then
      cm:set_saved_value("jcbac_army_limit_player", mct_mymod:get_option_by_key("player_limit"):get_finalized_setting())
      cm:set_saved_value("jcbac_army_limit_ai", mct_mymod:get_option_by_key("ai_limit"):get_finalized_setting())
      cm:set_saved_value("jcbac_dynamic_limit", mct_mymod:get_option_by_key("dynamic_limit"):get_finalized_setting())
      cm:set_saved_value("jcbac_limit_rank", mct_mymod:get_option_by_key("limit_rank"):get_finalized_setting())
      cm:set_saved_value("jcbac_limit_step", mct_mymod:get_option_by_key("limit_step"):get_finalized_setting())
      cm:set_saved_value("jcbac_limit_deceleration", mct_mymod:get_option_by_key("limit_deceleration"):get_finalized_setting())
      cm:set_saved_value("jcbac_hero_cap", mct_mymod:get_option_by_key("hero_cap"):get_finalized_setting())
      cm:set_saved_value("jcbac_supply_lines", mct_mymod:get_option_by_key("supply_lines"):get_finalized_setting())
      cm:set_saved_value("jcbac_upgrade_ai_armies", mct_mymod:get_option_by_key("upgrade_ai_armies"):get_finalized_setting())
      cm:set_saved_value("jcbac_upgrade_grace_period", mct_mymod:get_option_by_key("upgrade_grace_period"):get_finalized_setting())
      cm:set_saved_value("jcbac_autolevel_ai_lords", mct_mymod:get_option_by_key("autolevel_ai"):get_finalized_setting())
      cm:set_saved_value("jcbac_mct_read_20210820", true)
    end
  else
    --default values if MCT not used
    cm:set_saved_value("jcbac_army_limit_player", 10500)
    cm:set_saved_value("jcbac_army_limit_ai", 12000)
    cm:set_saved_value("jcbac_dynamic_limit", true)
    cm:set_saved_value("jcbac_limit_rank", 2)
    cm:set_saved_value("jcbac_limit_step", 1000)
    cm:set_saved_value("jcbac_limit_deceleration", 50)
    cm:set_saved_value("jcbac_hero_cap", 2)
    cm:set_saved_value("jcbac_supply_lines", false)
    cm:set_saved_value("jcbac_upgrade_ai_armies", false)
    cm:set_saved_value("jcbac_upgrade_grace_period", 20)
    cm:set_saved_value("jcbac_autolevel_ai_lords", 3)
    cm:set_saved_value("jcbac_mct_read_20210820", true)
  end
end

local function get_army_cost(character)
  local current_character = character
  --if char has no army, return -1
  if not current_character:has_military_force() then
    return -1
  end

  local military_force = current_character:military_force()
  local unit_list = military_force:unit_list()
  local current_unit
  local army_point_cost = 0
  for i=0, unit_list:num_items()-1 do
    current_unit = unit_list:item_at(i)
    --the Green Knight is always a free unit
    if not (current_unit:unit_key() == "wh_dlc07_brt_cha_green_knight_0") then
      army_point_cost = army_point_cost + current_unit:get_unit_custom_battle_cost()
    end
  end
  return army_point_cost
end

local function get_army_supply_factor(character, added_cost)
  local current_character = character
  --if char has no army, return -1
  if not current_character:has_military_force() then
    return -1
  end
  local supply_factor = 1
  local army_point_cost = get_army_cost(current_character) + added_cost
  --determine army limit
  local army_limit = cm:get_saved_value("jcbac_army_limit_player")
  if (cm:get_saved_value("jcbac_dynamic_limit")) then
    local lord_rank = character:rank()
    local limit_rank = cm:get_saved_value("jcbac_limit_rank")
    local limit_step = cm:get_saved_value("jcbac_limit_step")
    local limit_deceleration = cm:get_saved_value("jcbac_limit_deceleration")

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
    army_limit = army_limit + ((math.floor(lord_rank/limit_rank))*limit_step) - total_deceleration_factor
  end


  if (army_point_cost / army_limit) < 0.25 then
    supply_factor = 0.25
  elseif (army_point_cost / army_limit) < 0.5 then
    supply_factor = 0.5
  elseif (army_point_cost / army_limit) < 0.75 then
    supply_factor = 0.75
  end
  return supply_factor
end

local function get_army_hero_count(character)
  local current_character = character
  --if char has no army, return -1
  if not current_character:has_military_force() then
    return -1
  end

  local military_force = current_character:military_force()
  local unit_list = military_force:unit_list()
  local current_unit
  local army_hero_count = -1
  for i=0, unit_list:num_items()-1 do
    current_unit = unit_list:item_at(i)
    --the Green Knight is not counted for the hero limit | also the special heroes for Clan Angrund
    if string.find(current_unit:unit_key(), "_cha_") or (current_unit:unit_key() == "wh2_dlc11_cst_inf_count_noctilus_0") or (current_unit:unit_key() == "wh2_dlc11_cst_inf_count_noctilus_1") then
      if not (current_unit:unit_key() == "wh_dlc07_brt_cha_green_knight_0" or current_unit:unit_key() == "wh_dlc06_dwf_cha_master_engineer_ghost_0" or current_unit:unit_key() == "wh_dlc06_dwf_cha_runesmith_ghost_0" or current_unit:unit_key() == "wh_dlc06_dwf_cha_thane_ghost_0" or current_unit:unit_key() == "wh_dlc06_dwf_cha_thane_ghost_1") then
        army_hero_count = army_hero_count + 1
      end
    end
  end
  return army_hero_count
end

local function get_character_cost_string(character)
  local current_character = character
  local return_string = ""
  --if char has no army, return -1
  if not current_character:has_military_force() then
    return return_string
  else
    return_string = "\nCost values of lord/heroes: "
  end

  local military_force = current_character:military_force()
  local unit_list = military_force:unit_list()
  local current_unit
  for i=0, unit_list:num_items()-1 do
    current_unit = unit_list:item_at(i)
    if string.find(current_unit:unit_key(), "_cha_") then
      return_string = return_string..(current_unit:get_unit_custom_battle_cost()).."  "
    end
  end
  return return_string
end

local function get_garrison_cost(cqi)
  local military_force = cm:get_military_force_by_cqi(cqi)
  local unit_list = military_force:unit_list()
  local current_unit
  local army_point_cost = 0
  for i=0, unit_list:num_items()-1 do
    current_unit = unit_list:item_at(i)
    army_point_cost = army_point_cost + current_unit:get_unit_custom_battle_cost()
  end
  return army_point_cost
end

local function get_army_queued_units_cost()
  local queued_units_cost = 0
  local current_queued_unit
  local i = 0
  while (find_uicomponent(core:get_ui_root(), "main_units_panel", "units", "QueuedLandUnit "..i)) do
    current_queued_unit = find_uicomponent(core:get_ui_root(), "main_units_panel", "units", "QueuedLandUnit "..i)
    current_queued_unit:SimulateMouseOn()
    local unit_info = find_uicomponent(core:get_ui_root(), "UnitInfoPopup", "tx_unit-type")
    local rawstring = unit_info:GetStateText()
    local infostart = string.find(rawstring, "unit/") + 5
    local infoend = string.find(rawstring, "]]") - 1
    local queued_unit_name = string.sub(rawstring, infostart, infoend)

    for j=1, #cbac_units_cost do
      if cbac_units_cost[j][1] == queued_unit_name then
        queued_units_cost = queued_units_cost+cbac_units_cost[j][2]
        break
      end
    end
    i = i+1
  end
  return queued_units_cost
end


-- check all armies of faction and apply penalties if over fund limit
local function enforce_cost_limit(faction)
  local characters = faction:character_list()
  for i=0, characters:num_items()-1 do
    local current_character = characters:item_at(i)
    local current_army_cqi = 0
    if cm:char_is_mobile_general_with_army(current_character) then
      current_army_cqi = current_character:military_force():command_queue_index()
      local effective_army_limit = cm:get_saved_value("jcbac_army_limit_player")
      if (cm:get_saved_value("jcbac_dynamic_limit")) then
        local lord_rank = current_character:rank()
        local limit_rank = cm:get_saved_value("jcbac_limit_rank")
        local limit_step = cm:get_saved_value("jcbac_limit_step")
        local limit_deceleration = cm:get_saved_value("jcbac_limit_deceleration")

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
      if (get_army_cost(current_character) > effective_army_limit) or (get_army_hero_count(current_character) > cm:get_saved_value("jcbac_hero_cap")) then
        --the Vermintide army spawned from a Skaven undercity is exempt from the limit while it has the initial effect
        if not (current_character:military_force():has_effect_bundle("wh2_dlc12_bundle_underempire_army_spawn")) then
          --apply punishment
          cbac:log("Army ("..i..") is over cost limit ("..effective_army_limit.."), will be punished!")
          cm:apply_effect_bundle_to_force("jcbac_army_cost_limit_penalty", current_army_cqi, 1)
        end
      end
    end
  end
end

-- check all armies of faction and remove penalties if not over fund limit
local function check_remove_cost_penalties(faction)
  local characters = faction:character_list()
  for i=0, characters:num_items()-1 do
    local current_character = characters:item_at(i)
    local current_army_cqi = 0
    if cm:char_is_mobile_general_with_army(current_character) then
      current_army_cqi = current_character:military_force():command_queue_index()
      local effective_army_limit = cm:get_saved_value("jcbac_army_limit_player")
      if (cm:get_saved_value("jcbac_dynamic_limit")) then
        local lord_rank = current_character:rank()
        local limit_rank = cm:get_saved_value("jcbac_limit_rank")
        local limit_step = cm:get_saved_value("jcbac_limit_step")
        local limit_deceleration = cm:get_saved_value("jcbac_limit_deceleration")

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
      if get_army_cost(current_character) <= effective_army_limit then
        --remove punishment
        cbac:log("Army ("..i..") is not over cost limit, will remove penalty!")
        cm:remove_effect_bundle_from_force("jcbac_army_cost_limit_penalty", current_army_cqi)
      end
    end
  end
end

local function set_tooltip_text_army_cost(character)
  local lord_rank = character:rank()
  local limit_rank = cm:get_saved_value("jcbac_limit_rank")
  local limit_step = cm:get_saved_value("jcbac_limit_step")
  local limit_deceleration = cm:get_saved_value("jcbac_limit_deceleration")
  local next_limit_increase = limit_step - ((math.floor(lord_rank/limit_rank)) * limit_deceleration)
  if next_limit_increase < 0 then next_limit_increase = 0 end
  local army_cost = get_army_cost(character)
  local hero_count = get_army_hero_count(character)
  local army_queued_units_cost = get_army_queued_units_cost()
  local this_army_cost_limit
  local supply_factor = get_army_supply_factor(character, 0)
  local zoom_component = find_uicomponent(core:get_ui_root(), "main_units_panel", "button_focus")
  if not zoom_component then
    return
  end
  local tooltip_text = ""

  if character:faction():is_human() then
    this_army_cost_limit = cm:get_saved_value("jcbac_army_limit_player")
  else
    this_army_cost_limit = cm:get_saved_value("jcbac_army_limit_ai")
  end
  if (cm:get_saved_value("jcbac_dynamic_limit")) then
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
    this_army_cost_limit = this_army_cost_limit + ((math.floor(lord_rank/limit_rank))*limit_step) - total_deceleration_factor
  end

  --Apply cost total of this army as tooltip text of the zoom button of the army
  tooltip_text = "Army current point cost: "..army_cost.." (Limit: "..this_army_cost_limit..")"
  if army_queued_units_cost > 0 then
    tooltip_text = tooltip_text.."\nProjected point cost after recruitment: "..(army_cost+army_queued_units_cost)
  end
  tooltip_text = tooltip_text..(get_character_cost_string(character))
  if (cm:get_saved_value("jcbac_dynamic_limit")) then
    tooltip_text = tooltip_text.."\nLimit rises every "..limit_rank.." lord levels. Next increase: " ..next_limit_increase
  end
  if (army_cost+army_queued_units_cost) > this_army_cost_limit then
    tooltip_text = "[[col:red]]"..tooltip_text.."[[/col]]"
  end
  if character:faction():is_human() and (hero_count) > cm:get_saved_value("jcbac_hero_cap") then
    tooltip_text = tooltip_text.."\n[[col:red]]".."This army has too many heroes in it!".."[[/col]]"
  end
  local subculture = character:faction():subculture()
  if character:faction():is_human() and (cm:get_saved_value("jcbac_supply_lines")) then
    if (subculture == "wh_dlc03_sc_bst_beastmen" or subculture == "wh_main_sc_brt_bretonnia" or subculture == "wh2_dlc09_sc_tmb_tomb_kings" or subculture == "wh_main_sc_chs_chaos" or character:faction():name() == "wh2_dlc13_lzd_spirits_of_the_jungle") then
      tooltip_text = tooltip_text.."\nThis faction does not use Supply Lines"
    else
      if character:character_subtype("wh2_main_def_black_ark") then
        tooltip_text = tooltip_text.."\nBlack Arks do not contribute to the Supply Lines penalty"
      else
        tooltip_text = tooltip_text.."\nArmy contributes at "..(supply_factor*100).."% to Supply Lines"
        if army_queued_units_cost > 0 then
          local supply_with_queued = get_army_supply_factor(character, army_queued_units_cost)
          tooltip_text = tooltip_text.." (will be "..(supply_with_queued*100).."%)"
        end
      end
    end
  end
  zoom_component:SetTooltipText(tooltip_text, true)
end

local function set_tooltip_text_garrison_cost(cqi)
  local zoom_component = find_uicomponent(core:get_ui_root(), "main_settlement_panel_header", "button_info")
  if not zoom_component then
    return
  end
  local tooltip_text = ""
  if cqi == -1 then
    tooltip_text = "Selected region has no garrison."
  else
    local army_cost = get_garrison_cost(cqi)
    --Apply cost total of this army as tooltip text of the zoom button of the army
    tooltip_text = "The units in the garrison of the selected settlement cost "..army_cost.." points. Garrisons have no limit."
  end
  zoom_component:SetTooltipText(tooltip_text, true)
end

local function apply_supply_lines(faction)
  local total_supply_lines_factor = 0
  local characters = faction:character_list()
  for i=0, characters:num_items()-1 do
    local current_character = characters:item_at(i)
    local current_army_cqi = 0
    if cm:char_is_mobile_general_with_army(current_character) and not current_character:character_subtype("wh2_main_def_black_ark") then
      current_army_cqi = current_character:military_force():command_queue_index()
      --the Vermintide army spawned from a Skaven undercity is exempt from supply lines while it has the initial effect
      if not (current_character:military_force():has_effect_bundle("wh2_dlc12_bundle_underempire_army_spawn")) then
        --add this army's supply factor
        total_supply_lines_factor = total_supply_lines_factor + get_army_supply_factor(current_character, 0)
      end
    end
  end
  --one full army is free (or several partial armies that add up to one full army or less)
  total_supply_lines_factor = total_supply_lines_factor-1
  --but make sure that the factor is not <0
  if total_supply_lines_factor < 0 then
    total_supply_lines_factor = 0
  end

  --base penalty is +15% unit upkeep on VH and Legendary
  local base_supply_lines_penalty = 15
  --modify it for easy difficulties
  local combined_difficulty = cm:model():combined_difficulty_level()
  if combined_difficulty == -1 then --Hard
    base_supply_lines_penalty = 7
  elseif combined_difficulty == 0 then --Normal
    base_supply_lines_penalty = 2
  elseif combined_difficulty == 1 then --Easy
    base_supply_lines_penalty = 1
  end

  local effect_strength = math.ceil(total_supply_lines_factor * base_supply_lines_penalty)

  local supply_lines_effect_bundle = cm:create_new_custom_effect_bundle("jcbac_supply_lines")
  supply_lines_effect_bundle:add_effect("wh_main_effect_force_all_campaign_upkeep", "force_to_force_own_factionwide", effect_strength)
  supply_lines_effect_bundle:set_duration(0)
  cm:apply_custom_effect_bundle_to_faction(supply_lines_effect_bundle, faction);
end

--****************************************
--****************************************
--SECTION FOR AI
--****************************************
--****************************************
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
  local effective_army_limit = cm:get_saved_value("jcbac_army_limit_ai")
  if (cm:get_saved_value("jcbac_dynamic_limit")) then
    local lord_rank = character:rank()
    local limit_rank = cm:get_saved_value("jcbac_limit_rank")
    local limit_step = cm:get_saved_value("jcbac_limit_step")
    local limit_deceleration = cm:get_saved_value("jcbac_limit_deceleration")

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
  local effective_army_limit = cm:get_saved_value("jcbac_army_limit_ai")
  if (cm:get_saved_value("jcbac_dynamic_limit")) then
    local lord_rank = character:rank()
    local limit_rank = cm:get_saved_value("jcbac_limit_rank")
    local limit_step = cm:get_saved_value("jcbac_limit_step")
    local limit_deceleration = cm:get_saved_value("jcbac_limit_deceleration")

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
  local upgrade_grace_period = cm:get_saved_value("jcbac_upgrade_grace_period")

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
      local effective_army_limit = cm:get_saved_value("jcbac_army_limit_ai")
      if (cm:get_saved_value("jcbac_dynamic_limit")) then
        local lord_rank = current_character:rank()
        local limit_rank = cm:get_saved_value("jcbac_limit_rank")
        local limit_step = cm:get_saved_value("jcbac_limit_step")
        local limit_deceleration = cm:get_saved_value("jcbac_limit_deceleration")

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
          if (cm:get_saved_value("jcbac_upgrade_ai_armies") and (not faction:losing_money()) and (faction:treasury() > 7000) and (current_army_size > 17)) then
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
  if cm:get_saved_value("jcbac_autolevel_ai_lords") == 1 then
    modifier = 8
  elseif cm:get_saved_value("jcbac_autolevel_ai_lords") == 2 then
    modifier = 6
  elseif cm:get_saved_value("jcbac_autolevel_ai_lords") == 4 then
    modifier = 4
  elseif cm:get_saved_value("jcbac_autolevel_ai_lords") == 5 then
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
    return cm:character_is_army_commander(context:character()) and not (context:character():faction():is_human()) and (cm:get_saved_value("jcbac_autolevel_ai_lords") > 0);
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
    return cm:character_is_army_commander(context:character()) and not (context:character():faction():is_human()) and (cm:get_saved_value("jcbac_autolevel_ai_lords") > 0);
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
  "MCT_CBAC",
  "MctInitialized",
  true,
  function(context)
    mct_cbac = context:mct()
  end,
  true
)


--Listener for when the MCT settings screen was opened and settings changed
core:add_listener(
  "MCT_CHANGED_CBAC",
  "MctFinalized",
  true,
  function(context)
    --re-read settings into the saved values
    read_mct_values(false)
  end,
  true
)

--Listener for when the MCT settings screen was opened
core:add_listener(
  "MCT_PANEL_OPENED_CBAC",
  "MctPanelOpened",
  true,
  function(context)
    --make all options read-only if the campaign was started with the settings lock enabled
    local mct_mymod = mct_cbac:get_mod_by_key("jadawin_cost_based_army_caps")
    if (mct_mymod:get_option_by_key("settings_locked"):get_finalized_setting()) then
      mct_mymod:get_option_by_key("player_limit"):set_read_only(true)
      mct_mymod:get_option_by_key("ai_limit"):set_read_only(true)
      mct_mymod:get_option_by_key("dynamic_limit"):set_read_only(true)
      mct_mymod:get_option_by_key("limit_rank"):set_read_only(true)
      mct_mymod:get_option_by_key("limit_step"):set_read_only(true)
      mct_mymod:get_option_by_key("hero_cap"):set_read_only(true)
      mct_mymod:get_option_by_key("supply_lines"):set_read_only(true)
      mct_mymod:get_option_by_key("upgrade_ai_armies"):set_read_only(true)
      mct_mymod:get_option_by_key("autolevel_ai"):set_read_only(true)
    end
  end,
  true
)

-- event army selected, show cost in tooltip
core:add_listener(
  "JCBAC_ArmyCostTooltip",
  "CharacterSelected",
  function(context)
    return context:character():has_military_force();
  end,
  function(context)
    cbac:log("Listener JCBAC_ArmyCostTooltip has fired.")
    local current_character = context:character()
    --store the character cqi also in saved values so other unrelated events can use it
    cm:set_saved_value("jcbac_last_selected_char_cqi", (current_character:command_queue_index()))
    cbac:log("Selected character's CQI: "..current_character:command_queue_index())
    if (not (cm:get_saved_value("jcbac_mct_read_20210814"))) then
      read_mct_values(true)
    end
    cm:callback(function()
        set_tooltip_text_army_cost(current_character)
        cbac:log("Listener JCBAC_ArmyCostTooltip has finished.")
      end, 0.1)
  end,
  true
)

-- event army selected, show cost in tooltip
core:add_listener(
  "JCBAC_GarrisonCostTooltip",
  "SettlementSelected",
  function(context)
    return true;
  end,
  function(context)
    cbac:log("Listener JCBAC_GarrisonCostTooltip has fired.")
    local garrison_residence = context:garrison_residence()
    local region = garrison_residence:region()
    local cqi = -1
    if not region:is_abandoned() then
      local garrison_commander = cm:get_garrison_commander_of_region(region)
      if garrison_commander then
        local army = garrison_commander:military_force()
        cqi = army:command_queue_index()
      end
    end
    cm:callback(function()
        set_tooltip_text_garrison_cost(cqi)
        cbac:log("Listener JCBAC_GarrisonCostTooltip has finished.")
      end, 0.1)
  end,
  true
)

core:add_listener(
  "JCBAC_NormalUnitDisbandedEvent",
  "UnitDisbanded",
  function(context)
    return cm.campaign_ui_manager:is_panel_open("units_panel") and context:unit():faction():is_human();
  end,
  function(context)
    cbac:log("Listener JCBAC_NormalUnitDisbandedEvent has fired.")
    cm:callback(function()
        check_remove_cost_penalties(cm:model():world():whose_turn_is_it())
        cbac:log("Listener JCBAC_NormalUnitDisbandedEvent has finished.")
      end, 0.1)
  end,
  true
)

core:add_listener(
  "JCBAC_GeneralDisbandedEvent",
  "CharacterConvalescedOrKilled",
  function(context)
    return cm:char_is_mobile_general_with_army(context:character());
  end,
  function(context)
    cbac:log("Listener JCBAC_GeneralDisbandedEvent has fired.")
    cm:set_saved_value("jcbac_last_selected_char_cqi", nil)
    cbac:log("Listener JCBAC_GeneralDisbandedEvent has finished.")
  end,
  true
)

core:add_listener(
  "JCBAC_UnitMergedEvent",
  "UnitMergedAndDestroyed",
  function(context)
    return cm.campaign_ui_manager:is_panel_open("units_panel") and context:unit():faction():is_human();
  end,
  function(context)
    cbac:log("Listener JCBAC_UnitMergedEvent has fired.")
    cm:callback(function()
        check_remove_cost_penalties(cm:model():world():whose_turn_is_it())
        cbac:log("Listener JCBAC_UnitMergedEvent has finished.")
      end, 0.1)
  end,
  true
)

--catch all clicks to refresh the army cost tooltip if the units_panel is open
--this fires also when player cancels recruitment of a unit, adds a unit to the queue etc
core:add_listener(
  "JCBAC_ClickEvent",
  "ComponentLClickUp",
  function(context)
    return cm.campaign_ui_manager:is_panel_open("units_panel");
  end,
  function(context)
    cm:callback(function()
        local last_selected_character = cm:get_character_by_cqi(cm:get_saved_value("jcbac_last_selected_char_cqi"))
        if last_selected_character then
          if not last_selected_character:is_wounded() then
            if cm:char_is_mobile_general_with_army(last_selected_character) then
              set_tooltip_text_army_cost(last_selected_character)
            end
          end
        end
      end, 0.3)
  end,
  true
)

-- event player starts turn
core:add_listener(
  "JCBAC_ApplyArmyPenalties",
  "FactionTurnStart",
  function(context) return (context:faction():is_human()) end,
  function(context)
    local current_faction = context:faction()
    local subculture = current_faction:subculture()
    local turn_number = cm:model():turn_number()
    cm:callback(function()
        --if it's the first turn or no saved values exist yet (meaning that the mod was just enabled in an existing campaign), read all the values from the MCT settings
        if (turn_number == 1 or not (cm:get_saved_value("jcbac_mct_read_20210814"))) then
          read_mct_values(true)
        end
        enforce_cost_limit(current_faction)
      end, 0.1)
  end,
  true
)

core:add_listener(
  "JCBAC_SupplyLines",
  "FactionTurnEnd",
  function(context)
    return (context:faction():is_human())
  end,
  function(context)
    local current_faction = context:faction()
    local subculture = current_faction:subculture()
    if (cm:get_saved_value("jcbac_supply_lines")) then
      if not (subculture == "wh_dlc03_sc_bst_beastmen" or subculture == "wh_main_sc_brt_bretonnia" or subculture == "wh2_dlc09_sc_tmb_tomb_kings" or subculture == "wh_main_sc_chs_chaos" or current_faction:name() == "wh2_dlc13_lzd_spirits_of_the_jungle") then
        apply_supply_lines(current_faction)
      end
    end
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
