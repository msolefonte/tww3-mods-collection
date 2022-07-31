local cbac = {};
local config = {
  "army_limit_player" = 10500,
  "army_limit_ai" = 12000,
  "dynamic_limit" = true,
  "limit_rank" = 2,
  "limit_step" = 1000,
  "limit_deceleration" = 50,
  "hero_cap" = 2,
  "supply_lines" = false,
  "upgrade_ai_armies" = false,
  "upgrade_grace_period" = 20,
  "autolevel_ai_lords" = 3,
  "logging_enabled" = false
};

function cbac:log(str)
  if config["logging_enabled"] then
    out('CBAC ' .. str);
  end
end

function cbac:get_config(config_key)
  if get_mct then
      local mct = get_mct();

      if mct ~= nil then
          cbac:log("Loading config from MCT: " .. config_key);
          local mod_cfg = mct:get_mod_by_key("wolfy_cost_based_army_caps");
          config[config_key] = mod_cfg:get_option_by_key(config_key):get_finalized_setting();
      end
  end

  return config[config_key];
end

function cbac:block_mct_settings_if_required()
  if get_mct then
    local mct = get_mct();

    if mct ~= nil then
      local mod_cfg = mct:get_mod_by_key("wolfy_cost_based_army_caps");
      if (mod_cfg:get_option_by_key("settings_locked"):get_finalized_setting()) then
        mod_cfg:get_option_by_key("player_limit"):set_read_only(true);
        mod_cfg:get_option_by_key("ai_limit"):set_read_only(true);
        mod_cfg:get_option_by_key("dynamic_limit"):set_read_only(true);
        mod_cfg:get_option_by_key("limit_rank"):set_read_only(true);
        mod_cfg:get_option_by_key("limit_step"):set_read_only(true);
        mod_cfg:get_option_by_key("hero_cap"):set_read_only(true);
        mod_cfg:get_option_by_key("supply_lines"):set_read_only(true);
        mod_cfg:get_option_by_key("upgrade_ai_armies"):set_read_only(true);
        mod_cfg:get_option_by_key("autolevel_ai"):set_read_only(true);
      end
    end
  end
end

function cbac:get_unit_cost(unit) -- TODO Remove Hardcode
  if unit:unit_key() == "wh_dlc07_brt_cha_green_knight_0" then
    return 0;
  else
    return unit:get_unit_custom_battle_cost();
  end
end

function cbac:get_hero_count(unit) -- TODO Remove Hardcode
  if string.find(current_unit:unit_key(), "_cha_") or (current_unit:unit_key() == "wh2_dlc11_cst_inf_count_noctilus_0") or (current_unit:unit_key() == "wh2_dlc11_cst_inf_count_noctilus_1") then
    if not (current_unit:unit_key() == "wh_dlc07_brt_cha_green_knight_0" or current_unit:unit_key() == "wh_dlc06_dwf_cha_master_engineer_ghost_0" or current_unit:unit_key() == "wh_dlc06_dwf_cha_runesmith_ghost_0" or current_unit:unit_key() == "wh_dlc06_dwf_cha_thane_ghost_0" or current_unit:unit_key() == "wh_dlc06_dwf_cha_thane_ghost_1") then
      return 1;
    end
  end

  return 0;
end

function cbac:get_army_cost(character)
  if not character:has_military_force() then
    return -1;
  end

  local army_cost = 0;
  for _, unit in ipairs(character:military_force():unit_list()) do
    army_cost = army_cost + cbac:get_unit_cost(unit);
  end

  return army_cost;
end

function cbac:get_army_limit(character)
  local army_limit = cbac:get_config("army_limit_player");

  if (cbac:get_config("dynamic_limit")) then
    local lord_rank = character:rank();
    local limit_rank = cbac:get_config("limit_rank");
    local limit_step = cbac:get_config("limit_step");
    local limit_deceleration = cbac:get_config("limit_deceleration");

    local total_deceleration_factor = 0;
    local number_of_steps = (math.floor(lord_rank / limit_rank)) - 1;

    for step=1, number_of_steps, 1 do
      if (limit_deceleration * step <= limit_step) then
        total_deceleration_factor = total_deceleration_factor + (limit_deceleration * step);
      else
        total_deceleration_factor = total_deceleration_factor + limit_step;
      end
    end

    army_limit = army_limit + ((math.floor(lord_rank / limit_rank)) * limit_step) - total_deceleration_factor;
  end

  return army_limit;
end

function cbac:get_army_supply_factor(character, added_cost)
  if not character:has_military_force() then
    return -1;
  end

  local army_cost = cbac:get_army_cost(character) + added_cost;
  local army_limit = cbac:get_army_limit(character);

  local supply_factor = 1;
  if (army_point_cost / army_limit) < 0.25 then
    supply_factor = 0.25;
  elseif (army_point_cost / army_limit) < 0.5 then
    supply_factor = 0.5;
  elseif (army_point_cost / army_limit) < 0.75 then
    supply_factor = 0.75;
  end

  return supply_factor;
end

function cbac:get_army_hero_count(character)
  if not character:has_military_force() then
    return -1;
  end

  local army_hero_count = -1;
  for _, unit in ipairs(character:military_force():unit_list()) do
    army_hero_count = army_hero_count + cbac:get_hero_count(unit);
  end

  return army_hero_count;
end

function cbac:get_character_cost_string(character)
  if not character:has_military_force() then
    return "";
  end

  local character_cost_string = "\nCost values of lord/heroes: ";
  for _, unit in ipairs(character:military_force():unit_list()) do
    if string.find(unit:unit_key(), "_cha_") then
      character_cost_string = character_cost_string .. (unit:get_unit_custom_battle_cost()) .. "  ";
    end
  end

  return character_cost_string;
end

function cbac:get_garrison_cost(cqi)  -- TODO Refactor
  local garrison_cost = 0;
  for _, unit in ipairs(cm:get_military_force_by_cqi(cqi):unit_list()) do
    garrison_cost = garrison_cost + cbac:get_unit_cost(unit);
  end

  return garrison_cost;
end

function cbac:get_army_queued_units_cost()  -- TODO Refactor
  local queued_units_cost = 0;
  local current_queued_unit;

  local i = 0;
  while (current_queued_unit = find_uicomponent(core:get_ui_root(), "main_units_panel", "units", "QueuedLandUnit " .. i)) do
    current_queued_unit:SimulateMouseOn();

    local unit_info = find_uicomponent(core:get_ui_root(), "UnitInfoPopup", "tx_unit-type");
    local unit_state_text = unit_info:GetStateText();
    local unit_info_head = string.find(unit_state_text, "unit/") + 5;
    local unit_info_tail = string.find(unit_state_text, "]]") - 1;

    local queued_unit_name = string.sub(unit_state_text, unit_info_head, unit_info_tail);
    for j=1, #cbac_units_cost do -- TODO WHERE THE FUCK DOES THIS COME FROM
      if cbac_units_cost[j][1] == queued_unit_name then
        queued_units_cost = queued_units_cost + cbac_units_cost[j][2];
        break;
      end
    end

    i = i + 1;
  end

  return queued_units_cost;
end

core:add_static_object("cbac", cbac);
