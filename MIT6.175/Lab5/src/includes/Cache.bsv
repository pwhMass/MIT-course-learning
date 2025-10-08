import Fifo::*;
import Vector::*;
import MemTypes::*;
import CacheTypes::*;
import MemUtil::*;
import Types::*;



module mkTranslator(WideMem mem,Cache ifc);

    Fifo#(2,CacheWordSelect) reqQ <- mkCFFifo();
    method Action req(MemReq r);
        reqQ.enq(getWordSelect(r.addr));
        
        CacheLine data = replicate(0);
        if(r.op == St) begin  
            data[getWordSelect(r.addr)] = r.data;  
        end 

        let wideReq = WideMemReq{
            write_en: (r.op == St) ? (1 << getWordSelect(r.addr)) : 0,
            addr: r.addr,
            data: data
        };
        mem.req(wideReq);
    endmethod

	method ActionValue#(MemResp) resp;
        reqQ.deq;
        let res <- mem.resp;

        return res[reqQ.first];
    endmethod

endmodule



typedef struct {
    Bool valid;
    CacheTag tag;
    CacheLine data;
} FullCacheLine deriving(Eq,Bits);

typedef enum {Idle, DealMiss, WriteBack, DealData} CacheState deriving(Eq,Bits);


module mkCache(WideMem mem,Cache ifc);

    Reg#(MemReq) missReq <- mkRegU();
    Reg#(CacheState) state <- mkReg(Idle);
    Vector#(CacheRows, Reg#(FullCacheLine)) cache <- replicateM(mkReg(FullCacheLine{valid: False, tag: 0, data: replicate(0)}));

    Fifo#(2, MemResp) outQ <- mkBypassFifo();

    // Reg#(Vector#(CacheRows, FullCacheLine)) cache <- mkReg(replicate(FullCacheLine{valid: False, tag: 0, data: replicate(0)}));
    

    rule handleMiss if (state == DealMiss);
        let r = missReq;
        let idx = getIndex(r.addr);
        let tag = getTag(r.addr);
        let wordSel = getWordSelect(r.addr);
        let cacheLine = cache[idx];

        if(cacheLine.valid) begin
            // Need to write back
            state <= WriteBack;
            // Write back the old cache line
            let wideReq = WideMemReq{
                write_en: '1,
                addr: {cacheLine.tag, idx, 0},
                data: cacheLine.data
            };
            mem.req(wideReq);
        end else begin
            // No need to write back
            state <= DealData;

            let wideReq = WideMemReq{
                write_en: 0,
                addr: r.addr,
                data: ?
            };
            mem.req(wideReq);
        end
    endrule

    rule handleWriteBack if (state == WriteBack);
        let r = missReq;
        let idx = getIndex(r.addr);
        // let tag = getTag(r.addr);
        // let wordSel = getWordSelect(r.addr);
        let cacheLine = cache[idx];
        // After write back, fetch the new cache line
        let wideReq = WideMemReq{
            write_en: 0,
            addr: r.addr,
            data: ?
        };
        mem.req(wideReq);
        state <= DealData;
    endrule

    rule handleData if (state == DealData);
        let r = missReq;
        let idx = getIndex(r.addr);
        let tag = getTag(r.addr);
        let wordSel = getWordSelect(r.addr);
        let res <- mem.resp;


        let data = res;
        if(r.op == St) begin
            // If it's a store, update the cache line with the new data
            data[wordSel] = r.data;
        end
        else begin
            // Return the requested word
            outQ.enq(res[wordSel]);
        end
        
        // Update the cache line
        cache[idx] <= FullCacheLine{
            valid: True,
            tag: tag,
            data: data
        };
        
        state <= Idle;
    endrule

    method Action req(MemReq r) if (state == Idle);
        let idx = getIndex(r.addr);
        let tag = getTag(r.addr);
        let wordSel = getWordSelect(r.addr);

        let cacheLine = cache[idx];

        if(cacheLine.valid && cacheLine.tag == tag) begin
            // Cache hit
            if(r.op == St) begin
                let data = cacheLine.data;
                data[wordSel] = r.data;
                cache[idx] <= FullCacheLine{
                    valid: True,
                    tag: tag,
                    data: data
                };
            end
            else begin
                outQ.enq(cacheLine.data[wordSel]);
            end
        end else begin
            // Cache miss
            missReq <= r;
            state <= DealMiss;
        end
    endmethod

	method ActionValue#(MemResp) resp;
        outQ.deq;
        return outQ.first;
    endmethod

endmodule