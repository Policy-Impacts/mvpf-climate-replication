*************************************************************
/* 0. Program: ETS                         */
*************************************************************

/* 
Colmer, Jonathan, Ralf Martin, Mirabelle Muuls, and Ulrich J. Wagner. 2024.
"Does Pricing Carbon Mitigate Climate Change? Firm-Level Evidence from the European Trading System"
Review of Economic Studies 00: 1--36. 
*/

*****************************
/* 1. Estimates from Paper */
*****************************

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
if "`bootstrap'" == "pe_ci" {
	preserve
		use "${code_files}/2b_causal_estimates_draws/${folder_name}/${ts_causal_draws}/${name}_ci_pe.dta", clear
		
levelsof estimate, local(estimates)


		foreach est in `estimates' {
			sum ${val} if estimate == "`est'"
			local `est' = r(mean)
		}
	restore 
}

 
if "${spec_type}" == "baseline" | "${spec_type}" == "baseline_gen" {
	
	local dollar_year = ${policy_year}
	global MVPF_type = "marginal"
	
}
if "${spec_type}" == "current"{
	
	local dollar_year = ${today_year}
	global MVPF_type = "marginal"
	
}


****************************************************
/* 2. Price, Allowance, and Pollution Data */
****************************************************
preserve

	import excel "${policy_assumptions}", first clear sheet("ETS_C&T_data")
	
	gen real_permit_price = .
	levelsof(year), local(year_loop)
	foreach y of local year_loop {
		
		replace real_permit_price = annual_price * (${cpi_`dollar_year'}/${cpi_`y'}) if year == `y'
		
	}
	
	qui sum real_permit_price [aw = allowances_auctioned] if inrange(year, 2005, ${policy_year})
		local baseline_price = r(mean)


	if "${spec_type}" == "baseline" | "${spec_type}" == "baseline_gen" {
		
		local permit_price = `baseline_price'
		
	}

	if "${spec_type}" == "current"{
		
		qui sum real_permit_price if year == `dollar_year'
			local permit_price = r(mean)
		
	}

	local dp_dlogq = `baseline_price' / `ets_CO2_abated_pct'

****************************************************
/* 3. Import Social Costs and Marginal Damages */
****************************************************
	gen sc_CO2 = .
	foreach y of local year_loop {
		
		replace sc_CO2 = (${sc_CO2_`y'} * (${cpi_`dollar_year'} / ${cpi_${sc_dollar_year}})) if year == `y'
		// Constant dollars, varying social cost of carbon.
		
	}

	if "${spec_type}" == "baseline" {
		
		qui sum sc_CO2 [aw = allowances_auctioned] if inrange(year, 2005, ${policy_year}) 
			local social_cost_CO2 = r(mean)
		
	}

	if "${spec_type}" == "current" {
		
		qui sum sc_CO2 [aw = allowances_auctioned] if year == `dollar_year'
			local social_cost_CO2 = r(mean)
		
	}

restore

****************************************************
/* 4. Cost Calculations */
****************************************************
if "${MVPF_type}" == "marginal" {
	
	local permit_revenue = `dp_dlogq'
	local fiscal_externality = -`permit_price'
	
}

local pollutants_list CO2

****************************************************
/* 5. WTP Calculations */
****************************************************

if "${MVPF_type}" == "marginal" {
	
	* Producers/Firms WTP (M), +
	local wtp_permits_grandfathered = 0
	local wtp_permits_auctioned = `dp_dlogq'
		local wtp_permits = `wtp_permits_grandfathered' + `wtp_permits_auctioned'
		assert `wtp_permits' > 0

	local wtp_abatement = 0 // Envelopes out. 
	
	local wtp_producers = `wtp_permits' + `wtp_abatement'
		
	* Society WTP (M), - 
	local wtp_soc = 0	
	foreach p of local pollutants_list {
		
		if "`p'" == "CO2" {
			local wtp_`p' = -`social_cost_`p''
		}
		
		assert `wtp_`p'' < 0 // Soc. WTP negative for revenue-raising policies.
		
		local wtp_soc = `wtp_soc' + `wtp_`p''
			assert `wtp_soc' < 0
	
	}
	
	local wtp_soc_l = 0
	local wtp_soc_g = `wtp_CO2'
		assert round(`wtp_soc_g' + `wtp_soc_l', 0.00001) == round(`wtp_soc', 0.00001)
	
	local total_WTP = `wtp_producers' + (`wtp_soc'*(1 - (${USShareFutureSSC} * ${USShareGovtFutureSCC})))

}

local WTP_USPres = `wtp_soc_l'
	assert `WTP_USPres' == 0
local WTP_USFut = `wtp_soc_g' * (${USShareFutureSSC} - (${USShareFutureSSC} * ${USShareGovtFutureSCC}))
local WTP_RoW = (`wtp_soc_g' * (1 - ${USShareFutureSSC})) + `wtp_producers'

local fiscal_externality_lr = (`wtp_soc_g') * (${USShareFutureSSC} * ${USShareGovtFutureSCC}) * -1
	assert `fiscal_externality_lr' >= 0 
	
local total_cost = `permit_revenue' + `fiscal_externality' + `fiscal_externality_lr'
	

****************************************************
/* 6. Calculate MVPF (and Cost Effectiveness Metrics) */
****************************************************
local MVPF = `total_WTP'/`total_cost' // finite MVPF
	assert round((`WTP_USPres' + `WTP_USFut' + `WTP_RoW')/`total_cost', 0.01) == round(`MVPF', 0.01)


di in red `total_WTP'
di in red `total_cost'
di in red `MVPF'

di in red `WTP_RoW'
di in red `WTP_USFut'
di in red `WTP_USPres'

di in red `wtp_permits'

****************************************************
/* 7. Save Results and Waterfall Components */
****************************************************
global normalize_`1' = 0

global MVPF_`1' = `MVPF'
global WTP_USPres_`1' = `WTP_USPres'
global WTP_USFut_`1'  = `WTP_USFut'
global WTP_RoW_`1'    = `WTP_RoW'

global cost_`1' = `total_cost'
global program_cost_`1' = `permit_revenue'
	
global WTP_`1' = `total_WTP'

global wtp_soc_`1' = `wtp_soc_g' * (1 - (${USShareFutureSSC} * ${USShareGovtFutureSCC}))
global wtp_soc_g_`1'  = `wtp_CO2' * (1 - (${USShareFutureSSC} * ${USShareGovtFutureSCC}))

global dp_dq_`1' = `dp_dlogq'
global wtp_abatement_`1' = `wtp_abatement'
global wtp_permits_`1' = `wtp_permits'

global fisc_ext_t_`1' = `fiscal_externality'
global fisc_ext_s_`1' = 0
global fisc_ext_lr_`1' = `fiscal_externality_lr'

global semie_`1' = `dp_dlogq'
global permit_price_`1' = `permit_price'