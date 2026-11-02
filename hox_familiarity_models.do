/*==========================================================================
  PEER EFFECT IN COMPETITIVE RUNNING — HOX2007SCH MODELS
  Moderator: Repeated Co-Competition (Familiarity)
  Task Complexity: Race Distance

  Outcome:    deviation_speed  (current speed − athlete's prior PB)
  Peer:       opponents' PAST performance as of current competition
              (past_perf_k = mean comp_max over strictly-prior meets)
              Pre-determined by start_date/end_date; no simultaneity
  Familiarity: avg number of prior co-races with current opponents
  Task complexity: racetype (sprint / middle / long)

  HOX2007SCH models:
    1. Linear-in-means        avg opponent quality
    2. Bad Apple              min opponent quality
    3. Shining Light          max opponent quality
    4. Invidious Comparison   focal runner's rank in field
    5. Boutique               fraction of opponents similar to self
    6/7. Focus / Rainbow      field SD (Focus: low SD helps; Rainbow: high SD helps)
    8. Single Crossing        fast runners benefit more from fast peers

  FEs:     athlete_id  +  track_event_id#year
  Cluster: athlete_id

  Graph style: Kieran Healy — white background, Okabe-Ito palette,
               ribbon CIs, no chartjunk, small multiples for comparisons
==========================================================================*/

clear all
set more off

*---------------------------------------------------------------------------
* 0. PATHS AND PACKAGES
*---------------------------------------------------------------------------
global root "C:\Users\mahya\OneDrive - Simon Fraser University (1sfu)\Desktop\Peer effect in competitive runners"
cd "$root"
cap mkdir "$root/peer_effect_output"

foreach pkg in reghdfe ftools rangestat coefplot estout plottig {
    capture which `pkg'
    if _rc ssc install `pkg', replace
}

* Okabe-Ito colorblind-safe palette
global c_blue   "0 114 178"
global c_orange "230 159 0"
global c_green  "0 158 115"
global c_red    "213 94 0"
global c_purple "204 121 167"
global c_lblue  "86 180 233"

* Shared graph base options
capture which plottig
if !_rc global gscheme "scheme(plottig)"
else     global gscheme "scheme(s1color)"

global gbase "graphregion(color(white) fcolor(white)) plotregion(color(white)) legend(region(lcolor(none)))"

*===========================================================================
* SECTION 1  FAMILIARITY VARIABLE
* peer_data_ready already has opp_id_k (opponent IDs) per race.
* Strategy:
*   (a) Collapse to one row per (athlete, competition, eventid)
*   (b) Reshape opp_id_k to long → one row per (focal, comp, eventid, opp)
*   (c) Sort by (focal, opp, eventid, start_date): running count = n_prior
*   (d) Aggregate back: avg_n_prior = mean prior co-races with current field
*===========================================================================

use "$root/peer_data_ready.dta", clear

*--- discover K (number of opponent columns) --------------------------------
ds opp_id_*
local K : word count `r(varlist)'
display as text "Max opponents per race: `K'"

preserve

    bysort athlete_id competition_id eventid: keep if _n == 1
    keep athlete_id competition_id eventid start_date end_date opp_id_*

    *--- reshape to long ---------------------------------------------------
    reshape long opp_id_, ///
        i(athlete_id competition_id eventid start_date end_date) j(opp_idx)
    rename opp_id_ opp_id
    drop if missing(opp_id)
    drop opp_idx

    *--- running count of prior co-races per (focal, opp, eventid) pair ----
    sort athlete_id opp_id eventid start_date competition_id
    bysort athlete_id opp_id eventid (start_date competition_id): ///
        gen int n_prior_coraces = _n - 1
    * 0 = first time meeting this opponent in this event type

    *--- aggregate to (focal, comp, eventid) level -------------------------
    bysort athlete_id competition_id eventid: ///
        egen double avg_n_prior = mean(n_prior_coraces)
    bysort athlete_id competition_id eventid: ///
        egen int n_opp_familiar = total(n_prior_coraces >= 1)

    display as text _newline "=== Distribution of avg_n_prior (prior co-races) ==="
    sum avg_n_prior, detail

    keep athlete_id competition_id eventid avg_n_prior n_opp_familiar
    duplicates drop
    tempfile familiarity
    save `familiarity'

restore

merge m:1 athlete_id competition_id eventid using `familiarity', nogen
label var avg_n_prior    "Mean prior co-races with current opponents (same eventid)"
label var n_opp_familiar "Number of current opponents faced ≥1 time before"

