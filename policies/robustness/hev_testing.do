/*
*************************************************************************************
/*                         0. Program: HEV Testing                    */
*************************************************************************************

*/

display `"All the arguments, as typed by the user, are: `0'"'


local hev_cf = "${hev_cf}"
if "`hev_cf'" == "muehl" | "`hev_cf'" == "new_car" {
    local veh_lifespan_type = "car"
}
    

********************************
/* 1. Pull Global Assumptions */
********************************
* Project wide globals
local discount = ${discount_rate}

*********************************
/* 2. Estimates from Paper */
*********************************
/* Import estimates from paper, giving option for corrected estimates.
When bootstrap!=yes import point estimates for causal estimates.
When bootstrap==yes import a particular draw for the causal estimates. */

if "`1'" != "" global name = "`1'"
local bootstrap = "`2'"
if "`3'" != "" global folder_name = "`3'"
if "`bootstrap'" == "yes" {
*	if ${draw_number} ==1 {
        preserve
            use "${code_files}/2b_causal_estimates_draws/${folder_name}/${ts_causal_draws}/${name}.dta", clear
            qui ds draw_number, not 
            global estimates_${name} = r(varlist)
            
            mkmat ${estimates_${name}}, matrix(draws_${name}) rownames(draw_number)
        restore
*	}
    local ests ${estimates_${name}}
    foreach var in `ests' {
        matrix temp = draws_${name}["${draw_number}", "`var'"]
        local `var' = temp[1,1]
    }
}
if "`bootstrap'" == "no" {
    preserve
            
        qui import excel "${code_files}/2a_causal_estimates_papers/${folder_name}/${name}.xlsx", clear sheet("wrapper_ready") firstrow            
        
        levelsof estimate, local(estimates)




        foreach est in `estimates' {
            su pe if estimate == "`est'"
            local `est' = r(mean)
        }
    restore
}

local farmer_theta = -0.421

****************************************************
/* 3. Set local assumptions unique to this policy */
****************************************************

global dollar_year = ${current_year}

global run_year = 2020
local dollar_year = ${dollar_year}

****************************************************
/* 3a. Hybrid and Counterfactual Vehicle Fuel Economy Data */
****************************************************
preserve
    use "${assumptions}/evs/processed/hev_data", clear
    ** cleanest counterfactual
    keep if year == ${run_year}
    qui sum mpg_cf
    local hev_cf_mpg = r(mean)
    qui sum mpg
    local hev_mpg = r(mean)
restore

preserve
    qui import excel "${policy_assumptions}", first clear sheet("fuel_economy_1975_2022")
    qui sum RealWorldMPG if RegulatoryClass == "All" & ModelYear == "2020"
    local base_mpg2020 = r(mean)
restore
****************************************************
/* 3b. Gas Price and Tax Data */
****************************************************


preserve
    use "${gas_fleet_emissions}/fleet_year_final", clear
    keep if fleet_year==${run_year}
    
    qui ds *_gal
    foreach var in `r(varlist)' {
        replace `var' = `var'/1000000
        * Converting from grams per gallon to metric tons per gallon.
        qui sum `var'
        local `var' = r(mean)
    }
restore

preserve
    use "${user_specific_assumptions}/files_v${user_name}/Gasoline Prices, Markups, and Taxes/gas_data_final", clear
            
    gen real_gas_price = gas_price*(${cpi_${dollar_year}} / index) 
    gen real_tax_rate = avg_tax_rate*(${cpi_${dollar_year}} / index)
    gen real_markup = markup * (${cpi_${dollar_year}} / index)
            
    keep if year==${run_year}
        
    local consumer_price = real_gas_price 
    * Consumer price = includes taxes. 
    local tax_rate = real_tax_rate
    local markup = real_markup

restore

