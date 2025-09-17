import Ehr::*;
import Vector::*;

//////////////////
// Fifo interface 

interface Fifo#(numeric type n, type t);
    method Bool notFull;
    method Action enq(t x);
    method Bool notEmpty;
    method Action deq;
    method t first;
    method Action clear;
endinterface

/////////////////
// Conflict FIFO

module mkMyConflictFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo
    Vector#(n, Reg#(t))     data     <- replicateM(mkRegU());
    Reg#(Bit#(TLog#(n)))    enqP     <- mkReg(0);
    Reg#(Bit#(TLog#(n)))    deqP     <- mkReg(0);
    Reg#(Bool)              empty    <- mkReg(True);
    Reg#(Bool)              full     <- mkReg(False);

    // useful value
    Bit#(TLog#(n))          max_index = fromInteger(valueOf(n)-1);


    function Bit#(TLog#(n)) nextPtr( Bit#(TLog#(n)) p );
        return (p == max_index) ? 0 : p + 1;
    endfunction

    method Bool notFull;
        return !full;
    endmethod

    method Bool notEmpty;
        return !empty;
    endmethod

    method Action enq(t x) if (!full);
        data[enqP] <= x;
        let next_enqP = nextPtr(enqP);
        enqP <= next_enqP;
        empty <= False;
        if (next_enqP == deqP) begin
            full <= True;
        end

    endmethod

    method Action deq() if (!empty);   
        let next_deqP = nextPtr(deqP);
        deqP <= next_deqP;
        full <= False;
        if (next_deqP == enqP) begin
            empty <= True;
        end
    endmethod

    method t first if (!empty);
        return data[deqP];
    endmethod

    method Action clear;
        enqP <= 0;
        deqP <= 0;
        empty <= True;
        full <= False;
    endmethod

    // TODO: Implement all the methods for this module
endmodule

/////////////////
// Pipeline FIFO

// Intended schedule:
//      {notEmpty, first, deq} < {notFull, enq} < clear
module mkMyPipelineFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo

    method Bool notFull;
        return True;
    endmethod

    method Action enq(t x);
        noAction;
    endmethod

    method Bool notEmpty;
        return False;
    endmethod

    method Action deq;
        noAction;
    endmethod

    method t first;
        return ?;
    endmethod

    method Action clear;
        noAction;
    endmethod
endmodule

/////////////////////////////
// Bypass FIFO without clear

// Intended schedule:
//      {notFull, enq} < {notEmpty, first, deq} < clear
module mkMyBypassFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo

    method Bool notFull;
        return True;
    endmethod

    method Action enq(t x);
        noAction;
    endmethod

    method Bool notEmpty;
        return False;
    endmethod

    method Action deq;
        noAction;
    endmethod

    method t first;
        return ?;
    endmethod

    method Action clear;
        noAction;
    endmethod
endmodule

//////////////////////
// Conflict free fifo

// Intended schedule:
//      {notFull, enq} CF {notEmpty, first, deq}
//      {notFull, enq, notEmpty, first, deq} < clear
module mkMyCFFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo

    method Bool notFull;
        return True;
    endmethod

    method Action enq(t x);
        noAction;
    endmethod

    method Bool notEmpty;
        return False;
    endmethod

    method Action deq;
        noAction;
    endmethod

    method t first;
        return ?;
    endmethod

    method Action clear;
        noAction;
    endmethod
endmodule

