local cbac = require("script/cbac/lib/cbac");

local function is_army_punisheable(military_force)
  -- The Vermintide army spawned from a Skaven undercity is exempt from the limit while it has the initial effect
  return not (military_force:has_effect_bundle("wh2_dlc12_bundle_underempire_army_spawn"));
end

local function enforce_army_cost_limit(character)
  if cm:char_is_mobile_general_with_army(character) then
    local current_army_cqi = current_character:military_force():command_queue_index();
    local army_limit = cbac:get_army_limit(character);

    if (cbac:get_army_cost(character) > army_limit) or (cbac:get_army_hero_count(character) > cbac:get_config("hero_cap")) then
      if is_army_punisheable(character:military_force()) then
        cbac:log("Army (" .. current_army_cqi .. ") is over cost limit (" .. effective_army_limit .. "), will be punished!")
        cm:apply_effect_bundle_to_force("cbac_army_cost_limit_penalty", current_army_cqi, 1);  -- TODO RENAME TABLES
        return;
      end
    end

    if get_army_cost(character) <= effective_army_limit then
      cbac:log("Army (" .. current_army_cqi .. ") is not over cost limit, will remove penalty!")
      cm:remove_effect_bundle_from_force("cbac_army_cost_limit_penalty", current_army_cqi);  -- TODO RENAME TABLES
    end
  end
end

local function enforce_faction_cost_limit(faction)
  for _, character in ipairs(faction:character_list()) do
    enforce_army_cost_limit(character);
  end
end

local function set_tooltip_text_army_cost(character) -- TODO Refactor
  local lord_rank = character:rank();

  local limit_rank = cbac:get_config("limit_rank");
  local limit_step = cbac:get_config("limit_step");
  local limit_deceleration = cbac:get_config("limit_deceleration");
  local next_limit_increase = limit_step - ((math.floor(lord_rank/limit_rank)) * limit_deceleration)
  if next_limit_increase < 0 then next_limit_increase = 0 end

  local army_cost = cbac:get_army_cost(character);
  local army_queue_cost = cbac:get_army_queued_units_cost();
  local army_limit = cbac:get_army_limit(character);
  local hero_count = cbac:get_army_hero_count(character);
  local supply_factor = cbac:get_army_supply_factor(character, 0);

  local zoom_component = find_uicomponent(core:get_ui_root(), "main_units_panel", "button_focus")
  if not zoom_component then
    return;
  end

  --Apply cost total of this army as tooltip text of the zoom button of the army
  local tooltip_text = "Army current point cost: " .. army_cost .. " (Limit: " .. army_limit .. ")";
  if army_queued_units_cost > 0 then
    tooltip_text = tooltip_text .. "\nProjected point cost after recruitment: " .. (army_cost + army_queued_units_cost);
  end
  tooltip_text = tooltip_text..(get_character_cost_string(character))
  if (cbac:get_config("dynamic_limit")) then
    tooltip_text = tooltip_text .. "\nLimit rises every " .. limit_rank .. " lord levels. Next increase: " .. next_limit_increase;
  end
  if (army_cost+army_queued_units_cost) > army_limit then
    tooltip_text = "[[col:red]]" .. tooltip_text .. "[[/col]]";
  end
  if character:faction():is_human() and (hero_count) > cbac:get_config("hero_cap") then
    tooltip_text = tooltip_text .. "\n[[col:red]]" .. "This army has too many heroes in it!" .. "[[/col]]"
  end

  local subculture = character:faction():subculture()
  if character:faction():is_human() and (cbac:get_config("supply_lines")) then
    -- TODO HARDCODED
    if (subculture == "wh_dlc03_sc_bst_beastmen" or subculture == "wh_main_sc_brt_bretonnia" or subculture == "wh2_dlc09_sc_tmb_tomb_kings" or subculture == "wh_main_sc_chs_chaos" or character:faction():name() == "wh2_dlc13_lzd_spirits_of_the_jungle") then
      tooltip_text = tooltip_text .. "\nThis faction does not use Supply Lines";
    else
      if character:character_subtype("wh2_main_def_black_ark") then
        tooltip_text = tooltip_text .. "\nBlack Arks do not contribute to the Supply Lines penalty";
      else
        tooltip_text = tooltip_text .. "\nArmy contributes at " .. (supply_factor * 100) .. "% to Supply Lines";
        if army_queued_units_cost > 0 then
          local supply_with_queued = get_army_supply_factor(character, army_queued_units_cost);
          tooltip_text = tooltip_text .. " (will be " .. (supply_with_queued * 100) .. "%)";
        end
      end
    end
  end

  zoom_component:SetTooltipText(tooltip_text, true)
