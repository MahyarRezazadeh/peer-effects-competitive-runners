clear all
 use "C:\Users\mahya\OneDrive - Simon Fraser University (1sfu)\Desktop\Peer effect in competitive runners\data_ready.dta" 

 *================================================================
* AVERAGE OPPONENT PERFORMANCE
*
* For each row in the original data, average_opponent =
*   mean speed of all opponents' performances in any
*   (competition_id, discipline) EXCEPT the (competition_id,
*    discipline) the opponent shares with the focal athlete,
*   restricted to opponent races strictly BEFORE the focal
*   race's startdate.
*
* - Full sample preserved: every original row stays, rounds/heats
*   in the same race all receive the same average_opponent value.
* - Memory-safe: opponent join is chunked.
*================================================================

*----- 0. Working directory --------------------------------------
global WD "C:\Users\mahya\OneDrive - Simon Fraser University (1sfu)\Desktop\Peer effect in competitive runners"      // <-- edit this path
cap mkdir "$WD"

*----- 1. Date prep + save the original (with duplicates) -------
gen long sdate = date(startdate, "YMD")   // adjust mask if needed
format sdate %td
assert !missing(sdate)

save "$WD/orig.dta", replace

*----- 2. Unique focal observations ------------------------------
* One row per athlete-race; rounds of the same race share
* opponents and date, so we compute once and merge back m:1.
use "$WD/orig.dta", clear
keep athlete_id competition_id discipline sdate
duplicates drop
rename athlete_id focal_id
rename sdate      focal_sdate
save "$WD/focal.dta", replace

*----- 3. Unique roster per (competition_id, discipline) ---------
* An opponent who ran 3 rounds is still just one opponent.
use "$WD/orig.dta", clear
keep athlete_id competition_id discipline
duplicates drop
rename athlete_id opp_id
save "$WD/roster.dta", replace

*----- 4. Focal × its opponents in that race ---------------------
use "$WD/focal.dta", clear
joinby competition_id discipline using "$WD/roster.dta"
drop if focal_id == opp_id
save "$WD/pairs.dta", replace

*----- 5. Opponent performance catalogue (ALL rows kept) ---------
use "$WD/orig.dta", clear
keep athlete_id competition_id discipline speed sdate
rename (athlete_id competition_id discipline speed sdate) ///
       (opp_id     opp_comp       opp_disc   opp_speed opp_sdate)
save "$WD/perf.dta", replace

*----- 6. Chunked joinby with pre-aggregation --------------------
use "$WD/pairs.dta", clear
gen long _row = _n
local N = _N
local chunksize = 100000                  // shrink if OOM (e.g. 50000)
local nchunks   = ceil(`N'/`chunksize')
save "$WD/pairs.dta", replace

local first = 1

forvalues c = 1/`nchunks' {
    local lo = (`c' - 1) * `chunksize' + 1
    local hi = min(`c' * `chunksize', `N')
    di as txt "Chunk `c'/`nchunks' (rows `lo'-`hi')"

    use if inrange(_row, `lo', `hi') using "$WD/pairs.dta", clear
    drop _row

    joinby opp_id using "$WD/perf.dta"

    * Exclude the (competition_id, discipline) shared with the focal
    drop if opp_comp == competition_id & opp_disc == discipline

    * Only opponent races strictly BEFORE the focal race
    keep if opp_sdate < focal_sdate

    * >>> Same-discipline only? Uncomment:
    * keep if opp_disc == discipline

    collapse (sum)   sum_speed = opp_speed   ///
             (count) cnt_speed = opp_speed,  ///
        by(focal_id competition_id discipline)

    if `first' {
        save "$WD/partial.dta", replace
        local first = 0
    }
    else {
        append using "$WD/partial.dta"
        save "$WD/partial.dta", replace
    }
}

*----- 7. Combine partial sums into the final mean ---------------
use "$WD/partial.dta", clear
collapse (sum) sum_speed cnt_speed, by(focal_id competition_id discipline)
gen average_opponent = sum_speed / cnt_speed
gen n_opp_obs        = cnt_speed
drop sum_speed cnt_speed
rename focal_id athlete_id
save "$WD/avgop.dta", replace

*----- 8. Merge back to the ORIGINAL data (all rounds preserved) -
use "$WD/orig.dta", clear
merge m:1 athlete_id competition_id discipline using "$WD/avgop.dta", ///
    keep(master match) nogen

* Optional: save final dataset
* save "$WD/final.dta", replace


bysort athlete_id: egen maximum_speed = max(speed)


gen deviation_speed= speed-maximum_speed

save "$WD/peer_data_ready.dta", replace