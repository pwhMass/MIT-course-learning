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

    Reg#(Maybe#(CacheLineAddr)) linkAddr <- mkReg(Invalid);

    Fifo#(2, Data) hitQ <- mkBypassFifo;
    Fifo#(1, MemReq) reqQ <- mkBypassFifo;

    Reg#(CacheStatus) mshr <- mkReg(Ready);
    Reg#(MemReq) missReq <- mkRegU;

    function Bool isLoad(MemOp op);
        return op == Ld || op == Lr;
    endfunction


    //TODO 这样的优先级顺序对吗？
    (* descending_urgency = "dng, startReq, startReqSc, startReqFence" *)
    rule startReq(mshr == Ready && reqQ.first.op != Sc && reqQ.first.op != Fence);
        MemReq r = reqQ.first;
        reqQ.deq;

        let index = getIndex(r.addr);
        let tag = getTag(r.addr);
        let wordSelect = getWordSelect(r.addr);


        let hit = state[index] != I && tagArray[index] == tag;

        if(hit) begin
            // cache hit

            if(isLoad(r.op)) begin
                refDMem.commit(r,tagged Valid dataArray[index],tagged Valid dataArray[index][wordSelect]);
                hitQ.enq(dataArray[index][wordSelect]);
                if(r.op == Lr) begin
                    linkAddr <= tagged Valid getLineAddr(r.addr);
                end
            end
            else begin // it is store
                if (state[index] == M) begin
                    let tempLine = dataArray[index];
                    refDMem.commit(r, tagged Valid tempLine, tagged Invalid);
                    let updatedLine = update(tempLine, wordSelect, r.data);
                    dataArray[index] <= updatedLine;
                end
                else begin
                    missReq <= r;
                    mshr <= SendFillReq;
                end
            end
        end
        else begin
            // cache miss
            // TODO 是否可以判定是否为 I 来直接跳转到 SendFillReq
            missReq <= r; mshr <= StartMiss;
        end

    endrule

    rule startReqSc(mshr == Ready && reqQ.first.op == Sc);
        MemReq r = reqQ.first;
        reqQ.deq;

        let index = getIndex(r.addr);
        let tag = getTag(r.addr);
        let wordSelect = getWordSelect(r.addr);

        if(linkAddr matches tagged Valid .la &&& la == getLineAddr(r.addr)) begin
            //for debug
            if(tagArray[index] != tag || state[index] == I) begin
                $fwrite(stderr, "Error: DCache tag or state mismatch!,tag is %0h, state is %0h\n", tagArray[index], state[index]);
                $finish;
            end
            if (state[index] == M) begin
                hitQ.enq(scSucc);
                let tempLine = dataArray[index];
                let updatedLine = update(tempLine, wordSelect, r.data);
                dataArray[index] <= updatedLine;
                refDMem.commit(r, tagged Valid tempLine, tagged Valid scSucc);
                linkAddr <= Invalid;
            end
            else begin
                missReq <= r;
                mshr <= SendFillReq;
            end
        end
        else begin
            hitQ.enq(scFail);
            refDMem.commit(r, tagged Invalid, tagged Valid scFail);
            linkAddr <= Invalid;
        end

    
    endrule

    rule startReqFence(mshr == Ready && reqQ.first.op == Fence);
        $fwrite(stderr, "Error: DCache does not support Fence operation!\n");
        $finish;
    endrule

    rule startMiss(mshr == StartMiss);
        let index = getIndex(missReq.addr);
        let cTag = tagArray[index];

        if(state[index] != I) begin
            // for linkAddr
            if(linkAddr matches tagged Valid .la &&& {cTag,index} == la) begin
                linkAddr <= Invalid;
            end
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

        let s = isLoad(missReq.op) ? S : M;
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


        // update cache line
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
            refDMem.commit(missReq,tagged Valid newCacheLine,tagged Invalid);
            newCacheLine[wordSelect] = missReq.data;
        end 
        else if(missReq.op == Sc) begin
            if(linkAddr matches tagged Valid .la &&& getLineAddr(resp.addr) == la) begin
                hitQ.enq(scSucc);
                refDMem.commit(missReq, tagged Valid newCacheLine, tagged Valid scSucc);
                newCacheLine[wordSelect] = missReq.data;
                linkAddr <= Invalid;
            end
            else begin
                hitQ.enq(scFail);
                refDMem.commit(missReq, tagged Invalid, tagged Valid scFail);
                linkAddr <= Invalid;
            end
        end
        dataArray[index] <= newCacheLine;
        mshr <= Resp;
    endrule

    rule sendProc(mshr == Resp);
        let index = getIndex(missReq.addr);
        let tag = getTag(missReq.addr);
        let wordSelect = getWordSelect(missReq.addr);

        if(missReq.op == Ld) begin 
            refDMem.commit(missReq,tagged Valid dataArray[index],tagged Valid dataArray[index][wordSelect]);
            hitQ.enq(dataArray[index][wordSelect]); 
        end
        else if(missReq.op == Lr) begin 
            refDMem.commit(missReq,tagged Valid dataArray[index],tagged Valid dataArray[index][wordSelect]);
            hitQ.enq(dataArray[index][wordSelect]); 
            linkAddr <= tagged Valid getLineAddr(missReq.addr);
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

            // for linkAddr
            if(linkAddr matches tagged Valid .la &&& getLineAddr(req.addr) == la &&& req.state == I) begin
                linkAddr <= Invalid;
            end
        
            // deal with downgrade request
            state[index] <= req.state;
            // TODO: 是否应该增加 clear 来满足与 req 互斥的情况？
            // dataArray[index] <= replicate(0); // clear data

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
        refDMem.issue(r);

        reqQ.enq(r);
    endmethod


    method ActionValue#(MemResp) resp;
        hitQ.deq;
        return hitQ.first;
    endmethod
endmodule