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
    Vector#(n, Reg#(t))     data     <- replicateM(mkRegU());
    Ehr#(2,Bit#(TLog#(n)))    enqP     <- mkEhr(0);
    Ehr#(3,Bit#(TLog#(n)))    deqP     <- mkEhr(0);
    Ehr#(3,Bool)              empty    <- mkEhr(True);
    Ehr#(3,Bool)              full     <- mkEhr(False);

    // useful value
    Bit#(TLog#(n))          max_index = fromInteger(valueOf(n)-1);


    function Bit#(TLog#(n)) nextPtr( Bit#(TLog#(n)) p );
        return (p == max_index) ? 0 : p + 1;
    endfunction

    method Bool notFull;
        return !full[1];
    endmethod

    method Bool notEmpty;
        return !empty[0];
    endmethod

    method Action enq(t x) if (!full[1]);
        data[enqP[0]] <= x;
        let next_enqP = nextPtr(enqP[0]);
        enqP[0] <= next_enqP;
        empty[1] <= False;
        if (next_enqP == deqP[1]) begin
            full[1] <= True;
        end

    endmethod

    method Action deq() if (!empty[0]);   
        let next_deqP = nextPtr(deqP[0]);
        deqP[0] <= next_deqP;
        full[0] <= False;
        if (next_deqP == enqP[0]) begin
            empty[0] <= True;
        end
    endmethod

    method t first if (!empty[0]);
        return data[deqP[0]];
    endmethod

    method Action clear;
        enqP[1] <= 0;
        deqP[2] <= 0;
        empty[2] <= True;
        full[2] <= False;
    endmethod

endmodule

/////////////////////////////
// Bypass FIFO without clear

// Intended schedule:
//      {notFull, enq} < {notEmpty, first, deq} < clear
module mkMyBypassFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo

    Vector#(n, Reg#(t))     data     <- replicateM(mkRegU());
    Ehr#(3,Bit#(TLog#(n)))    enqP     <- mkEhr(0);
    Ehr#(2,Bit#(TLog#(n)))    deqP     <- mkEhr(0);
    Ehr#(3,Bool)              empty    <- mkEhr(True);
    Ehr#(3,Bool)              full     <- mkEhr(False);

    // useful value
    Bit#(TLog#(n))          max_index = fromInteger(valueOf(n)-1);


    function Bit#(TLog#(n)) nextPtr( Bit#(TLog#(n)) p );
        return (p == max_index) ? 0 : p + 1;
    endfunction

    method Bool notFull;
        return !full[0];
    endmethod

    method Bool notEmpty;
        return !empty[1];
    endmethod

    method Action enq(t x) if (!full[0]);
        data[enqP[0]] <= x;
        let next_enqP = nextPtr(enqP[0]);
        enqP[0] <= next_enqP;
        empty[0] <= False;
        if (next_enqP == deqP[0]) begin
            full[0] <= True;
        end

    endmethod

    method Action deq() if (!empty[1]);   
        let next_deqP = nextPtr(deqP[0]);
        deqP[0] <= next_deqP;
        full[1] <= False;
        if (next_deqP == enqP[1]) begin
            empty[1] <= True;
        end
    endmethod

    method t first if (!empty[1]);
        return data[deqP[0]];
    endmethod

    method Action clear;
        enqP[2] <= 0;
        deqP[1] <= 0;
        empty[2] <= True;
        full[2] <= False;
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


    Bit#(TLog#(n))          max_index = fromInteger(valueOf(n)-1);
    function Bit#(TLog#(n)) nextPtr( Bit#(TLog#(n)) p );
        return (p == max_index) ? 0 : p + 1;
    endfunction

    Vector#(n, Reg#(t))     data     <- replicateM(mkRegU());
    Ehr#(2,Bit#(TLog#(n)))    enqP     <- mkEhr(0);
    Ehr#(2,Bit#(TLog#(n)))    deqP     <- mkEhr(0);
    Ehr#(2,Bool)              empty    <- mkEhr(True);
    Ehr#(2,Bool)              full     <- mkEhr(False);
    // Ehr#(2,Maybe#(Bool))             call_deq <- mkEhr(tagged Invalid);
    // Ehr#(2,Maybe#(t))                call_enq <- mkEhr(tagged Invalid);
    RWire#(void)             call_deq <- mkRWire;
    RWire#(t)                 call_enq <- mkRWire;


    rule post_canonicalize;
        let c_deq = call_deq.wget();
        let c_enq = call_enq.wget();

        Bool _empty = empty[0];
        Bool _full = full[0];
        
        if (isValid(c_deq) && isValid(c_enq)) begin
            // both deq and enq
            data[enqP[0]] <= fromMaybe(?,c_enq);
            let next_deqP = nextPtr(deqP[0]);
            deqP[0] <= next_deqP;
            let next_enqP = nextPtr(enqP[0]);
            enqP[0] <= next_enqP;
            // empty and full do not change
        end else if (isValid(c_deq)) begin
            // only deq
            let next_deqP = nextPtr(deqP[0]);
            deqP[0] <= next_deqP;
            _full = False;
            if (next_deqP == enqP[0]) begin
                _empty = True;
            end
        end else if (isValid(c_enq)) begin
            // only enq
            data[enqP[0]] <= fromMaybe(?,c_enq);
            let next_enqP = nextPtr(enqP[0]);
            enqP[0] <= next_enqP;
            _empty = False;
            if (next_enqP == deqP[0]) begin
                _full = True;
            end
        end


        empty[0] <= _empty;
        full[0] <= _full;
    endrule

    method Bool notFull;
        return !full[0];
    endmethod

    method Action enq(t x) if (!full[0]);
        call_enq.wset(x);
    endmethod

    method Bool notEmpty;
        return !empty[0];
    endmethod

    method Action deq if (!empty[0]);
        call_deq.wset(?);
    endmethod

    method t first if (!empty[0]);
        return data[deqP[0]];
    endmethod

    method Action clear;
        enqP[1] <= 0;
        deqP[1] <= 0;
        empty[1] <= True;
        full[1] <= False;
    endmethod
endmodule