*===========================================================================
* SECTION 2  PEER QUALITY VARIABLES FROM PAST PERFORMANCE
* past_perf_k = opponent k's mean comp_max over strictly-prior meets
* Pre-determined (end_date of prior comp < start_date of current): CLEAN
*===========================================================================

ds past_perf_*
local pp_vars `r(varlist)'

*--- distributional measures -----------------------------------------------
egen double opp_mean_past = rowmean(`pp_vars')   // Linear-in-means
egen double opp_max_past  = rowmax(`pp_vars')    // Shining Light: best opponent
egen double opp_min_past  = rowmin(`pp_vars')    // Bad Apple: worst opponent
egen double opp_sd_past   = rowsd(`pp_vars')     // Focus / Rainbow: field spread

label var opp_mean_past "Mean opponent prior avg speed — Linear-in-means"
label var opp_max_past  "Best opponent's prior avg speed — Shining Light"
label var opp_min_past  "Worst opponent's prior avg speed — Bad Apple"
label var opp_sd_past   "SD of opponents' prior avg speed — Focus / Rainbow"

*--- Boutique: share of opponents within 0.2 m/s of focal's prior best ----
local delta = 0.2

gen double _n_sim = 0
gen double _n_val = 0
forvalues k = 1/`K' {
    capture confirm variable past_perf_`k'
    if !_rc {
        replace _n_sim = _n_sim + (!missing(past_perf_`k') & abs(past_perf_`k' - max_prev) <= `delta')
        replace _n_val = _n_val + !missing(past_perf_`k')
    }
}
gen double frac_similar = _n_sim / _n_val if _n_val > 0
drop _n_sim _n_val
label var frac_similar "Share of opponents within ±0.2 m/s of focal's prior best — Boutique"

