#include "Vtb_tape.h"
#include "verilated.h"
int main(int c,char**v){ Verilated::commandArgs(c,v); Vtb_tape t; while(!Verilated::gotFinish()){ t.clock=0; t.eval(); t.clock=1; t.eval(); } }