****************************************************
/* 3c. Hybrid Specific Assumptions */
****************************************************
preserve
    qui import excel "${policy_assumptions}", first clear sheet("evs") // same as BEVs
        
    levelsof Parameter, local(levels)
    foreach val of local levels {
        qui sum Estimate if Parameter == "`val'"
        global `val' = `r(mean)'
    }
        
    local val_given = ${val_given}
    local lifetime = ${vehicle_`veh_lifespan_type'_lifetime}
restore

****************************************************
/* 3d. HEV Battery Capacity Data */
****************************************************
preserve
    use "${assumptions}/evs/processed/hev_data", clear
    forvalues y = 2000(1)2006{
        qui sum batt_cap if year == `y'
        local batt_cap`y' = r(mean)
        qui sum batt_cap_N if year == `y'
        local total_sales`y' = r(mean)
    }
    keep if year == ${run_year}
    qui sum batt_cap
    local batt_cap = r(mean)
restore


****************************************************
/*                  3e. HEV Price Data            */
****************************************************
preserve
    use "${assumptions}/evs/processed/hev_data", clear
    keep if year == ${run_year}
    qui sum msrp
    local msrp = r(mean) * (${cpi_`dollar_year'} / ${cpi_${run_year}})
restore

****************************************************
/* 3g. EV and ICE Age-State-Level VMT Data */
****************************************************
local ub = `lifetime'

preserve
    
    use "${assumptions}/evs/processed/ev_vmt_by_age", clear
    local ub = `lifetime'
    duplicates drop age vmt, force
    sort age
    forvalues y = 1(1)`ub'{
        local hev_miles_traveled`y' = vmt[`y']
    }

restore

preserve

    use "${assumptions}/evs/processed/ice_vmt_by_age", clear
    duplicates drop age vmt, force
    sort age
    forvalues y = 1(1)`ub'{
        local ice_miles_traveled`y' = vmt[`y']
    }

restore

** fixing HEVs vmt at same levels as ICE
forvalues y = 1(1)`ub'{
    local hev_miles_traveled`y' = `ice_miles_traveled`y''
}

****************************************************
/* 3g. Cost Curve */
****************************************************
preserve
    use "${assumptions}/evs/processed/battery_sales_combined", clear
    keep if year == `dollar_year'
    qui sum cum_sales
    local cum_sales = r(mean)
    qui sum marg_sales
    local marg_sales = r(mean)		
restore

preserve
    use "${assumptions}/evs/processed/all_cells_batt_costs_combined", clear

    keep if year == `dollar_year'
    qui sum prod_cost_2018
    local prod_cost = r(mean)
    local batt_per_kwh_cost = `prod_cost'

restore

****************************************************
/* 3h. Subsidy Levels */
****************************************************
** Federal Subsidy

local elas_avg_fed_subsidy = 1073 // Table 3
local avg_fed_subsidy = 0
local avg_state_subsidy = 0 // no states offer normal hybrid subsidies in 2020

****************************************************
/* 4. Set local assumptions unique to this policy */
****************************************************
** Cost assumptions:
* Program costs - US$

local avg_subsidy = `avg_state_subsidy'

****************************************************
/*          5. Intermediate Calculations          */
****************************************************
local epsilon = -${feed_in_elas}
local net_msrp = `msrp' - `avg_subsidy' - `avg_fed_subsidy'
local semie = -`epsilon' / `net_msrp'

local beh_response = `semie'

* oil producers
local producer_price = `consumer_price' - `tax_rate'
local producer_mc = `producer_price' - `markup'

* no utility company producer surplus for HEVs

**************************
/* 6. Cost Calculations  */
**************************

* Program cost
local program_cost = 1

* no utility fiscal externality for HEVs


local gas_fisc_ext = -`beh_response' * (${hybrid_cf_gas_fisc_ext_`dollar_year'} - ${`hev_cf'_cf_gas_fisc_ext_`dollar_year'})
local fed_fisc_ext = `beh_response' * `avg_fed_subsidy'

local beh_fisc_ext = `semie' * `avg_subsidy'

local total_cost0 = `program_cost' + `gas_fisc_ext' + `fed_fisc_ext' + `beh_fisc_ext'


*************************
/* 7. WTP Calculations */
*************************

* consumers
local wtp_cons = 1


local wtp_prod_s = 0

if "${value_profits}" == "yes"{

    * oil producers
    local wtp_prod_s = `beh_response' * (${hybrid_wtp_prod_s_`dollar_year'} - ${`hev_cf'_wtp_prod_s_`dollar_year'}) 
}

*no utility producer surplus for HEVs
** take out the corporate effective tax rate
local total_wtp_prod_s = `wtp_prod_s'
local wtp_prod_s = `total_wtp_prod_s' * (1 - 0.21)
local gas_corp_fisc_e = `total_wtp_prod_s' * 0.21

local wtp_private = `wtp_cons' + `wtp_prod_s'


* learning by doing
local prod_cost = `prod_cost' * (${cpi_`dollar_year'} / ${cpi_2018}) // data is in 2018USD



local batt_cost = `prod_cost' * `batt_cap'

local batt_frac = `batt_cost' / `msrp'

