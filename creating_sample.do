/********************************************************************
  NONLINEAR PEER EFFECT RESPONSE FUNCTIONS AND TRANSITION PATH
  Outcome: deviation_speed
  Benchmark outcome: speed = maximum speed in each period
  Peer variable: average_opponent
  Athlete id: athlete_id
********************************************************************/
global root="C:\Users\mahya\OneDrive - Simon Fraser University (1sfu)\Desktop\Peer effect in competitive runners"

cd "$root"

use "$root/data_ready.dta", replace


encode (discipline), gen(discipline1)


/*Sample restrictions
****/
drop if race==.
*fill age variable
  replace age=year-birthyear if age==.

*drop if age<15

 *drop if is_home_race ==1

  *only outdoor events
 /* insample= 1  select
individual events (so no relay
only indiidual runing evnets ( 100, 200, 400, 800, `500, 3000, 5000, 10000) no walk
no wheelchair or blind races
adults only
no hurdles or steeplechase
 */


*fill age variable
  replace age=year-birthyear if age==.

*CREATE ST PERFORMANCE

gen tmp_wr=WR_men if race_sex=="male"
replace tmp_wr=WR_women if race_sex=="female"
bys race_distance_meters race_sex: egen tmp_SD=sd(second)

bys race_distance_meters race_sex: egen tmp_SD_speed=sd(speed)
bys race_distance_meters race_sex: egen tmp_mean_speed=mean(speed)
bys race_distance_meters race_sex: egen tmp_max_speed=max(speed)

bys athlete_id race_distance_meters: egen tmp_PB=max(speed)

gen perf_sexton=-abs(tmp_wr-second)/tmp_SD

 *gen speed_norm=(speed-tmp_mean_speed)/tmp_SD_speed
 gen speed_norm=(speed -tmp_max_speed )/tmp_SD_speed
 gen speed_normPB=(speed -tmp_PB )/tmp_SD_speed

label var speed_norm "Standardized speed"
label var  perf_sexton "Standardized performance relative to World record"

gen abs_latitude=abs(latitude)

gen is_final=(race==3)
 
gen is_female=(gender==2)

 
egen track_event_id=group(race_distance_meters race_sex)
egen competition_id_event=group(competition_id track_event_id )

gen is_summer=( season==4)

gen is_spring =(season==3)


gen is_sprint=(race_distance_meters<=400)
gen is_middle=(racetype==2)
gen is_long=(racetype==3)
 
 egen gdppc_2019_2023=rowmean(gdp_percapita_2019 - gdp_percapita_2023)
 gen ln_gdppc_2019_2023=ln(gdppc_2019_2023)
 
 *indicator of rank among runners in same track event  (i.e. men 100 m)
 
 *identify max speed of runner 
 bys athlete_id race_distance_meters race_sex: egen max_speed=max(speed)
 bys athlete_id race_distance_meters race_sex : gen tmp_id=_n
 

 *assign decile withi track event id
 forvalues i=1/18 {
 	cap drop tmp_rank`i'
	cap xtile  tmp_rank`i'=max_speed if tmp_id==1 & track_event_id==`i', n(10)
 }
 egen tmp_rankall=rmax(tmp_rank? tmp_rank??)
 bys athlete_id track_event_id: egen rank=max(tmp_rankall)
 
 
   label var rank "rank 10 (fastest) to 1 (slowest)"
   
    *create max speed of runner (normalized siialr to the and averaged over all events )
  
    bys athlete_id: egen meanrunnerspeed_norm=mean(speed_norm)
   bys athlete_id: egen maxrunnerspeed_norm=max(speed_norm)

   
 *duration of event
 gen nrdaysevent=end_date- start_date+1
 
 
 	  *identify trimmed sample
