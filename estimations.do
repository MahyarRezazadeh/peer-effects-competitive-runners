clear all

*global root="C:\Users\mahya\OneDrive - Simon Fraser University (1sfu)\Desktop\Peer effect in competitive runners"

global root="/Users/mahyarrezazadeh/Library/CloudStorage/OneDrive-SimonFraserUniversity(1sfu)/Desktop/Peer effect in competitive runners"



cd "$root"

use "$root/data_ready.dta", replace


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

	
*-----------------------------------------------------------------------
* always_sprint / always_middle / always_long
*   1 = athlete competed ONLY in that race type
*   0 = athlete competed in that type AND at least one other type
*   . = athlete never competed in that type
*-----------------------------------------------------------------------

* Count of distinct (non-missing) racetypes per athlete
bysort athlete_id racetype: gen byte _flag = (_n == 1) if !missing(racetype)
bysort athlete_id: egen n_racetypes = total(_flag)
drop _flag

* Whether the athlete ever raced each specific type
bysort athlete_id: egen has_sprint = max(racetype == 1)
bysort athlete_id: egen has_middle = max(racetype == 2)
bysort athlete_id: egen has_long   = max(racetype == 3)

gen byte always_sprint = .
replace  always_sprint = 1 if has_sprint == 1 & n_racetypes == 1
replace  always_sprint = 0 if has_sprint == 1 & n_racetypes > 1

gen byte always_middle = .
replace  always_middle = 1 if has_middle == 1 & n_racetypes == 1
replace  always_middle = 0 if has_middle == 1 & n_racetypes > 1

gen byte always_long = .
replace  always_long = 1 if has_long == 1 & n_racetypes == 1
replace  always_long = 0 if has_long == 1 & n_racetypes > 1

drop has_sprint has_middle has_long n_racetypes

label var always_sprint "=1 if only sprint, =0 if mixed w/ other types, . if never sprint"
label var always_middle "=1 if only middle, =0 if mixed w/ other types, . if never middle"
label var always_long   "=1 if only long,   =0 if mixed w/ other types, . if never long"


bysort athlete_id: egen has_sprint = max(racetype == 1)
bysort athlete_id: egen has_middle = max(racetype == 2)
bysort athlete_id: egen has_long   = max(racetype == 3)
gen byte n_main_types = has_sprint + has_middle + has_long

* mix_two:   1 if the athlete competed in exactly two of {sprint, middle, long}
* mix_three: 1 if the athlete competed in all three
gen byte mix_sprint_middle = (has_sprint == 1 & has_middle == 1 & has_long == 0)
gen byte mix_sprint_long   = (has_sprint == 1 & has_long   == 1 & has_middle == 0)
gen byte mix_middle_long   = (has_middle == 1 & has_long   == 1 & has_sprint == 0)
gen byte mix_three = (n_main_types == 3)

drop has_sprint has_middle has_long n_main_types


label var mix_three "=1 if athlete competed in all 3 of {sprint, middle, long}"

*-----------------------------------------------------------------------
* Add opponent columns to the main row-level dataset.
* For each (athlete_id, competition_id, eventid), the new columns are:
*   n_opponents
*   opp_id_1, opp_id_2, ..., opp_id_K
*   performance_1, performance_2, ..., performance_K
*   past_perf_1, past_perf_2, ..., past_perf_K
* These are broadcast to every round (every row) of the same race.
* All your existing variables (speed, deviation_speed, average_opponent,
* tier, always_sprint, mix_three, etc.) are preserved.
*-----------------------------------------------------------------------

