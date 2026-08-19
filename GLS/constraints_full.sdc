set_units -time 1.0ns;
set_units -capacitance  1.0pF;

set CLOCK_PERIOD 10;
set CLOCK_NAME   clk;

set SKEW_setup  [expr $CLOCK_PERIOD*0.025];
set SKEW_hold   [expr $CLOCK_PERIOD*0.025];
set MINRISE     [expr $CLOCK_PERIOD*0.125];
set MAXRISE     [expr $CLOCK_PERIOD*0.2];
set MINFALL     [expr $CLOCK_PERIOD*0.125];
set MAXFALL     [expr $CLOCK_PERIOD*0.2];

set MIN_PORT 1;
set MAX_PORT 2.5;


####### CLOCK CONSTRAINTS #########

create_clock -name "$CLOCK_NAME"                        \
             -period "$CLOCK_PERIOD"            \
             -waveform "0 [expr $CLOCK_PERIOD/2]"  \
              [get_ports "clk"]

## clock source latency
set_clock_latency   -source   -max   1.25   -late    [get_clocks  clk]
set_clock_latency   -source   -min   0.75   -late    [get_clocks  clk]
set_clock_latency   -source   -max   1.0    -early   [get_clocks  clk]
set_clock_latency   -source   -min   1.25   -early   [get_clocks  clk]

# clock transition
set_clock_transition   -rise   -min   $MINRISE   [get_clocks  clk]
set_clock_transition   -rise   -max   $MAXRISE   [get_clocks  clk]
set_clock_transition   -fall   -min   $MINRISE   [get_clocks  clk]
set_clock_transition   -fall   -max   $MAXRISE   [get_clocks  clk]