local fixed_cost_frac = 1 - `batt_frac'

local car_theta = `farmer_theta' * `batt_frac'




** Externality and WTP for driving a hybrid vehicle
local total_hev_damages_glob = ${hybrid_cf_damages_glob_`dollar_year'} - ${yes_hev_rbd_glob_`dollar_year'}

local wtp_yes_hev_local = -`beh_response' * ${hybrid_cf_damages_loc_`dollar_year'} // with rebound
local wtp_yes_hev_rbd_loc = -`beh_response' * ${yes_hev_rbd_loc_`dollar_year'}
local wtp_yes_hev_loc_no_rbd = `wtp_yes_hev_local' - `wtp_yes_hev_rbd_loc' // for Latex

local wtp_yes_hev_global_tot = -`beh_response' * `total_hev_damages_glob' // no rebound
local wtp_yes_hev_rbd_glob_tot = -`beh_response' * ${yes_hev_rbd_glob_`dollar_year'}

local wtp_yes_hev_g = `wtp_yes_hev_global_tot' * ((1 - ${USShareFutureSSC}) + ${USShareFutureSSC} * (1 - ${USShareGovtFutureSCC}))
local wtp_yes_hev_rbd_glob = `wtp_yes_hev_rbd_glob_tot' * ((1 - ${USShareFutureSSC}) + ${USShareFutureSSC} * (1 - ${USShareGovtFutureSCC}))

local q_carbon_yes_hev = -`beh_response' * ${hybrid_cf_carbon_`dollar_year'}
local q_carbon_yes_hev_mck = ${hybrid_cf_carbon_`dollar_year'}
local wtp_soc_rbd = `wtp_yes_hev_rbd_glob' + `wtp_yes_hev_rbd_loc'


local yes_hev_local_ext = `wtp_yes_hev_local' / `beh_response'
local yes_hev_global_ext_tot = `wtp_yes_hev_global_tot' / `beh_response'
local wtp_yes_hev = `wtp_yes_hev_loc_no_rbd' + `wtp_yes_hev_g'


local yes_hev_ext = `wtp_yes_hev' / `beh_response'

** Externality and WTP for driving an ICE vehicle

local wtp_no_ice_local = `beh_response' * ${`hev_cf'_cf_damages_loc_`dollar_year'}
local wtp_no_ice_global_tot = `beh_response' * ${`hev_cf'_cf_damages_glob_`dollar_year'}
local wtp_no_ice_g = `wtp_no_ice_global_tot' * ((1 - ${USShareFutureSSC}) + ${USShareFutureSSC} * (1 - ${USShareGovtFutureSCC}))

local q_carbon_no_ice = `beh_response' * ${`hev_cf'_cf_carbon_`dollar_year'}
local q_carbon_no_ice_mck = ${`hev_cf'_cf_carbon_`dollar_year'}

local no_ice_local_ext = `wtp_no_ice_local' / `beh_response'
local no_ice_global_ext_tot = `wtp_no_ice_global_tot' / `beh_response'

local wtp_no_ice = `wtp_no_ice_local' + `wtp_no_ice_g'


local no_ice_ext = `wtp_no_ice' / `beh_response'


*** Battery manufacturing emissions