end

local function set_tooltip_text_garrison_cost(cqi) -- TODO Refactor
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

local function apply_supply_lines(faction) -- TODO Refactor
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


-- LISTENERS

core:add_listener(
  "CBAC_MCTPanelOpened",
  "MctPanelOpened",
  true,
  cbac:block_mct_settings_if_required(),
  true
)

-- event army selected, show cost in tooltip
core:add_listener( -- TODO Refactor
  "JCBAC_ArmyCostTooltip",
  "CharacterSelected",
  function(context)
    return context:character():has_military_force();
  end,
  function(context)
    cbac:log("Listener JCBAC_ArmyCostTooltip has fired.")
    local current_character = context:character()
    --store the character cqi also in saved values so other unrelated events can use it
    cm:set_saved_value("cbac_last_selected_char_cqi", (current_character:command_queue_index()))
    cbac:log("Selected character's CQI: "..current_character:command_queue_index())
    if (not (cbac:get_config("mct_read_20210814"))) then
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
core:add_listener( -- TODO Refactor
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

core:add_listener( -- TODO Refactor
  "JCBAC_NormalUnitDisbandedEvent",
  "UnitDisbanded",
  function(context)
    return cm.campaign_ui_manager:is_panel_open("units_panel") and context:unit():faction():is_human();
  end,
  function(context)
    cbac:log("Listener JCBAC_NormalUnitDisbandedEvent has fired.")
    cm:callback(function()
        enforce_faction_cost_limit(cm:model():world():whose_turn_is_it())
        cbac:log("Listener JCBAC_NormalUnitDisbandedEvent has finished.")
      end, 0.1)
  end,
  true
)

core:add_listener( -- TODO Refactor
  "JCBAC_GeneralDisbandedEvent",
  "CharacterConvalescedOrKilled",
  function(context)
    return cm:char_is_mobile_general_with_army(context:character());
  end,
  function(context)
    cbac:log("Listener JCBAC_GeneralDisbandedEvent has fired.");
    cm:set_saved_value("cbac_last_selected_char_cqi", nil);
    cbac:log("Listener JCBAC_GeneralDisbandedEvent has finished.");
  end,
  true
)

core:add_listener( -- TODO Refactor
  "JCBAC_UnitMergedEvent",
  "UnitMergedAndDestroyed",
  function(context)
    return cm.campaign_ui_manager:is_panel_open("units_panel") and context:unit():faction():is_human();
  end,
  function(context)
    cbac:log("Listener JCBAC_UnitMergedEvent has fired.")
    cm:callback(function()
        enforce_faction_cost_limit(cm:model():world():whose_turn_is_it())
        cbac:log("Listener JCBAC_UnitMergedEvent has finished.")
      end, 0.1)
  end,
  true
)

--catch all clicks to refresh the army cost tooltip if the units_panel is open
--this fires also when player cancels recruitment of a unit, adds a unit to the queue etc
core:add_listener( -- TODO Refactor
  "JCBAC_ClickEvent",
  "ComponentLClickUp",
  function(context)
    return cm.campaign_ui_manager:is_panel_open("units_panel");
  end,
  function(context)
    cm:callback(function()
        local last_selected_character = cm:get_character_by_cqi(cm:get_saved_value("cbac_last_selected_char_cqi"))
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

core:add_listener(
  "JCBAC_ApplyArmyPenalties",
  "FactionTurnStart",
  function(context) return (context:faction():is_human()) end,
  function(context)
    cm:callback(function()
        enforce_faction_cost_limit(context:faction());
      end, 0.1)
  end,
  true
)

core:add_listener( -- TODO Refactor
  "JCBAC_SupplyLines",
  "FactionTurnEnd",
  function(context)
    return (context:faction():is_human())
  end,
  function(context)
    local current_faction = context:faction()
    local subculture = current_faction:subculture()
    if (cbac:get_config("supply_lines")) then
      if not (subculture == "wh_dlc03_sc_bst_beastmen" or subculture == "wh_main_sc_brt_bretonnia" or subculture == "wh2_dlc09_sc_tmb_tomb_kings" or subculture == "wh_main_sc_chs_chaos" or current_faction:name() == "wh2_dlc13_lzd_spirits_of_the_jungle") then
        apply_supply_lines(current_faction)
      end
    end
  end,
  true
)
