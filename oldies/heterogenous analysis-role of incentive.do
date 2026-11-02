* Event titles to estimate
local events 170 169 167 42 109

* Choose grid for x-axis
summ average_opponent if inlist(eventtitle,170,169,167,42,109)
local xmin = r(min)
local xmax = r(max)

* Change step size if needed
local step = 0.1

tempfile allmfx
save `allmfx', emptyok replace

foreach e of local events {

    reghdfe speed c.average_opponent##c.average_opponent ///
        if eventtitle == `e', absorb(i.athlete_id)

    margins, dydx(average_opponent) ///
        at(average_opponent = (`xmin'(`step')`xmax'))

    matrix M = r(table)'

    preserve
        clear
        svmat M, names(col)

        gen average_opponent = .
        local i = 1
        forvalues x = `xmin'(`step')`xmax' {
            replace average_opponent = `x' in `i'
            local ++i
        }

        gen eventtitle = `e'
        rename b marginal_effect
        rename se std_error
        gen ci_low  = marginal_effect - 1.96 * std_error
        gen ci_high = marginal_effect + 1.96 * std_error

        keep eventtitle average_opponent marginal_effect std_error ci_low ci_high

        append using `allmfx'
        save `allmfx', replace
    restore
}

use `allmfx', clear

twoway ///
    (rarea ci_low ci_high average_opponent if eventtitle==170, color(navy%15)) ///
    (line marginal_effect average_opponent if eventtitle==170, lcolor(navy) lwidth(medthick)) ///
    (rarea ci_low ci_high average_opponent if eventtitle==169, color(maroon%15)) ///
    (line marginal_effect average_opponent if eventtitle==169, lcolor(maroon) lwidth(medthick)) ///
    (rarea ci_low ci_high average_opponent if eventtitle==167, color(forest_green%15)) ///
    (line marginal_effect average_opponent if eventtitle==167, lcolor(forest_green) lwidth(medthick)) ///
    (rarea ci_low ci_high average_opponent if eventtitle==42, color(orange%15)) ///
    (line marginal_effect average_opponent if eventtitle==42, lcolor(orange) lwidth(medthick)) ///
    (rarea ci_low ci_high average_opponent if eventtitle==109, color(purple%15)) ///
    (line marginal_effect average_opponent if eventtitle==109, lcolor(purple) lwidth(medthick)) ///
    , ///
    yline(0, lpattern(dash) lcolor(gs8)) ///
    xtitle("average_opponent") ///
    ytitle("Marginal effect on speed") ///
    title("Marginal effect of average_opponent by eventtitle") ///
    legend(order(2 "170" 4 "169" 6 "167" 8 "42" 10 "109") ///
           title("eventtitle") rows(1))