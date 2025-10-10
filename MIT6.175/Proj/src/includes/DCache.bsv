import CacheTypes::*;
import Vector::*;
import FShow::*;
import MemTypes::*;
import Types::*;
import ProcTypes::*;
import Fifo::*;
import Ehr::*;
import RefTypes::*;



typedef enum{Ready, StartMiss, SendFillReq, WaitFillResp, Resp} CacheStatus
    deriving(Eq, Bits);
module mkDCache#(CoreID id)(
        MessageGet fromMem,
        MessagePut toMem,
        RefDMem refDMem,
        DCache ifc);

    Vector#(CacheRows, Reg#(MSI)) state <- replicateM(mkReg(I));
    Vector#(CacheRows, Reg#(CacheTag)) tagArray <- replicateM(mkRegU);
    Vector#(CacheRows, Reg#(CacheLine)) dataArray <- replicateM(mkRegU);

    Fifo#(3,MemResp) hitQ <- mkCFFifo;

    Reg#(CacheStatus) mshr <- mkReg(Ready);
    Reg#(MemReq) missReq <- mkRegU;


    //for test
    // rule logState;
    //     $display("DCache %0d state: mshr=%0d", id, mshr);
    // endrule
    
    // TODO 如何指定method 和 rule之间的优先级？
    // (* descending_urgency = "req, dng" *)

    rule startMiss(mshr == StartMiss);
        let index = getIndex(missReq.addr);
        let tag = getTag(missReq.addr);

        if(state[index] != I) begin
            // invalidate the state
            state[index] <= I;
            // send write-back request
            let data = state[index] == M ? tagged Valid dataArray[index] : tagged Invalid;
            toMem.enq_resp(CacheMemResp {child: id, addr: {tagArray[index], index, 0}, state: I, data: data});
        end 

        mshr <= SendFillReq;

    //参考
//   let slot = findVictimSlot(state, missReq.addr); 
//   if(!isStateI(state[slot])) 
//     begin // write-back (Evacuate)
//       let a = getAddr(state[slot]);
//       let d = (isStateM(state[slot])? dataArray[slot]: -);
//       state[slot] <= (I, _);
//       c2m.enq(<Resp, c->m, a, I, d>); end
//   mshr <= SendFillReq; missSlot <= slot; 
    endrule 

    rule sendFillReq(mshr == SendFillReq);

        let s = missReq.op == Ld ? S : M;
        toMem.enq_req(CacheMemReq {child: id, addr: missReq.addr, state: s});
        mshr <= WaitFillResp;
    endrule

    rule waitFillResp(mshr == WaitFillResp &&& fromMem.first matches tagged Resp .resp); 
        // $display("DCache %0d receive fill response: %0h", id, fromMem.first);    

        fromMem.deq;

        // assert
        if(getLineAddr(resp.addr) != getLineAddr(missReq.addr)) begin
            $fwrite(stderr, "Error: DCache receive fill response address mismatch!\n");
            $finish;
        end

        let index = getIndex(resp.addr);
        let tag = getTag(resp.addr);
        let wordSelect = getWordSelect(missReq.addr);


        // // update cache line
        state[index] <= resp.state;
        tagArray[index] <= tag;

        let newCacheLine = dataArray[index];
        if(resp.data matches tagged Valid .data) begin
            // $display("DCache %0d update cache line %0d with data %0h", id, index, data);
            newCacheLine = data;
        end else begin
            // $display("Warning: DCache receive fill response with no data!\n");
        end
        if(missReq.op == St) begin
            newCacheLine[wordSelect] = missReq.data;
        end
        dataArray[index] <= newCacheLine;
        mshr <= Resp;
    endrule

    rule sendProc(mshr == Resp);
        let index = getIndex(missReq.addr);
        let tag = getTag(missReq.addr);
        let wordSelect = getWordSelect(missReq.addr);

        if(missReq.op == Ld) begin 
            hitQ.enq(dataArray[index][wordSelect]); 
        end
        mshr <= Ready;
    endrule 



    // TODO: mshr != Resp 这个条件是不是不必要的？
    rule dng (mshr != Resp &&& mshr != StartMiss &&& fromMem.first matches tagged Req .req); 
        let index = getIndex(req.addr);
        let tag = getTag(req.addr);

        if(state[index] > req.state) begin
            // DEBUG: 应该能成立
            if(tagArray[index] != tag) begin
                $fwrite(stderr, "Error: DCache tag mismatch!\n");
                $finish;
            end

            // deal with downgrade request
            state[index] <= req.state;
            // TODO: 是否应该增加 clear 来满足与 req 互斥的情况？
            dataArray[index] <= replicate(0); // clear data

            // send downgrade request to PPP
            let data = state[index] == M ? tagged Valid dataArray[index] : tagged Invalid;
            toMem.enq_resp(CacheMemResp {child: id, addr: req.addr, state: req.state, data: data});
        end else begin
            // the address has already been downgraded
            $display("Warning: DCache receive downgrade request but state is %0d", state[index]);
        end

        fromMem.deq;
    endrule 

    method Action req(MemReq r) if(mshr == Ready);

        let index = getIndex(r.addr);
        let tag = getTag(r.addr);
        let wordSelect = getWordSelect(r.addr);


        let hit = state[index] != I && tagArray[index] == tag;

        if(hit) begin
            // cache hit
            let cLine = dataArray[index];
            if(r.op == Ld) hitQ.enq(dataArray[index][wordSelect]);
            else  begin// it is store
                if (state[index] == M)
                    dataArray[index][wordSelect] <= r.data;
                else 
                    begin missReq <= r; mshr <= SendFillReq; end
            end
        end 
        else begin
            // cache miss
            // TODO 是否可以判定是否为 I 来直接跳转到 SendFillReq
            missReq <= r; mshr <= StartMiss;
        end

    endmethod


    method ActionValue#(MemResp) resp;
        hitQ.deq;
        return hitQ.first;
    endmethod
endmodule