local relevant_scc = ${sc_CO2_`dollar_year'}

local batt_emissions = 214 + 20 // from Table 9 of Pipitone et al. (2021)

local batt_man_ext = `batt_emissions' * 0.001 * `beh_response' * `relevant_scc' * ((1 - ${USShareFutureSSC}) + ${USShareFutureSSC} * (1 - ${USShareGovtFutureSCC}))
local batt_man_ext_tot = `batt_emissions' * 0.001 * `beh_response' * `relevant_scc'

local wtp_soc = `wtp_yes_hev' + `wtp_no_ice' - `batt_man_ext'
local wtp_glob = `wtp_yes_hev_g' + `wtp_no_ice_g' - `batt_man_ext'
local wtp_loc = `wtp_yes_hev_loc_no_rbd' + `wtp_no_ice_local'


local local_enviro_ext = (`wtp_no_ice_local' + `wtp_yes_hev_local') / `beh_response'
local global_enviro_ext_tot = (`wtp_no_ice_global_tot' + `wtp_yes_hev_global_tot' - `batt_man_ext_tot') / `beh_response'

local enviro_ext = `local_enviro_ext' + `global_enviro_ext_tot'

local prod_cost = `prod_cost' * `batt_cap' // cost of a battery in a car as opposed to cost per kWh

* learning-by-doing

*temporary solution -> if bootstrap gets a positive elasticity, hardcode epsilon
if `epsilon' > 0{
    local epsilon = -0.001
}


** --------------------- COST CURVE --------------------- **
cost_curve_masterfile, demand_elas(`epsilon') discount_rate(`discount') farmer(`farmer_theta') fcr(`fixed_cost_frac') curr_prod(`marg_sales') cum_prod(`cum_sales') price(`net_msrp') enviro(constant_`enviro_ext')
local dyn_enviro = `r(enviro_mvpf)'

cost_curve_masterfile, demand_elas(`epsilon') discount_rate(`discount') farmer(`farmer_theta') fcr(`fixed_cost_frac') curr_prod(`marg_sales') cum_prod(`cum_sales') price(`net_msrp') enviro(constant_`local_enviro_ext')
local dyn_enviro_local = `r(enviro_mvpf)'

cost_curve_masterfile, demand_elas(`epsilon') discount_rate(`discount') farmer(`farmer_theta') fcr(`fixed_cost_frac') curr_prod(`marg_sales') cum_prod(`cum_sales') price(`net_msrp') enviro(constant_`global_enviro_ext_tot')
local dyn_enviro_global_tot = `r(enviro_mvpf)'
local dyn_enviro_global = `dyn_enviro_global_tot' * ((1 - ${USShareFutureSSC}) + ${USShareFutureSSC} * (1 - ${USShareGovtFutureSCC}))

local dyn_price = `r(cost_mvpf)'
local cost_wtp = `r(cost_mvpf)' * `program_cost'
local env_cost_wtp = `dyn_enviro' * `program_cost' // same as local plus global_tot
local env_cost_wtp_l = `dyn_enviro_local' * `program_cost'
local env_cost_wtp_global_tot = `dyn_enviro_global_tot' * `program_cost'
local env_cost_wtp_g = `dyn_enviro_global' * `program_cost'

local env_cost_wtp = `env_cost_wtp_l' + `env_cost_wtp_g' // switching to not include the piece of the global dynamic enviro that will go to the FE

local q_carbon = `q_carbon_no_ice' + `q_carbon_yes_hev'
local q_carbon_no = `q_carbon'
local q_carbon_cost_curve = `dyn_enviro_global_tot' / ${sc_CO2_`dollar_year'}
local q_carbon_cost_curve_mck = `q_carbon_cost_curve' / `beh_response'
local q_carbon_mck = `q_carbon_no_ice_mck' + `q_carbon_yes_hev_mck'
local q_carbon = `q_carbon' + `q_carbon_cost_curve'


********** Long-Run Fiscal Externality **********

local fisc_ext_lr = -1 * (`wtp_no_ice_global_tot' + `wtp_yes_hev_global_tot' + `env_cost_wtp_global_tot' + `batt_man_ext_tot') * ${USShareFutureSSC} * ${USShareGovtFutureSCC}
local total_cost = `total_cost0' + `fisc_ext_lr' + `gas_corp_fisc_e'

*************************************************

// Quick Decomposition

/* Assumptions:

    - wtp_private, cost_wtp -> US Present
    - wtp_soc, env_cost_wtp -> US Future & Rest of the World

*/

* Total WTP
local WTP = `wtp_private' + `wtp_soc' + `wtp_soc_rbd' // not including learning-by-doing
local WTP_cc = `WTP' + `cost_wtp' + `env_cost_wtp'

local WTP_USPres = `wtp_private' + `wtp_yes_hev_local' + `wtp_no_ice_local' + `env_cost_wtp_l'
local WTP_USFut = (${USShareFutureSSC} * (1 - ${USShareGovtFutureSCC})) * (`wtp_yes_hev_global_tot' + `wtp_no_ice_global_tot' + `env_cost_wtp_global_tot') + 0.1 * `cost_wtp'
local WTP_RoW = (1 - ${USShareFutureSSC}) * (`wtp_yes_hev_global_tot' + `wtp_no_ice_global_tot' + `env_cost_wtp_global_tot') + 0.9 * `cost_wtp'

**************************
/* 8. MVPF Calculations */
**************************

local MVPF = `WTP_cc' / `total_cost'
local MVPF_no_cc = `WTP' / `total_cost'

global MVPF_hev_testing `MVPF' 
global cost_hev_testing `total_cost' 
global WTP_cc_hev_testing `WTP_cc'