cap drop trim
sum speed_norm , de
gen trim=(speed_norm>`r(p99)' | speed_norm< `r(p1)')
 
 
*olympic games(not inlcuding youth), world athletic champiosnioops. commonwealth games, olympic trial
 
  decode name , gen(name_string)
 
  
	cap drop is_olympic
	generate is_olympic = regexm(name_string, "Olympic Games")	
	recode   is_olympic 1=0 if regexm(name_string, "Youth")	

	cap drop is_worldchamp
	generate is_worldchamp = regexm(name_string, "IAAF World Championships")	 
	recode is_worldchamp 0=1 if regexm(name_string, "World Athletics Championships")
   recode is_worldchamp 0=1 if regexm(name_string, "World Athletics")
 recode is_worldchamp 1=0 if regexm(name_string, "Trials")
  recode is_worldchamp 1=0 if regexm(name_string, "Pre World")


 
 cap drop is_vip
 gen is_vip=(is_olympic==1 | is_worldchamp==1)
 
 gen ihs_elevation= asinh(elevation)
 
 
 *calculate wet bulb temperatures
  
 gen T=temp0
 gen RH=humidity
gen wetbulb = T * atan(0.152 * sqrt(RH + 8.3136)) + atan(T + RH) - atan(RH - 1.6763) + 0.00391838 * (RH^(3/2)) * atan(0.0231 * RH) - 4.686

/* REGRESSION SAMPLE: Fernando's work

	 global RHSvars="   c.temp0##c.temp0##c.meansummertemp0     c.pm0##c.pm0      c.pm0##c.temp0  c.temp0##c.humidity     c.pm0##c.humidity   c.humidity##c.humidity         c.pm0##c.north_wind     c.north_wind##c.north_wind c.pm0##c.east_wind     c.east_wind##c.east_wind   c.temp0##c.precipitation   c.pm0##c.precipitation  c.precipitation##c.precipitation    nrdaysevent"
	 global FEs=" i.athlete_id       is_home_race   i.track_event_id##i.year  is_final"
	 global clustervar="cluster athlete_id   "
	 
	 ******/
 order athlete_id competition_id speed discipline eventtitle eventid
 sort athlete_id competition_id discipline
 
 
 gen is_home_race=(Nationality_code==country_code)
*-----------------------------------------------------------------------
* average_opponent: leave-one-out mean of opponents' max speed in the
* same eventid across STRICTLY-PRIOR competitions, where "prior" means
* the other competition's end_date < this competition's start_date.
*-----------------------------------------------------------------------

* Make sure rangestat is installed
capture which rangestat
if _rc ssc install rangestat

*--- Step 1. Best speed per (athlete, eventid, competition) ------------
bysort athlete_id eventid competition_id: egen comp_max = max(speed)

*--- Step 2. Max speed across STRICTLY-PRIOR competitions --------------
* One row per (athlete, eventid, competition); use rangestat to take the
* max of comp_max over OTHER rows (same athlete & eventid) whose
* end_date is at or below (start_date - 1).
preserve
    bysort athlete_id eventid competition_id: keep if _n == 1

    gen long _ub = start_date - 1                 // strict cutoff
    rangestat (max) max_prev = comp_max,          ///
        interval(end_date . _ub)                  ///
        by(athlete_id eventid)

    keep athlete_id eventid competition_id max_prev
    tempfile prevmax
    save `prevmax'
restore

merge m:1 athlete_id eventid competition_id using `prevmax', nogen

*--- Step 3. Leave-one-out mean of opponents' max_prev -----------------
* At the (competition, eventid) level on ONE row per athlete so multi-
* round athletes aren't multi-counted, then merge back to row level.
preserve
    bysort competition_id eventid athlete_id: keep if _n == 1

    bysort competition_id eventid: egen double _sum = total(max_prev)
    bysort competition_id eventid: egen          _cnt = count(max_prev)

    gen double _own = cond(missing(max_prev), 0, max_prev)
    gen byte   _has = !missing(max_prev)

    gen double average_opponent = (_sum - _own) / (_cnt - _has)
    replace    average_opponent = . if (_cnt - _has) <= 0

    keep athlete_id competition_id eventid average_opponent
    tempfile avgopp
    save `avgopp'
restore

merge m:1 athlete_id competition_id eventid using `avgopp', nogen

label var comp_max         "Athlete's best speed in this meet × eventid"
label var max_prev         "Athlete's max speed in this eventid, prior meets"
label var average_opponent "Mean of opponents' max_prev in this race"

*--- Step 4. Deviation of current speed from prior personal best -------
gen double deviation_speed = speed - max_prev
label var deviation_speed "Speed in this round minus athlete's prior max in this eventid"

* Race = competition × discipline
egen race_id = group(competition_id eventid)
*********************************************************************************/
	
	
	
	*-----------------------------------------------------------------------
* Competition tier (numeric eventTitle version)
*   3 = Top professional circuit
*   2 = Strong nationals & continental tour
*   1 = Other professional / open
*   0 = Amateur / youth / development
*-----------------------------------------------------------------------
cap drop tier
gen byte tier = 1   // default

*--- Tier 3: Top professional ------------------------------------------
* 42=Diamond Discipline, 53=Elite Event,
* 83=IAAF World Indoor Tour, 196=World Athletics Indoor Tour
replace tier = 3 if inlist(eventtitle, 42, 53, 83, 196)

*--- Tier 2: Strong nationals & continental ----------------------------
* 10=Asian Race, 12=Asics Challenge, 13/14/15=Australian 10k/3k/5k Ch.,
* 20=CAN/CHN Challenge, 21=Canada Summer Games Trials,
* 24=Championship events, 48=Dutch 10,000m Ch., 50=EU Cup,
* 51=Ecuadorian Champs, 55=Estonian 10,000m Ch.,
* 60=French 10,000m Champs, 84=Indoor Meeting, 85=International Events,
* 87=Irish 10,000m Ch., 93=Japan GP Series, 96=Kenyan Olympic Trials,
* 98=Liechtenstein Champs, 109=National Events,
* 111=NZ 3000m Ch., 126=Portuguese 10,000m Ch.,
* 129=Premier Events, 143=Senior Events, 146=South American GP,
* 150=Spanish 10,000m Ch., 155=Super League, 178=UK 10,000m Ch.
replace tier = 2 if inlist(eventtitle,                                          ///
    10, 12, 13, 14, 15, 20, 21, 24, 48, 50,                                     ///
    51, 55, 60, 84, 85, 87, 93, 96, 98, 109,                                    ///
    111, 126, 129, 143, 146, 150, 155, 178)

*--- Tier 0: Youth / amateur / development -----------------------------
* 2/4/5/6=US HS classes (3A–6A), 23=Championship HS Event,
* 29=Club events, 30=College Events, 32–35=Combined Events U16–U23,
* 36=Community Events, 41=Developmental Events,
* 72–75=High School Div I/II/V/VI, 76=High School Events,
* 77=HS Invitational, 78=HS Rising Stars,
* 105=Masters Events, 107=Middle School Events,
* 113=NZ U20 3000m Ch., 154=Split times U20,
* 164–177=U13 through U23 (plus invitationals/gala),
* 189=University, 192=Veteran Events, 193=W35,
* 276=Young Diamonds Challenge
replace tier = 0 if inlist(eventtitle,                                          ///
    2, 4, 5, 6, 23, 29, 30, 32, 33, 34,                                         ///
    35, 36, 41, 72, 73, 74, 75, 76, 77, 78,                                     ///
    105, 107, 113, 154, 164, 165, 166, 167, 169, 170,                           ///
    171, 172, 173, 174, 175, 176, 177, 189, 192, 193,                           ///
    276)

label define tier_lbl 0 "Amateur/Youth" 1 "Other Open"                          ///
                     2 "Strong Nationals/Continental"                           ///
                     3 "Top Professional", replace
label values tier tier_lbl
label var tier "Competition tier from eventTitle"

 
 save "$root/data_ready.dta", replace
 
 
 
/***************OLDIES
 
*------------------------------------------------------------*
* 1. USER SETTINGS
*------------------------------------------------------------*

* Replace this with your actual period variable name
* Example: period, round, year, race_date, event_period, etc.
global period date_start


* Main variables
local y_dev   deviation_speed
local y_level speed
local peer    average_opponent
local id      athlete_id

* Controls and fixed effects
local controls c.temp0##c.temp0 east_wind north_wind pollution_0_days_before_nobiasc
local fes i.eventid i.age i.year  i.age_2 i.Nationality i.raceid i.athlete_id i.discipline1

* Cluster structure
local clust i.athlete_id

* Output folder
cap mkdir "peer_effect_output"


/********************************************************************
  2. Estimate nonlinear peer-effect model
********************************************************************/
bysort athlete_id: egen best = max(speed)
egen athlete_rank = rank(-best) if best == speed, unique   // rank once per athlete
bysort athlete_id (athlete_rank): replace athlete_rank = athlete_rank[1]
gen byte top_25 = (athlete_rank <=  12972 )  //top 25%
drop best athlete_rank


 reghdfe `y_dev' ///
    c.`peer'##c.`peer'##c.`peer' ///
     `controls', ///
    absorb(`fes') ///
     vce(cluster `clust')


estimates store peer_cubic

* Save coefficients
scalar b1 = _b[c.`peer']
scalar b2 = _b[c.`peer'#c.`peer']
scalar b3 = _b[c.`peer'#c.`peer'#c.`peer']

display "Cubic peer-effect coefficients:"
display "b1 = " b1
display "b2 = " b2
display "b3 = " b3


/********************************************************************
  3. Marginal effect of peer composition
     d(deviation_speed)/d(average_opponent)
********************************************************************/

gen double ME_peer = b1 + 2*b2*`peer' + 3*b3*(`peer'^2)

sum ME_peer, detail

histogram ME_peer, ///
    fraction ///
    xtitle("Marginal effect of average_opponent") ///
    ytitle("Fraction") ///
    title("Distribution of nonlinear marginal peer effects")

graph export "peer_effect_output/marginal_effect_distribution.png", replace


/********************************************************************
  4. Construct benchmark: no peer effect
     Benchmark = maximum speed in each period
********************************************************************/

bysort `period': egen double max_speed_period = max(`y_level')

gen double speed_no_peer_benchmark = max_speed_period

label var speed_no_peer_benchmark ///
    "Benchmark speed without peer effect: max speed in period"


/********************************************************************
  5. Construct fitted nonlinear peer response
     This isolates the peer-composition part of the cubic response.
********************************************************************/

* Choose a reference peer composition.
* Here: sample mean of average_opponent.
sum `peer' if e(sample), meanonly
scalar peer_ref = r(mean)

scalar f_ref = b1*peer_ref + b2*(peer_ref^2) + b3*(peer_ref^3)

gen double peer_response_dev = ///
    b1*`peer' + b2*(`peer'^2) + b3*(`peer'^3) - f_ref

label var peer_response_dev ///
    "Nonlinear peer-response component, centered at mean peer composition"

* Level response with peer effect:
* benchmark maximum speed + estimated nonlinear peer deviation
gen double speed_with_peer_effect = ///
    speed_no_peer_benchmark + peer_response_dev

label var speed_with_peer_effect ///
    "Response speed with nonlinear peer effect"

* Gap between peer-effect response and benchmark
gen double peer_transition_gap = ///
    speed_with_peer_effect - speed_no_peer_benchmark

label var peer_transition_gap ///
    "With-peer response minus no-peer benchmark"


/********************************************************************
  6. Response function over a grid of peer composition
********************************************************************/

preserve

    keep if e(sample)
    keep `peer'
    drop if missing(`peer')

    sum `peer', detail
    local p1  = r(p1)
    local p99 = r(p99)

    clear
    set obs 200

    gen double peer_grid = `p1' + (_n-1)*((`p99' - `p1')/199)

    gen double response_with_peer_dev = ///
        b1*peer_grid + b2*(peer_grid^2) + b3*(peer_grid^3) - f_ref

    gen double response_no_peer_dev = 0

    label var peer_grid "Peer composition: average_opponent"
    label var response_with_peer_dev "With nonlinear peer effect"
    label var response_no_peer_dev "No peer effect benchmark"

    twoway ///
        (line response_with_peer_dev peer_grid, ///
            lcolor(navy) lwidth(medthick)) ///
        (line response_no_peer_dev peer_grid, ///
            lcolor(maroon) lpattern(dash) lwidth(medthick)), ///
        yline(0, lcolor(gs10)) ///
        xtitle("Peer composition: average_opponent") ///
        ytitle("Predicted deviation from benchmark speed") ///
        title("Response function to peer composition") ///
        subtitle("Cubic nonlinear peer effect vs no-peer benchmark") ///
        legend(order(1 "With peer effect" 2 "No peer effect / benchmark") ///
               position(6) rows(1))

    graph export "peer_effect_output/response_function_peer_composition.png", replace

    save "peer_effect_output/response_function_grid.dta", replace

restore


/********************************************************************
  7. Transition path over periods
********************************************************************/

preserve

    keep if e(sample)

    collapse ///
        (mean) avg_speed_observed = `y_level' ///
               avg_speed_with_peer = speed_with_peer_effect ///
               avg_speed_no_peer = speed_no_peer_benchmark ///
               avg_peer_gap = peer_transition_gap ///
               avg_peer_comp = `peer' ///
        (sd) sd_peer_gap = peer_transition_gap ///
        (count) N = `y_level', ///
        by(`period')

    sort `period'

    label var avg_speed_observed "Observed average speed"
    label var avg_speed_with_peer "Predicted speed with peer effect"
    label var avg_speed_no_peer "Benchmark: max speed in period"
    label var avg_peer_gap "Average peer-effect transition gap"

    twoway ///
        (line avg_speed_with_peer `period', ///
            lcolor(navy) lwidth(medthick)) ///
        (line avg_speed_no_peer `period', ///
            lcolor(maroon) lpattern(dash) lwidth(medthick)) ///
        (line avg_speed_observed `period', ///
            lcolor(gs8) lpattern(dot) lwidth(medthick)), ///
        xtitle("Period") ///
        ytitle("Speed") ///
        title("Transition path of speed") ///
        subtitle("With nonlinear peer effect vs no-peer benchmark") ///
        legend(order(1 "With peer effect" ///
                     2 "No peer effect / benchmark" ///
                     3 "Observed average speed") ///
               position(6) rows(1))

    graph export "peer_effect_output/transition_path_speed.png", replace

    twoway ///
        (line avg_peer_gap `period', ///
            lcolor(navy) lwidth(medthick)), ///
        yline(0, lcolor(maroon) lpattern(dash)) ///
        xtitle("Period") ///
        ytitle("With-peer minus benchmark speed") ///
        title("Transition gap from nonlinear peer effect")

    graph export "peer_effect_output/transition_gap.png", replace

    save "peer_effect_output/transition_path_by_period.dta", replace

restore


/********************************************************************
  8. Athlete-level transition paths
     Useful when panel is unbalanced.
********************************************************************/

preserve

    keep if e(sample)
    keep `id' `period' `y_level' `peer' ///
         speed_with_peer_effect speed_no_peer_benchmark peer_transition_gap

    sort `id' `period'

    save "peer_effect_output/athlete_level_transition_paths.dta", replace

restore


/********************************************************************
  9. Optional: plot selected athletes' transition paths
     Change the athlete IDs below.
********************************************************************/

levelsof `id' if e(sample), local(ids)
local first_ids : word 1 of `ids'
local second_ids : word 2 of `ids'
local third_ids : word 3 of `ids'

twoway ///
    (line speed_with_peer_effect `period' if `id' == `first_ids', ///
        lcolor(navy) lwidth(medthick)) ///
    (line speed_no_peer_benchmark `period' if `id' == `first_ids', ///
        lcolor(maroon) lpattern(dash) lwidth(medthick)), ///
    xtitle("Period") ///
    ytitle("Speed") ///
    title("Example athlete transition path") ///
    subtitle("Athlete ID = `first_ids'") ///
    legend(order(1 "With peer effect" 2 "No peer benchmark") ///
           position(6) rows(1))

graph export "peer_effect_output/example_athlete_transition.png", replace


/********************************************************************
  10. Export regression table
********************************************************************/

cap which esttab
if _rc ssc install estout, replace

esttab peer_cubic using "peer_effect_output/peer_effect_regression.rtf", ///
    replace ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    title("Nonlinear Peer Effect Model") ///
    keep(c.`peer' c.`peer'#c.`peer' c.`peer'#c.`peer'#c.`peer' ///
         c.temp0 c.temp0#c.temp0) ///
    stats(N r2_a, labels("Observations" "Adjusted R-squared"))
	
	
	*************************END OF OLDIES