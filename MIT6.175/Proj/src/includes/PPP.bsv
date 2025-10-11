import ProcTypes::*;
import MemTypes::*;
import Types::*;
import CacheTypes::*;
import MessageFifo::*;
import Vector::*;
import FShow::*;

function Bool isCompatible(MSI a,MSI b);
    return (a == I) || (b == I) || (a == b && a == S);
endfunction

typedef enum {Idle, Wait} PRState deriving(Eq, Bits, FShow);

module mkPPP(MessageGet c2m, MessagePut m2c, WideMem mem, Empty ifc);

    Vector#(CoreNum, Vector#(CacheRows, Reg#(MSI))) childState <- replicateM(replicateM(mkReg(I)));
    Vector#(CoreNum, Vector#(CacheRows, Reg#(CacheTag))) childTag <- replicateM(replicateM(mkRegU));

    // TODO 是否可以减小为 Vector#(CoreNum, Reg#(Bool)) 同时增加当前req状态指示
    Vector#(CoreNum, Vector#(CacheRows, Reg#(Bool))) waitc <- replicateM(replicateM(mkReg(False)));

    Reg#(PRState) pRState <- mkReg(Idle);

    // 用于解决rule冲突
    // TODO：尝试使用 Wire 类型实现结果失败了，为什么？
    RWire#(void) sendS2MResp <- mkRWire;

    (* descending_urgency = "parentRespSend,parentRespSendS2MResp" *)
    rule parentRespSendS2MResp(c2m.first matches tagged Req .req);
        if(isValid(sendS2MResp.wget)) begin
            let reqIndex = getIndex(req.addr);

            // update state
            childState[req.child][reqIndex] <= req.state;
            // deal req
            c2m.deq;
            m2c.enq_resp(CacheMemResp{child: req.child, addr: req.addr, state: req.state, data: tagged Invalid});
        end
    endrule

    // 为了正确运行
    

    rule parentResp(pRState == Idle &&& c2m.first matches tagged Req .req);
        let reqIndex = getIndex(req.addr);
        let reqTag = getTag(req.addr);
        
        let cState = childState[req.child][reqIndex];

        // for debug
        if(req.state <= cState) begin
            $fwrite(stderr, "Error: PPP receive req from core %0d, but req state %0d not higher than current state %0d\n", req.child, req.state, cState);
            $finish;
        end

        Bool comp = True;

        for(Integer i = 0; i < valueOf(CoreNum); i = i + 1) begin
            if(fromInteger(i) != req.child) begin
                let st = childState[i][reqIndex];
                let tg = childTag[i][reqIndex];
                // for debug
                if(tg == reqTag) begin
                    if(!isCompatible(st, req.state) || waitc[i][reqIndex]) begin
                        comp = False;
                    end
                end
                
            end
        end

        if(comp) begin
            if(cState == S && reqTag == childTag[req.child][reqIndex]) begin
                $display("PPP directly respond to core %0d", req.child);
                sendS2MResp.wset(?);   

                // update state
                // childState[req.child][reqIndex] <= req.state;
                // // deal req
                // c2m.deq;
                // m2c.enq_resp(CacheMemResp{child: req.child, addr: req.addr, state: req.state, data: tagged Invalid});
            end else if(cState == I) begin
                let wideReq = WideMemReq{
                    write_en: 0,
                    addr: {reqTag, reqIndex, 0},
                    data: ?
                };
                mem.req(wideReq);
                pRState <= Wait;
            end else begin
                // for debug
                $fwrite(stderr, "Error: PPP receive req from core %0d, but state is %0d\n", req.child, cState);
                $finish;
            end
        end
    endrule



    rule parentRespSend(pRState == Wait &&& c2m.first matches tagged Req .req);
        let reqIndex = getIndex(req.addr);
        let reqTag = getTag(req.addr);

        CacheLine wideResp <- mem.resp();

        // update state
        childState[req.child][reqIndex] <= req.state;
        childTag[req.child][reqIndex] <= reqTag;

        // deal req
        c2m.deq;
        m2c.enq_resp(CacheMemResp{child: req.child, addr: req.addr, state: req.state, data: tagged Valid wideResp});

        pRState <= Idle;
    endrule

    rule dwn(c2m.first matches tagged Req .req);
        let reqIndex = getIndex(req.addr);
        let reqTag = getTag(req.addr);
        let downTarget = case(req.state)
            M: I;
            S: S;
            I : begin
                let dummy1 = $fwrite(stderr, "Error: PPP receive req from core %0d, but req state %0d invalid\n", req.child, req.state);
                let dummy2 = $finish;
                return ?;
            end// should not happen
        endcase;

        Maybe#(CoreID) downCoreId = Invalid;
        
        for (Integer i = 0; i < valueOf(CoreNum); i = i + 1) begin
           if(fromInteger(i) != req.child) begin
                let st = childState[i][reqIndex];
                let tg = childTag[i][reqIndex];
                if(tg == reqTag && st > downTarget && !waitc[i][reqIndex]) begin
                    downCoreId = tagged Valid fromInteger(i);
                end
           end 
        end

        if(downCoreId matches tagged Valid .cid) begin
            // send down req
            m2c.enq_req(CacheMemReq{child: cid, addr: req.addr, state: downTarget});
            waitc[cid][reqIndex] <= True;
        end 
    endrule

    rule dwnRsp(c2m.first matches tagged Resp .resp);

        // deal resp
        c2m.deq;

        let reqIndex = getIndex(resp.addr);
        let reqTag = getTag(resp.addr);

        // for debug
        if(reqTag != childTag[resp.child][reqIndex]) begin
            $fwrite(stderr, "Error: PPP receive resp from core %0d, but tag not match\n", resp.child);
            $finish;
        end
        //update child state
        childState[resp.child][reqIndex] <= resp.state;

        waitc[resp.child][reqIndex] <= False;

        // write back data to mem
        if(resp.data matches tagged Valid .data) begin
            let wideReq = WideMemReq{
                write_en: '1,
                addr: {reqTag, reqIndex, 0},
                data: data
            };
            mem.req(wideReq);
        end

    endrule

endmodule