****************************************************************
*Creating an Ado file for the rebound effect (supply or demand shock)
*Works for a leftward shift of demand or rightward shift of supply
****************************************************************

cap prog drop rebound
prog def rebound, rclass

syntax anything, /// yes or no 
		[weighted_average(string)] ///

global elec_dem_elas = -0.190144

************************
*Electricity Rebound
************************

if "`weighted_average'" == "no" {

	if "`anything'" == "yes" {
		local reb = 1/(1 - (${elec_dem_elas}/${elec_sup_elas}))
	}

	if ${elec_sup_elas} == 0 | ${elec_dem_elas} >= 100 {
		local reb = 0
	}

	if ${elec_sup_elas} >= 100 | ${elec_dem_elas} == 0 {
		local reb = 1
	} 
}

else {
	preserve
		import excel "${assumptions}/grid_pollution", first clear sheet("elec_share_2020")

		foreach var in "Coal" "Oil"	"Gas" "Nuclear"	"Hydro"	"Biomass" "Wind" "Solar" "Geothermal" "OtherFossil"	"OtherUnknown" {
			local `var'_share = `var'[1]
		}

		*Get weighted average supply * demand elas from MarketSim Model (https://www.boem.gov/sites/default/files/documents//MarketSim%20Model%20Documentation.pdf)

		local nodata = `Geothermal_share' + `Biomass_share' + `OtherFossil_share' + `OtherUnknown_share'

		local elec_supply_ms = (0.22 * `Oil_share' + 1.50 * `Gas_share' + 0.27 * `Coal_share' + 0.53 * `Nuclear' + 0.05 * `Hydro_share' + 0.65 * `Wind_share' + 2.03 * `Solar_share') * (1/(1 - `nodata'))
		local elec_demand_ms = (0.384 * 0.287) + (0.354 * 0.134) + (0.260 * 0.125) // demand shares from https://www.eia.gov/energyexplained/electricity/use-of-electricity.php

		local reb = 1/(1 - (-1 * `elec_demand_ms'/`elec_supply_ms'))
	
	restore
}

if "`anything'" == "no" {
	local reb = 1
}
	
************************
*Natural Gas Rebound
************************
local ng_supply_elas = 1.50 // same value used for above calculation
local ng_demand_elas = -0.20 // Middle of range from https://www.nber.org/papers/w24295
local ng_reb = 1/(1 - (`ng_demand_elas'/`ng_supply_elas'))

return scalar r = `reb'
return scalar r_ng = `ng_reb'
end