preserve

    *--- Step 1. One row per (athlete, comp, eventid) ------------------
    bysort athlete_id competition_id eventid: keep if _n == 1
    keep athlete_id competition_id eventid start_date end_date comp_max

    *--- Step 2. Athlete's MEAN comp_max over strictly-prior meets ----
    gen long _ub = start_date - 1
    rangestat (mean) avg_past_performance = comp_max,                    ///
        interval(end_date . _ub) by(athlete_id eventid)
    drop _ub start_date end_date

    *--- Step 3. Number of opponents (covers solo runners too) --------
    bysort competition_id eventid: gen int n_opponents = _N - 1

    tempfile base
    save `base'

    *--- Step 4. Self-join: every (focal × opponent) pair in a race ----
    drop if n_opponents == 0         // skip solo entries; added back later
    drop n_opponents

    tempfile self_view
    save `self_view'

    rename (athlete_id comp_max avg_past_performance)                    ///
           (opp_id performance_ past_perf_)
    tempfile roster
    save `roster'

    use `self_view', clear
    joinby competition_id eventid using `roster'
    drop if athlete_id == opp_id

    *--- Step 5. Opponent index 1..K, ordered by opp athlete_id -------
    bysort athlete_id competition_id eventid (opp_id): gen int opp_idx = _n

    *--- Step 6. Reshape wide -----------------------------------------
    rename opp_id opp_id_
    keep athlete_id competition_id eventid opp_idx                       ///
         opp_id_ performance_ past_perf_

    reshape wide opp_id_ performance_ past_perf_,                        ///
        i(athlete_id competition_id eventid) j(opp_idx)

    *--- Step 7. Add n_opponents back (and the solo runners) ----------
    merge 1:1 athlete_id competition_id eventid using `base',            ///
        keepusing(n_opponents) nogen

    label var n_opponents "Number of opponents in this race"

    tempfile opp_wide
    save `opp_wide'

restore

*--- Step 8. Merge opponent columns into the full row-level dataset ---
* m:1 because multiple rounds share the same (athlete, comp, eventid).
merge m:1 athlete_id competition_id eventid using `opp_wide', nogen

*--- Step 9. Save the augmented dataset --------------------------------
save "$root/peer_data_ready.dta", replace




*********************CONTROLS


 global RHSvars="   c.temp0##c.temp0##c.meansummertemp0##c.average_opponent     c.average_opponent##c.pm0##c.pm0      c.pm0##c.temp0##c.average_opponent  c.temp0##c.humidity##c.average_opponent     c.pm0##c.humidity   c.humidity##c.humidity##c.average_opponent    c.pm0##c.north_wind     c.north_wind##c.north_wind c.pm0##c.east_wind  c.age##c.age##c.average_opponent   c.east_wind##c.east_wind   c.temp0##c.precipitation   c.pm0##c.precipitation  c.precipitation##c.precipitation##c.average_opponent    nrdaysevent"
	 global FEs=" i.athlete_id   i.is_female   i.is_home_race   i.track_event_id##i.year "
	 global clustervar="cluster athlete_id  race_id"

replace eventtitle=0 if eventtitle==.

********************************************************

*baseline

reghdfe deviation_speed  c.average_opponent##c.average_opponent##c.average_opponent##c.temp0##c.temp0 i.is_female##c.average_opponent c.average_opponent##i.eventtitle i.is_final##c.average_opponent i.racetype#c.average_opponent $RHSvars  , absorb($FEs)  vce (cluster athlete_id  i.eventtitle)
		