*--- Invidious Comparison: focal's normalized rank in field (past quality) -
gen double _n_bet = 0
gen double _n_val = 0
forvalues k = 1/`K' {
    capture confirm variable past_perf_`k'
    if !_rc {
        replace _n_bet = _n_bet + (!missing(past_perf_`k') & !missing(max_prev) & past_perf_`k' > max_prev)
        replace _n_val = _n_val + !missing(past_perf_`k')
    }
}
gen double rank_in_field = _n_bet / _n_val if _n_val > 0
drop _n_bet _n_val
label var rank_in_field "Normalized rank (0=fastest in field, 1=slowest) — Invidious Comparison"

*--- Single Crossing: own quality decile ----------------------------------
capture confirm variable rank
if _rc {
    bysort athlete_id track_event_id: egen _ob = max(speed)
    bysort track_event_id: xtile rank = _ob if !missing(_ob), n(10)
    bysort athlete_id track_event_id: ereplace rank = max(rank)
    drop _ob
}
label var rank "Runner quality decile in event type (10=fastest)"

*===========================================================================
* SECTION 3  STANDARDIZE PEER VARIABLES AND BUILD CONTROLS
*===========================================================================

foreach v in opp_mean_past opp_max_past opp_min_past opp_sd_past ///
             frac_similar rank_in_field avg_n_prior {
    sum `v', meanonly
    local m = r(mean)
    local s = r(sd)
    if `s' > 0 {
        gen double z_`v' = (`v' - `m') / `s'
        label var z_`v' "Std. `v'"
    }
}

*--- controls and FE identifiers ------------------------------------------
capture confirm variable is_home_race
if _rc gen byte is_home_race = (Nationality_code == country_code)

gen byte is_final = (race == 3) if !missing(race)

*--- task complexity: distance categories ---------------------------------
capture confirm variable racetype
if _rc {
    gen byte racetype = 1 if race_distance_meters <= 400
    replace  racetype = 2 if inrange(race_distance_meters, 500, 2000)
    replace  racetype = 3 if race_distance_meters > 2000 & !missing(race_distance_meters)
}
label define rt_lbl 1 "Sprint (≤400m)" 2 "Middle (500–2000m)" 3 "Long (>2000m)"
label values racetype rt_lbl

*--- familiarity bins -------------------------------------------------------
gen byte fam_bin = 0 if avg_n_prior == 0
replace  fam_bin = 1 if avg_n_prior >  0 & avg_n_prior <= 1
replace  fam_bin = 2 if avg_n_prior >  1 & avg_n_prior <= 3
replace  fam_bin = 3 if avg_n_prior >  3 & avg_n_prior <= 6
replace  fam_bin = 4 if avg_n_prior >  6 & !missing(avg_n_prior)

label define fam_lbl 0 "Never" 1 "1×" 2 "2–3×" 3 "4–6×" 4 "7+×"
label values fam_bin fam_lbl
label var fam_bin "Prior co-races with current field (binned)"
tab fam_bin, missing

*===========================================================================
* SECTION 4  ANALYSIS SAMPLE
*===========================================================================

drop if missing(deviation_speed)
drop if missing(opp_mean_past)
drop if missing(fam_bin)
drop if missing(racetype)
drop if missing(track_event_id)
drop if missing(year)

count
display as text "Analysis sample: " r(N) " observations"

global FEs      "athlete_id track_event_id#year"
global controls "c.temp0##c.temp0 north_wind east_wind is_home_race is_final"
global cluster  "athlete_id"

*===========================================================================
* SECTION 5  HOX2007SCH REGRESSIONS
*
* All models: OLS with reghdfe
* Peer variable = PAST opponent quality (pre-determined, no endogeneity)
* Key test: does peer effect (β) vary with familiarity (fam_bin)?
* Cross-cut by racetype (task complexity)
*===========================================================================

*---------------------------------------------------------------------------
* MODEL 1: Linear-in-means × familiarity
* β on z_opp_mean_past: does average field quality lift performance?
* β on interaction: does this effect grow or shrink with familiarity?
*---------------------------------------------------------------------------
reghdfe deviation_speed ///
    c.z_opp_mean_past##ib0.fam_bin ///
    $controls, ///
    absorb($FEs) vce(cluster $cluster)
estimates store M1_linear

*---------------------------------------------------------------------------
* MODEL 2: Bad Apple × familiarity
* β<0 on z_opp_min_past: a weak opponent wrecks pacing for everyone
*---------------------------------------------------------------------------
reghdfe deviation_speed ///
    c.z_opp_min_past##ib0.fam_bin ///
    $controls, ///
    absorb($FEs) vce(cluster $cluster)
estimates store M2_badapple

*---------------------------------------------------------------------------
* MODEL 3: Shining Light × familiarity
* β>0 on z_opp_max_past: a star opponent pulls the field faster
*---------------------------------------------------------------------------
reghdfe deviation_speed ///
    c.z_opp_max_past##ib0.fam_bin ///
    $controls, ///
    absorb($FEs) vce(cluster $cluster)
estimates store M3_shining

*---------------------------------------------------------------------------
* MODEL 4: Invidious Comparison × familiarity
* β<0 on z_rank_in_field: being outclassed (higher rank_norm) depresses perf
*---------------------------------------------------------------------------
reghdfe deviation_speed ///
    c.z_rank_in_field##ib0.fam_bin ///
    $controls, ///
    absorb($FEs) vce(cluster $cluster)
estimates store M4_invidious

*---------------------------------------------------------------------------
* MODEL 5: Boutique × familiarity
* β>0 on z_frac_similar: similar-quality field → pace groups → better times
*---------------------------------------------------------------------------
reghdfe deviation_speed ///
    c.z_frac_similar##ib0.fam_bin ///
    $controls, ///
    absorb($FEs) vce(cluster $cluster)
estimates store M5_boutique

*---------------------------------------------------------------------------
* MODEL 6/7: Focus vs Rainbow × familiarity
* Focus: β<0 (high SD hurts — disorganised pace)
* Rainbow: β>0 (high SD helps — something for everyone)
*---------------------------------------------------------------------------
reghdfe deviation_speed ///
    c.z_opp_sd_past##ib0.fam_bin ///
    $controls, ///
    absorb($FEs) vce(cluster $cluster)
estimates store M67_focusrainbow

*---------------------------------------------------------------------------
* MODEL 8: Single Crossing
* Interaction: top runners (high rank decile) benefit more from good peers
* β>0 on z_opp_mean_past#c.rank supports Single Crossing
*---------------------------------------------------------------------------
reghdfe deviation_speed ///
    c.z_opp_mean_past##c.rank ///
    c.z_opp_mean_past##ib0.fam_bin ///
    $controls, ///
    absorb($FEs) vce(cluster $cluster)
estimates store M8_singlecross

*---------------------------------------------------------------------------
* TASK COMPLEXITY: Model 1 separately by race distance
*---------------------------------------------------------------------------
forvalues rt = 1/3 {
    local lbl1 "Sprint (≤400m)"
    local lbl2 "Middle (500–2000m)"
    local lbl3 "Long (>2000m)"
    display as text _newline "=== Linear-in-means — `lbl`rt'' ==="

    reghdfe deviation_speed ///
        c.z_opp_mean_past##ib0.fam_bin ///
        $controls if racetype == `rt', ///
        absorb($FEs) vce(cluster $cluster)
    estimates store M1_rt`rt'
}

*---------------------------------------------------------------------------
* COMPARISON MODEL: one peer variable per model, no interaction
* (standardized → directly comparable across models for Fig 3 coefplot)
*---------------------------------------------------------------------------
foreach spec in ///
    "z_opp_mean_past,  Mc1" ///
    "z_opp_min_past,   Mc2" ///
    "z_opp_max_past,   Mc3" ///
    "z_rank_in_field,  Mc4" ///
    "z_frac_similar,   Mc5" ///
    "z_opp_sd_past,    Mc67" {

    local pv  = word("`spec'", 1)
    local est = subinstr(word("`spec'", 2), ",", "", .)

    reghdfe deviation_speed c.`pv' $controls, ///
        absorb($FEs) vce(cluster $cluster)
    estimates store `est'
}

reghdfe deviation_speed c.z_opp_mean_past##c.rank $controls, ///
    absorb($FEs) vce(cluster $cluster)
estimates store Mc8

*===========================================================================
* SECTION 6  GRAPHS — KIERAN HEALY STYLE
*===========================================================================

*---------------------------------------------------------------------------
* FIGURE 1: Peer effect by familiarity bin — main result
* Marginal effect of avg opponent quality on deviation_speed, by fam_bin
*---------------------------------------------------------------------------
estimates restore M1_linear

margins fam_bin, dydx(z_opp_mean_past) noatlegend

marginsplot, ///
    recast(connected) recastci(rarea) ///
    plotopts(lcolor("$c_blue") mcolor("$c_blue") lwidth(medthick) ///
             msymbol(circle) msize(medlarge)) ///
    ciopts(color("$c_blue" %20) lwidth(none)) ///
    yline(0, lpattern(dash) lcolor(gs10) lwidth(thin)) ///
    xtitle("Prior co-competitions with current field", size(medsmall)) ///
    ytitle("Effect of 1 SD increase in opponent quality on speed deviation (m/s)", ///
           size(small)) ///
    title("Does Familiarity Amplify or Dampen the Peer Effect?", size(medlarge)) ///
    subtitle("Marginal effect of average opponent quality, by familiarity with the field", ///
             size(small) color(gs7)) ///
    note("OLS · FEs: athlete + event-type×year · Clustered SEs by athlete" ///
         "Peer quality = opponents' mean prior comp speed (standardized)", ///
         size(vsmall) color(gs8)) ///
    $gscheme $gbase

graph export "$root/peer_effect_output/fig1_peer_by_familiarity.pdf", replace
graph export "$root/peer_effect_output/fig1_peer_by_familiarity.png", ///
    width(1800) height(1200) replace
display "Fig 1 saved."

*---------------------------------------------------------------------------
* FIGURE 2: Peer effect × familiarity × race distance
* Small multiples: sprint / middle / long
*---------------------------------------------------------------------------
reghdfe deviation_speed ///
    c.z_opp_mean_past##ib0.fam_bin##ib1.racetype ///
    $controls, ///
    absorb($FEs) vce(cluster $cluster)

margins ib1.racetype#ib0.fam_bin, dydx(z_opp_mean_past) noatlegend

marginsplot, ///
    x(fam_bin) by(racetype) ///
    recast(connected) recastci(rarea) ///
    plotopts(lwidth(medthick) msymbol(circle) msize(medlarge)) ///
    ciopts(lwidth(none)) ///
    yline(0, lpattern(dash) lcolor(gs10) lwidth(thin)) ///
    byopts( ///
        title("Peer Effect by Familiarity and Race Distance (Task Complexity)", ///
              size(medlarge)) ///
        note("OLS · FEs: athlete + event-type×year · Clustered SEs by athlete" ///
             "Sprint ≤400m · Middle 500–2000m · Long >2000m", ///
             size(vsmall) color(gs8)) ///
        graphregion(color(white) fcolor(white)) imargin(b=2)) ///
    xtitle("Prior co-competitions with current field", size(small)) ///
    ytitle("ME of opponent quality on speed deviation (m/s)", size(small)) ///
    $gscheme

graph export "$root/peer_effect_output/fig2_peer_familiarity_distance.pdf", replace
graph export "$root/peer_effect_output/fig2_peer_familiarity_distance.png", ///
    width(2400) height(1000) replace
display "Fig 2 saved."

*---------------------------------------------------------------------------
* FIGURE 3: HOX model comparison — which mechanism fits best?
* Standardized coefficients + 95% CI, one row per model
*---------------------------------------------------------------------------
capture which coefplot
if !_rc {
    coefplot ///
        (Mc1,  label("1. Linear-in-means")       ///
               msymbol(circle)   mcolor("$c_blue")   ciopts(lcolor("$c_blue"))) ///
        (Mc2,  label("2. Bad Apple (min opp)")    ///
               msymbol(square)   mcolor("$c_orange") ciopts(lcolor("$c_orange"))) ///
        (Mc3,  label("3. Shining Light (max opp)")///
               msymbol(triangle) mcolor("$c_green")  ciopts(lcolor("$c_green"))) ///
        (Mc4,  label("4. Invidious Comparison")   ///
               msymbol(diamond)  mcolor("$c_red")    ciopts(lcolor("$c_red"))) ///
        (Mc5,  label("5. Boutique (similarity)")  ///
               msymbol(circle)   mcolor("$c_purple") ciopts(lcolor("$c_purple"))) ///
        (Mc67, label("6/7. Focus / Rainbow (SD)") ///
               msymbol(square)   mcolor("$c_lblue")  ciopts(lcolor("$c_lblue"))) ///
        (Mc8,  label("8. Single Crossing")        ///
               msymbol(triangle) mcolor(gs5)         ciopts(lcolor(gs5))), ///
        keep(z_opp_mean_past z_opp_min_past z_opp_max_past ///
             z_rank_in_field z_frac_similar z_opp_sd_past) ///
        xline(0, lpattern(dash) lcolor(gs10) lwidth(thin)) ///
        graphregion(color(white) fcolor(white)) plotregion(color(white)) ///
        legend(cols(2) region(lcolor(none)) size(small)) ///
        xtitle("Effect of 1 SD change in peer variable on deviation_speed (m/s)", ///
               size(medsmall)) ///
        title("HOX2007SCH Models: Which Peer Mechanism Operates?", size(medlarge)) ///
        subtitle("Competitive running · all peer variables standardized", ///
                 size(small) color(gs7)) ///
        note("OLS · FEs: athlete + event-type×year · Clustered SEs by athlete · Bars = 95% CI", ///
             size(vsmall) color(gs8)) ///
        $gscheme

    graph export "$root/peer_effect_output/fig3_hox_model_comparison.pdf", replace
    graph export "$root/peer_effect_output/fig3_hox_model_comparison.png", ///
        width(1800) height(1200) replace
    display "Fig 3 saved."
}

*---------------------------------------------------------------------------
* FIGURE 4: Familiarity distribution
*---------------------------------------------------------------------------
twoway histogram avg_n_prior if avg_n_prior <= 20, ///
    discrete color("$c_blue" %65) lcolor(white) lwidth(thin) ///
    xline(1 3 6, lpattern(dash) lcolor("$c_orange") lwidth(thin)) ///
    xtitle("Average prior co-competitions with current field", size(medsmall)) ///
    ytitle("Fraction", size(medsmall)) ///
    title("Empirical Distribution of Familiarity", size(medlarge)) ///
    subtitle("Dashed lines = bin cutoffs: 0 / 1 / 2–3 / 4–6 / 7+", ///
             size(small) color(gs7)) ///
    note("Trimmed at 20 for readability.", size(vsmall) color(gs8)) ///
    $gscheme $gbase

graph export "$root/peer_effect_output/fig4_familiarity_distribution.pdf", replace
graph export "$root/peer_effect_output/fig4_familiarity_distribution.png", ///
    width(1800) height(1200) replace
display "Fig 4 saved."

*---------------------------------------------------------------------------
* FIGURE 5: Continuous familiarity × peer effect, by race distance
*---------------------------------------------------------------------------
reghdfe deviation_speed ///
    c.z_opp_mean_past##c.avg_n_prior##ib1.racetype ///
    $controls, ///
    absorb($FEs) vce(cluster $cluster)

_pctile avg_n_prior, p(95)
local hi   = r(r1)
local step = max(`hi' / 20, 0.25)

margins ib1.racetype, ///
    dydx(z_opp_mean_past) ///
    at(avg_n_prior=(0(`step')`hi')) ///
    noatlegend

marginsplot, ///
    x(avg_n_prior) ///
    recast(line) recastci(rarea) ///
    plot1opts(lcolor("$c_blue")   lwidth(medthick)) ///
    plot2opts(lcolor("$c_orange") lwidth(medthick)) ///
    plot3opts(lcolor("$c_green")  lwidth(medthick)) ///
    ci1opts(color("$c_blue"   %15) lwidth(none)) ///
    ci2opts(color("$c_orange" %15) lwidth(none)) ///
    ci3opts(color("$c_green"  %15) lwidth(none)) ///
    yline(0, lpattern(dash) lcolor(gs10) lwidth(thin)) ///
    xtitle("Avg prior co-competitions with current field", size(medsmall)) ///
    ytitle("ME of opponent quality on speed deviation (m/s)", size(medsmall)) ///
    title("Familiarity Moderates the Peer Effect", size(medlarge)) ///
    subtitle("by race distance (task complexity)", size(small) color(gs7)) ///
    legend(order(1 "Sprint ≤400m" 2 "Middle 500–2000m" 3 "Long >2000m") ///
           cols(3) region(lcolor(none)) size(small)) ///
    note("OLS · FEs: athlete + event-type×year · Bands = 95% CI", ///
         size(vsmall) color(gs8)) ///
    $gscheme $gbase

graph export "$root/peer_effect_output/fig5_familiarity_continuous_by_distance.pdf", replace
graph export "$root/peer_effect_output/fig5_familiarity_continuous_by_distance.png", ///
    width(1800) height(1200) replace
display "Fig 5 saved."

*---------------------------------------------------------------------------
* FIGURE 6: Bad Apple vs Shining Light by familiarity
*---------------------------------------------------------------------------
reghdfe deviation_speed ///
    c.z_opp_min_past##ib0.fam_bin ///
    c.z_opp_max_past##ib0.fam_bin ///
    $controls, ///
    absorb($FEs) vce(cluster $cluster)

margins fam_bin, dydx(z_opp_min_past z_opp_max_past) noatlegend

marginsplot, ///
    recast(connected) recastci(rarea) ///
    plot1opts(lcolor("$c_red")  mcolor("$c_red")  lwidth(medthick) msymbol(square)) ///
    plot2opts(lcolor("$c_blue") mcolor("$c_blue") lwidth(medthick) msymbol(circle)) ///
    ci1opts(color("$c_red"  %20) lwidth(none)) ///
    ci2opts(color("$c_blue" %20) lwidth(none)) ///
    yline(0, lpattern(dash) lcolor(gs10) lwidth(thin)) ///
    xtitle("Prior co-competitions with current field", size(medsmall)) ///
    ytitle("ME on speed deviation (m/s)", size(medsmall)) ///
    title("Bad Apple vs Shining Light by Familiarity", size(medlarge)) ///
    subtitle("Does the worst or best opponent drive the peer effect?", ///
             size(small) color(gs7)) ///
    legend(order(1 "Bad Apple: slowest opponent" 2 "Shining Light: fastest opponent") ///
           cols(2) region(lcolor(none)) size(small)) ///
    note("OLS · FEs: athlete + event-type×year · Bands = 95% CI", ///
         size(vsmall) color(gs8)) ///
    $gscheme $gbase

graph export "$root/peer_effect_output/fig6_badapple_vs_shining.pdf", replace
graph export "$root/peer_effect_output/fig6_badapple_vs_shining.png", ///
    width(1800) height(1200) replace
display "Fig 6 saved."

*===========================================================================
* SECTION 7  REGRESSION TABLES
*===========================================================================

capture which esttab
if !_rc {

    * Table 1: Linear-in-means with familiarity interaction, by distance
    esttab M1_linear M1_rt1 M1_rt2 M1_rt3 ///
        using "$root/peer_effect_output/table1_linear_familiarity.rtf", ///
        replace se star(* 0.10 ** 0.05 *** 0.01) ///
        title("Table 1: Linear-in-Means Peer Effect by Familiarity and Race Distance") ///
        mtitles("Pooled" "Sprint" "Middle" "Long") ///
        keep(z_opp_mean_past                  ///
             1.fam_bin 2.fam_bin 3.fam_bin 4.fam_bin ///
             c.z_opp_mean_past#1.fam_bin      ///
             c.z_opp_mean_past#2.fam_bin      ///
             c.z_opp_mean_past#3.fam_bin      ///
             c.z_opp_mean_past#4.fam_bin) ///
        varlabels(                             ///
            z_opp_mean_past                   "Avg opp quality (std.)"          ///
            1.fam_bin                         "Fam: 1× (ref: Never)"           ///
            2.fam_bin                         "Fam: 2–3×"                      ///
            3.fam_bin                         "Fam: 4–6×"                      ///
            4.fam_bin                         "Fam: 7+×"                       ///
            "c.z_opp_mean_past#1.fam_bin"     "Peer × 1×"                      ///
            "c.z_opp_mean_past#2.fam_bin"     "Peer × 2–3×"                    ///
            "c.z_opp_mean_past#3.fam_bin"     "Peer × 4–6×"                    ///
            "c.z_opp_mean_past#4.fam_bin"     "Peer × 7+×")                   ///
        stats(N r2_a, labels("N" "Adj. R²")) ///
        note("FEs: athlete_id + track_event_id×year. Clustered SEs by athlete_id." ///
             "Peer = opponents' mean prior comp speed (standardized).")

    * Table 2: All 8 HOX models, standardized peer variable, pooled
    esttab Mc1 Mc2 Mc3 Mc4 Mc5 Mc67 Mc8 ///
        using "$root/peer_effect_output/table2_hox_models.rtf", ///
        replace se star(* 0.10 ** 0.05 *** 0.01) ///
        title("Table 2: HOX2007SCH Peer Effect Models — Competitive Running") ///
        mtitles("1.Linear" "2.BadApple" "3.Shining" ///
                "4.Invidious" "5.Boutique" "6/7.Focus" "8.SingleX") ///
        keep(z_opp_mean_past z_opp_min_past z_opp_max_past ///
             z_rank_in_field z_frac_similar z_opp_sd_past) ///
        varlabels(                             ///
            z_opp_mean_past  "Avg opp quality — Linear"      ///
            z_opp_min_past   "Min opp quality — Bad Apple"   ///
            z_opp_max_past   "Max opp quality — Shining Light" ///
            z_rank_in_field  "Focal rank in field — Invidious" ///
            z_frac_similar   "Share similar opps — Boutique"  ///
            z_opp_sd_past    "SD opp quality — Focus/Rainbow") ///
        stats(N r2_a, labels("N" "Adj. R²")) ///
        note("All peer vars standardized (SD=1). OLS." ///
             "FEs: athlete_id + track_event_id×year. Clustered SEs by athlete_id.")
}

display as text _newline ///
    "============================================================" _newline ///
    "  DONE. Saved to: $root/peer_effect_output/" _newline ///
    "  Figures: fig1–fig6 (.pdf + .png)" _newline ///
    "  Tables:  table1.rtf  table2.rtf" _newline ///
    "============================================================"
