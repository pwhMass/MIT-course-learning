import Vector::*;
import CacheTypes::*;
import MessageFifo::*;
import Types::*;


module mkMessageRouter(
        Vector#(CoreNum, MessageGet) c2r,
        Vector#(CoreNum, MessagePut) r2c,
        MessageGet m2r,
        MessagePut r2m,
        Empty ifc
        );

    rule routem2c;
        // $display("Routing from mem to core");
        let msg = m2r.first;
        case (msg) matches
            tagged Req .req : r2c[req.child].enq_req(req);
            tagged Resp .resp : r2c[resp.child].enq_resp(resp);
        endcase
        m2r.deq;
    endrule

    Reg#(CoreID) start <- mkReg(0);
    rule routesc2m;
        Maybe#(Tuple2#(CoreID,CacheMemReq)) req_msg = tagged Invalid;
        Maybe#(Tuple2#(CoreID,CacheMemResp)) resp_msg = tagged Invalid;
        start <= start + 1;

        for (Integer j = 0; j < valueOf(CoreNum); j = j + 1) begin
            CoreID i = start + fromInteger(j);
            
            if (c2r[i].notEmpty) begin
                let msg = c2r[i].first;
                case (msg) matches
                    tagged Req .req : req_msg = tagged Valid tuple2(i,req);
                    tagged Resp .resp : resp_msg = tagged Valid tuple2(i,resp);
                endcase
            end 
        end
        if(resp_msg matches tagged Valid {.core_id, .msg}) begin
            // $display("Routing resp from core %0d to mem", core_id);
            c2r[core_id].deq;
            r2m.enq_resp(msg);
        end 
        else if(req_msg matches tagged Valid {.core_id, .msg}) begin
            // $display("Routing req from core %0d to mem", core_id);
            c2r[core_id].deq;
            r2m.enq_req(msg);
        end

    endrule
endmodule