_pctile average_opponent, p(1 99)
local lo   = r(r1)
local hi   = r(r2)
local step = (`hi' - `lo') / 40


margins, dydx(average_opponent) at(average_opponent=(`lo'(`step')`hi')) noatlegend noestimcheck


marginsplot, recast(line) recastci(rarea) plotopts(lcolor(navy) lwidth(medthick))ciopts(color(navy%20) lwidth(none)) yline(0, lpattern(dash) lcolor(gs8)) ylabel(-3(1)3) yscale(range(0 5)) title("Marginal effect of opponent quality on speed deviation") ytitle("∂ deviation_speed / ∂ average_opponent") xtitle("Average opponent max speed (m/s) baseline") scheme(s2color)
	graph export "$root/graphes/baseline.jpg", replace
	
	
	**************ROLE OF DISTANCE
	
	*sprint
		
	
	reghdfe deviation_speed  c.average_opponent##c.average_opponent##c.average_opponent##c.temp0##c.temp0 i.is_female##c.average_opponent  c.average_opponent##i.eventtitle i.is_final##c.average_opponent  $RHSvars  if racetype==1, absorb($FEs)  vce (cluster athlete_id  i.eventtitle)
		

_pctile average_opponent, p(1 99)
local lo   = r(r1)
local hi   = r(r2)
local step = (`hi' - `lo') / 40


margins, dydx(average_opponent) at(average_opponent=(`lo'(`step')`hi')) noatlegend noestimcheck


marginsplot, recast(line) recastci(rarea) plotopts(lcolor(navy) lwidth(medthick))ciopts(color(navy%20) lwidth(none)) yline(0, lpattern(dash) lcolor(gs8)) ylabel(-3(1)3) yscale(range(0 5)) title("Marginal effect of opponent quality on speed deviation") ytitle("∂ deviation_speed / ∂ average_opponent") xtitle("Average opponent max speed (m/s) middle") scheme(s2color)
	graph export "$root/graphes/sprint.jpg", replace

	

	
	
	
	*2-middle
	
	reghdfe deviation_speed c.average_opponent##c.average_opponent##c.average_opponent##c.temp0##c.temp0 i.is_female##c.average_opponent c.average_opponent##i.eventtitle i.is_final##c.average_opponent  $RHSvars  if racetype==2, absorb($FEs)  vce (cluster athlete_id  i.eventtitle)
		

_pctile average_opponent, p(1 99)
local lo   = r(r1)
local hi   = r(r2)
local step = (`hi' - `lo') / 40


margins, dydx(average_opponent) at(average_opponent=(`lo'(`step')`hi')) noatlegend noestimcheck


marginsplot, recast(line) recastci(rarea) plotopts(lcolor(navy) lwidth(medthick))ciopts(color(navy%20) lwidth(none)) yline(0, lpattern(dash) lcolor(gs8)) ylabel(-3(1)3) yscale(range(0 5)) title("Marginal effect of opponent quality on speed deviation") ytitle("∂ deviation_speed / ∂ average_opponent") xtitle("Average opponent max speed (m/s) middle") scheme(s2color)
	graph export "$root/graphes/middle.jpg", replace

	
	
	*3-long
	
	reghdfe deviation_speed c.average_opponent##c.average_opponent##c.average_opponent##c.temp0##c.temp0 i.is_female##c.average_opponent c.average_opponent##i.eventtitle i.is_final##c.average_opponent  $RHSvars  if racetype==3, absorb($FEs) vce (cluster athlete_id  i.eventtitle)
		

_pctile average_opponent, p(1 99)
local lo   = r(r1)
local hi   = r(r2)
local step = (`hi' - `lo') / 40


margins, dydx(average_opponent) at(average_opponent=(`lo'(`step')`hi')) noatlegend noestimcheck


marginsplot, recast(line) recastci(rarea) plotopts(lcolor(navy) lwidth(medthick))ciopts(color(navy%20) lwidth(none)) yline(0, lpattern(dash) lcolor(gs8)) ylabel(-3(1)3) yscale(range(0 5)) title("Marginal effect of opponent quality on speed deviation") ytitle("∂ deviation_speed / ∂ average_opponent") xtitle("Average opponent max speed (m/s) long") scheme(s2color)
	graph export "$root/graphes/long.jpg", replace
	
	
**Always Middle 


	reghdfe deviation_speed c.average_opponent##c.average_opponent##c.average_opponent##c.temp0##c.temp0 i.is_female##c.average_opponent c.average_opponent##i.eventtitle i.is_final##c.average_opponent  $RHSvars  if  always_middle==1, absorb($FEs) vce (cluster athlete_id  i.eventtitle)
		

_pctile average_opponent, p(1 99)
local lo   = r(r1)
local hi   = r(r2)
local step = (`hi' - `lo') / 40


margins, dydx(average_opponent) at(average_opponent=(`lo'(`step')`hi')) noatlegend noestimcheck


marginsplot, recast(line) recastci(rarea) plotopts(lcolor(navy) lwidth(medthick))ciopts(color(navy%20) lwidth(none)) yline(0, lpattern(dash) lcolor(gs8)) ylabel(-3(1)3) yscale(range(0 5)) title("Marginal effect of opponent quality on speed deviation") ytitle("∂ deviation_speed / ∂ average_opponent") xtitle("Average opponent max speed (m/s) always middle") scheme(s2color)
	graph export "$root/graphes/always_middle.jpg", replace


	***mix of middle and long in different races
	
		reghdfe deviation_speed c.average_opponent##c.average_opponent##c.average_opponent##c.temp0##c.temp0 i.is_female##c.average_opponent c.average_opponent##i.eventtitle i.is_final##c.average_opponent  $RHSvars  if  (mix_middle_long==1 & racetype==2), absorb($FEs) vce (cluster athlete_id  i.eventtitle) 
		** mix runners who compete in middle
				
		
		

_pctile average_opponent, p(1 99)
local lo   = r(r1)
local hi   = r(r2)
local step = (`hi' - `lo') / 40


margins, dydx(average_opponent) at(average_opponent=(`lo'(`step')`hi')) noatlegend noestimcheck


marginsplot, recast(line) recastci(rarea) plotopts(lcolor(navy) lwidth(medthick))ciopts(color(navy%20) lwidth(none)) yline(0, lpattern(dash) lcolor(gs8)) ylabel(-3(1)3) yscale(range(0 5)) title("Marginal effect of opponent quality on speed deviation") ytitle("∂ deviation_speed / ∂ average_opponent") xtitle("Average opponent max speed (m/s) mix of middle and long in middle races") scheme(s2color)
	graph export "$root/graphes/mix_middle_long_in_middle.jpg", replace
	
	
			reghdfe deviation_speed c.average_opponent##c.average_opponent##c.average_opponent##c.temp0##c.temp0 i.is_female##c.average_opponent c.average_opponent##i.eventtitle i.is_final##c.average_opponent  $RHSvars  if  (mix_middle_long==1 & racetype==3), absorb($FEs) vce (cluster athlete_id  i.eventtitle) 
		** mix runners who compete in long
		
		
		
		

_pctile average_opponent, p(1 99)
local lo   = r(r1)
local hi   = r(r2)
local step = (`hi' - `lo') / 40


margins, dydx(average_opponent) at(average_opponent=(`lo'(`step')`hi')) noatlegend noestimcheck


marginsplot, recast(line) recastci(rarea) plotopts(lcolor(navy) lwidth(medthick))ciopts(color(navy%20) lwidth(none)) yline(0, lpattern(dash) lcolor(gs8)) ylabel(-3(1)3) yscale(range(0 5)) title("Marginal effect of opponent quality on speed deviation") ytitle("∂ deviation_speed / ∂ average_opponent") xtitle("Average opponent max speed (m/s) mix of middle and long in long races (racetype=3)") scheme(s2color)
	graph export "$root/graphes/mix_middle_long_in_long.jpg", replace
		
	
		
**Always long runners


	reghdfe deviation_speed c.average_opponent##c.average_opponent##c.average_opponent##c.temp0##c.temp0 i.is_female##c.average_opponent c.average_opponent##i.eventtitle i.is_final##c.average_opponent  $RHSvars  if  always_long==1, absorb($FEs) vce (cluster athlete_id  i.eventtitle)
		

_pctile average_opponent, p(1 99)
local lo   = r(r1)
local hi   = r(r2)
local step = (`hi' - `lo') / 40


margins, dydx(average_opponent) at(average_opponent=(`lo'(`step')`hi')) noatlegend noestimcheck


marginsplot, recast(line) recastci(rarea) plotopts(lcolor(navy) lwidth(medthick))ciopts(color(navy%20) lwidth(none)) yline(0, lpattern(dash) lcolor(gs8)) ylabel(-3(1)3) yscale(range(0 5)) title("Marginal effect of opponent quality on speed deviation") ytitle("∂ deviation_speed / ∂ average_opponent") xtitle("Average opponent max speed (m/s) always long") scheme(s2color)
	graph export "$root/graphes/always_long.jpg", replace
	
	
	****always sprint runners
	
	
	reghdfe deviation_speed c.average_opponent##c.average_opponent##c.average_opponent##c.temp0##c.temp0 i.is_female##c.average_opponent c.average_opponent##i.eventtitle i.is_final##c.average_opponent  $RHSvars  if  always_sprint==1, absorb($FEs) vce (cluster athlete_id  i.eventtitle)
		

_pctile average_opponent, p(1 99)
local lo   = r(r1)
local hi   = r(r2)
local step = (`hi' - `lo') / 40


margins, dydx(average_opponent) at(average_opponent=(`lo'(`step')`hi')) noatlegend noestimcheck


marginsplot, recast(line) recastci(rarea) plotopts(lcolor(navy) lwidth(medthick))ciopts(color(navy%20) lwidth(none)) yline(0, lpattern(dash) lcolor(gs8)) ylabel(-3(1)3) yscale(range(0 5)) title("Marginal effect of opponent quality on speed deviation") ytitle("∂ deviation_speed / ∂ average_opponent") xtitle("Average opponent max speed (m/s) always sprint") scheme(s2color)
	graph export "$root/graphes/always_sprint.jpg", replace
	