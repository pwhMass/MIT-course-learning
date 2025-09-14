// Reference functions that use Bluespec's '*' operator
function Bit#(TAdd#(n,n)) multiply_unsigned( Bit#(n) a, Bit#(n) b );
    UInt#(n) a_uint = unpack(a);
    UInt#(n) b_uint = unpack(b);
    UInt#(TAdd#(n,n)) product_uint = zeroExtend(a_uint) * zeroExtend(b_uint);
    return pack( product_uint );
endfunction

function Bit#(TAdd#(n,n)) multiply_signed( Bit#(n) a, Bit#(n) b );
    Int#(n) a_int = unpack(a);
    Int#(n) b_int = unpack(b);
    Int#(TAdd#(n,n)) product_int = signExtend(a_int) * signExtend(b_int);
    return pack( product_int );
endfunction



// Multiplication by repeated addition
function Bit#(TAdd#(n,n)) multiply_by_adding( Bit#(n) a, Bit#(n) b )
    provisos(Add#(1, b__, n) );
    
    // TODO: Implement this function in Exercise 2
    Bit#(TAdd#(n,n)) result = 0;
    for (Integer i = 0; i < (valueOf(n)); i = i + 1) begin
        Bit#(TAdd#(n,1)) add_r = zeroExtend(b[i] == 1 ? a : 0);
        result[(i+valueOf(n)):i] = result[(i+valueOf(n)):i] + add_r;
    end
    return result;
endfunction



// Multiplication by repeated addition
function Bit#(TAdd#(n,n)) multiply_by_adding_2( Bit#(n) a, Bit#(n) b );
    
    Bit#(TAdd#(n,n)) result = 0;
    for (Integer i = 0; i < (valueOf(n)); i = i + 1) begin
        Bit#(TAdd#(n,n)) add_r = zeroExtend((b[i] == 1 ? a : 0)) << i;
        result = result + add_r;
    end
    return result;
endfunction

// Multiplier Interface
interface Multiplier#( numeric type n );
    method Bool start_ready();
    method Action start( Bit#(n) a, Bit#(n) b );
    method Bool result_ready();
    method ActionValue#(Bit#(TAdd#(n,n))) result();
endinterface


// Folded multiplier by repeated addition
module mkFoldedMultiplier( Multiplier#(n) )
    provisos(Add#(1, a__, n));
    // You can use these registers or create your own if you want
    Reg#(Bit#(n)) a <- mkRegU();
    Reg#(Bit#(n)) b <- mkRegU();
    Reg#(Bit#(n)) prod <- mkRegU();
    Reg#(Bit#(n)) tp <- mkRegU();
    Reg#(Bit#(TAdd#(TLog#(n),1))) i <- mkReg( fromInteger(valueOf(n)+1) );

    rule mulStep( i < fromInteger(valueOf(n)) );
        i <= i + 1;
        Bit#(TAdd#(n,1)) add_r = zeroExtend(prod) + zeroExtend(b[i] == 1 ? a : 0);
        prod <= truncateLSB(add_r);
        tp <= {add_r[0],tp[valueOf(n)-1:1]};
    endrule

    method Bool start_ready();
        return i == fromInteger(valueOf(n)+1);
    endmethod

    method Action start( Bit#(n) aIn, Bit#(n) bIn );
        a <= aIn;
        b <= bIn;
        tp <= 0;
        prod <= 0;
        i <= 0;
    endmethod

    method Bool result_ready();
        // TODO: Implement this in Exercise 4
        return i == fromInteger(valueOf(n));
    endmethod

    method ActionValue#(Bit#(TAdd#(n,n))) result();
        i <= i + 1;
        return {prod, tp};
    endmethod
endmodule


// Folded multiplier by repeated addition
module mkFoldedMultiplier_wrong( Multiplier#(n) );
    // You can use these registers or create your own if you want
    Reg#(Bit#(n)) a <- mkRegU();
    Reg#(Bit#(n)) b <- mkRegU();
    Reg#(Bit#(TAdd#(n,n))) prod <- mkRegU();

    Reg#(Bit#(TAdd#(TLog#(n),1))) i <- mkReg( fromInteger(valueOf(n)+1) );

    rule mulStep( i < fromInteger(valueOf(n)) );
        i <= i + 1;
        prod <= prod + (b[i] == 1 ? (zeroExtend(a) << i) : 0);
    endrule

    method Bool start_ready();
        return i == fromInteger(valueOf(n)+1);
    endmethod

    method Action start( Bit#(n) aIn, Bit#(n) bIn );
        a <= aIn;
        b <= bIn;
        prod <= 0;
        i <= 0;
    endmethod

    method Bool result_ready();
        // TODO: Implement this in Exercise 4
        return i == fromInteger(valueOf(n));
    endmethod

    method ActionValue#(Bit#(TAdd#(n,n))) result();
        i <= i + 1;
        return prod;
    endmethod
endmodule

function Bit#(n) arthmeticShiftRightOne( Bit#(n) x)
    provisos( Add#(1, a__, n) );
    return {x[valueOf(n)-1], x[valueOf(n)-1:1]};
endfunction

function Bit#(n) arthmeticShiftRight( Bit#(n) x, Integer power );
    Int#(n) t = unpack(x);
    t = t >> power;
    return pack(t);
endfunction


// Booth Multiplier
module mkBoothMultiplier( Multiplier#(n) );
    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) m_neg <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) m_pos <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) p <- mkRegU;
    Reg#(Bit#(TAdd#(TLog#(n),1))) i <- mkReg( fromInteger(valueOf(n)+1) );

    rule mul_step( i < fromInteger(valueOf(n)) );
        let pr = p[1:0];
        Bit#(TAdd#(TAdd#(n,n),1)) pe = case(pr) matches
            2'b01: arthmeticShiftRightOne( p + m_pos );
            2'b10: arthmeticShiftRightOne( p + m_neg );
            default: arthmeticShiftRightOne( p );
        endcase;

        p <= pe;
        i <= i + 1;
    endrule

    method Bool start_ready();
        return i == fromInteger(valueOf(TAdd#(n,1)));
    endmethod

    method Action start( Bit#(n) m, Bit#(n) r );
        // TODO: Implement this in Exercise 6
        m_pos <= {m,0};
        m_neg <= {-m,0};
        p <= {0,r,1'b0};
        i <= 0;

    endmethod

    method Bool result_ready();
        // TODO: Implement this in Exercise 4
        return i == fromInteger(valueOf(n));
    endmethod

    method ActionValue#(Bit#(TAdd#(n,n))) result();
        i <= i + 1;
        //TODO
        return p[valueOf(TAdd#(n,n)):1];
    endmethod
endmodule


// Booth Multiplier
module mkBoothMultiplier_2( Multiplier#(n) );
    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) m_neg <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) m_pos <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) p <- mkRegU;
    Reg#(Bit#(TAdd#(TLog#(n),1))) i <- mkReg( fromInteger(valueOf(n)+1) );

    rule mul_step( i < fromInteger(valueOf(n)) );
        let pr = p[1:0];
        Bit#(TAdd#(TAdd#(n,n),2)) pe = case(pr) matches
            2'b01: arthmeticShiftRightOne( signExtend(p) + signExtend(m_pos) );
            2'b10: arthmeticShiftRightOne( signExtend(p) + signExtend(m_neg) );
            default: arthmeticShiftRightOne( signExtend(p) );
        endcase;
        p <= truncate(pe);
        i <= i + 1;
    endrule

    method Bool start_ready();
        return i == fromInteger(valueOf(TAdd#(n,1)));
    endmethod

    method Action start( Bit#(n) m, Bit#(n) r );
        // TODO: Implement this in Exercise 6
        m_pos <= {m,0};
        m_neg <= {-m,0};

        p <= {0,r,1'b0};
        i <= 0;

    endmethod

    method Bool result_ready();
        // TODO: Implement this in Exercise 4
        return i == fromInteger(valueOf(n));
    endmethod

    method ActionValue#(Bit#(TAdd#(n,n))) result();
        i <= i + 1;
        // QUESTION: 你**为什么不报错，左右明显不一样宽
        // Bit#(TAdd#(n,n)) ppp = p[(valueOf(TAdd#(n,n))-1):1];
        // $display("result: m=%d", valueOf(TAdd#(n,n)));
        return p[valueOf(TAdd#(n,n)):1];
    endmethod
endmodule

// Radix-4 Booth Multiplier
module mkBoothMultiplierRadix4( Multiplier#(n) )
    provisos( Div#(n, 2, half_n), Add#(1, a__, half_n) );
    Reg#(Bit#(TAdd#(TAdd#(n,n),2))) m_neg <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),2))) m_pos <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),2))) p <- mkRegU;
    Reg#(Bit#(TAdd#(TLog#(n),1))) i <- mkReg( fromInteger(valueOf(n)/2+1) );

    rule mul_step( i < fromInteger(valueOf(n)/2) );
        let pr = p[2:0];

        Bit#(TAdd#(TAdd#(n,n),2)) pe = case(pr) matches
            3'b001: return p + m_pos ;
            3'b010: return p + (m_pos << 1) + m_neg ;
            3'b011: return p + (m_pos << 1) ;
            3'b100: return p + (m_neg << 1) ;
            3'b101: return p + (m_neg << 1) + m_pos ;
            3'b110: return p + m_neg ;
            default: return p ;
        endcase;

    p <= pack((Int#(TAdd#(TAdd#(n,n),2))'(unpack(pe))) >> 2);
    i <= i + 1;
    endrule

    method Bool start_ready();
        return i == fromInteger(valueOf(n)/2+1);
    endmethod

    method Action start( Bit#(n) m, Bit#(n) r );
        // TODO: Implement this in Exercise 8
        m_pos <= {msb(m),m,0};
        m_neg <= {msb(-m),-m,0};

        p <= {0,r,1'b0};
        i <= 0;
    endmethod

    method Bool result_ready();
        return i == fromInteger(valueOf(n)/2);
    endmethod

    method ActionValue#(Bit#(TAdd#(n,n))) result();
        // TODO: Implement this in Exercise 8
        i <= i + 1;
        $display("result: p=%b", p);
        return p[valueOf(TAdd#(n,n)):1];
    endmethod
endmodule

