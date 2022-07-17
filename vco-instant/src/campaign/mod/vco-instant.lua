local vco = core:get_static_object("vco");
local missions = {
  [[
		mission
  	{
  		victory_type vco_victory_type_long;
  		key wh_main_long_victory;
  		issuer CLAN_ELDERS;
  		primary_objectives_and_payload
  		{
  			objective
  			{
  				type OWN_N_UNITS;
  				total 1;
  			}
  			payload
  			{
  				game_victory;
  			}
  		}
  	}
  ]]
};

cm:add_first_tick_callback(
  function()
    vco:trigger_missions_for_current_faction(missions);
  end
);
