// SixStageBHT.bsv
//
// This is a six stage pipelined implementation of the RISC-V processor.

import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import MemInit::*;
import RFile::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;
import Scoreboard::*;
import Btb::*;
import DelayedMemory::*;
import Bht::*;  

typedef Bit#(1) Epoch;

// Pipeline register: Fetch -> Decode
typedef struct {
    Addr pc;
    Addr predPc;
    Epoch eEpoch;
    Epoch dEpoch;
} Fetch2Decode deriving (Bits, Eq);

// Pipeline register: Decode -> Register Fetch
typedef struct {
    DecodedInst dInst;
    Addr pc;
    Addr predPc;
    Epoch eEpoch;
} Decode2RegFetch deriving (Bits, Eq);

// Pipeline register: Register Fetch -> Execute
typedef struct {
    DecodedInst dInst;
    Data rVal1;
    Data rVal2;
    Data csrVal;
    Addr pc;
    Addr predPc;
    Epoch eEpoch;
} RegFetch2Execute deriving (Bits, Eq);

// Pipeline register: Execute -> Memory
typedef struct {
    Addr pc;
    ExecInst eInst;
    Bool isPoisoned;
} Execute2Memory deriving (Bits, Eq);

// Pipeline register: Memory -> Write Back
typedef struct {
    Addr pc;
    ExecInst eInst;
    Bool isPoisoned;
} Memory2WriteBack deriving (Bits, Eq);

typedef 8 FifoDepth;

(* synthesize *)
module mkProc(Proc);
    Ehr#(3, Addr) pc <- mkEhrU;
    RFile         rf <- mkRFile;
    DelayedMemory     iMem <- mkDelayedMemory;
    DelayedMemory     dMem <- mkDelayedMemory;
    CsrFile     csrf <- mkCsrFile;

    // Scoreboard
    // TODO : 也许可以使用 pipeline 提高性能
    Scoreboard#(8) sb <- mkCFScoreboard;
    // Btb
    Btb#(8) btb <- mkBtb;
    // Bht
    DirectionPred#(8) bht <- mkBHT;
    Reg#(Epoch) dEpoch <- mkReg(0);

    // TODO: Instantiate 5 FIFOs for pipeline stages
    Fifo#(FifoDepth, Fetch2Decode) f2d <- mkCFFifo;
    Fifo#(FifoDepth, Decode2RegFetch) d2rf <- mkCFFifo;
    Fifo#(FifoDepth, RegFetch2Execute) rf2e <- mkCFFifo;
    Fifo#(FifoDepth, Execute2Memory) e2m <- mkCFFifo;
    Fifo#(FifoDepth, Memory2WriteBack) m2wb <- mkCFFifo;

    Reg#(Epoch) eEpoch <- mkReg(0);

    // Stage 1: Instruction Fetch
    // Request instruction from iMem and update PC
    rule doFetch(csrf.started);

        iMem.req(MemReq {op:Ld,addr:pc[0],data:?});

        let ppc = btb.predPc(pc[0]);
        pc[0] <= ppc;

        f2d.enq(Fetch2Decode {pc: pc[0], predPc: ppc, eEpoch: eEpoch,dEpoch: dEpoch});

        $display("[F ] pc: %h predPc: %h epoch: %b", pc[0], ppc, eEpoch);
    endrule

    // Stage 2: Decode
    // Receive response from iMem and decode instruction
    rule doDecode(csrf.started);
        f2d.deq;
        let f2dEle = f2d.first;
        let inst <- iMem.resp;

        // TODO: 提前丢弃是否能获得更好的性能？
        if(f2dEle.eEpoch == eEpoch && f2dEle.dEpoch == dEpoch) begin
            let dInst = decode(inst);
            if(dInst.iType == Br || dInst.iType == J)begin
                let bhtPpc = case(dInst.iType)
                    Br  : return bht.ppcDP(f2dEle.pc, f2dEle.predPc);
                    J : return f2dEle.pc + fromMaybe(?, dInst.imm);
                    default : return 0; 
                endcase;

                if(bhtPpc != f2dEle.predPc) begin
                    // Branch predicted correctly
                    f2dEle.predPc = bhtPpc;
                    // MISPREDICTED
                    pc[1] <= bhtPpc;
                    dEpoch <= ~dEpoch;
                    //enq to d2rf
                    $display("[D ] pc: %h BRANCH MISPREDICTED! redirect to %h, epoch flip to %b", f2dEle.pc, bhtPpc, ~dEpoch);
                end
            end
            d2rf.enq(Decode2RegFetch {dInst:dInst, pc: f2dEle.pc,predPc: f2dEle.predPc,eEpoch: f2dEle.eEpoch });
         
        end

        $display("[D ] pc: %h inst: %h epoch: %b expanded: %s", f2dEle.pc, inst, f2dEle.eEpoch, showInst(inst));
    endrule

    // Stage 3: Register Fetch
    // Read from the register file
    rule doRegisterFetch(csrf.started);
        // read general purpose register values
        let element = d2rf.first;

        // TODO: 为 csr 增加 sb 检查
        if (!sb.search1(element.dInst.src1) && !sb.search2(element.dInst.src2)) begin
            // enq sb
            sb.insert(element.dInst.dst);

            Data rVal1 = rf.rd1(fromMaybe(?, element.dInst.src1));
            Data rVal2 = rf.rd2(fromMaybe(?, element.dInst.src2));

            // read CSR values (for CSRR inst)
            let csrVal = csrf.rd(fromMaybe(?, element.dInst.csr));

            d2rf.deq;
            rf2e.enq(RegFetch2Execute {dInst: element.dInst, rVal1: rVal1, rVal2: rVal2, pc: element.pc, predPc: element.predPc, eEpoch: element.eEpoch, csrVal: csrVal});

            $display("[RF] pc: %h rVal1: %h rVal2: %h csrVal: %h epoch: %b", element.pc, rVal1, rVal2, csrVal, element.eEpoch);
        end else begin
            $display("[RF] pc: %h STALLED (scoreboard conflict)", element.pc);
        end

    endrule

    // Stage 4: Execute
    // Execute the instruction and redirect the processor if necessary
    rule doExecute(csrf.started);
        let element = rf2e.first;
        rf2e.deq;
        let dInst = element.dInst;
        let rVal1 = element.rVal1;
        let rVal2 = element.rVal2;
        let csrVal = element.csrVal;

        // execute
        ExecInst eInst = exec(dInst, rVal1, rVal2, element.pc, element.predPc, csrVal);

        // 会对全局状态 eEpoch pc btb 进行修改，所以要避免错误指令生效
        let isPoisoned = False;
        // Only process mispredict for instructions with matching epoch
        if(eEpoch == element.eEpoch) begin
            //for branch, update BHT
            if(dInst.iType == Br) begin
                bht.update(element.pc, eInst.brTaken);
            end
            if(eInst.mispredict) begin
                btb.update(element.pc, eInst.addr);
                pc[2] <= eInst.addr;
                eEpoch <= ~eEpoch;
                $display("[EX] pc: %h MISPREDICTED! redirect to %h, epoch flip to %b", element.pc, eInst.addr, ~eEpoch);
            end

            // check unsupported instruction at commit time. Exiting
            if(eInst.iType == Unsupported) begin
                $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", element.pc);
                $finish;
            end
        end else begin
            // Epoch mismatch: instruction is from wrong path, mark as poisoned
            isPoisoned = True;
        end

        $display("[EX] pc: %h result: %h addr: %h poisoned: %b epoch: %b", element.pc, eInst.data, eInst.addr, isPoisoned, element.eEpoch);

        // pass to next stage
        let e2mEle = Execute2Memory {pc: element.pc, eInst: eInst,isPoisoned: isPoisoned};
        e2m.enq(e2mEle);


        /* 
        // These codes are checking invalid CSR index
        // you could uncomment it for debugging
        // 
        // check invalid CSR read
        if(eInst.iType == Csrr) begin
            let csrIdx = fromMaybe(0, eInst.csr);
            case(csrIdx)
                csrCycle, csrInstret, csrMhartid: begin
                    $display("CSRR reads 0x%0x", eInst.data);
                end
                default: begin
                    $fwrite(stderr, "ERROR: read invalid CSR 0x%0x. Exiting\n", csrIdx);
                    $finish;
                end
            endcase
        end
        // check invalid CSR write
        if(eInst.iType == Csrw) begin
            let csrIdx = fromMaybe(0, eInst.csr);
            if(csrIdx != csrMtohost) begin
                $fwrite(stderr, "ERROR: invalid CSR index = 0x%0x. Exiting\n", csrIdx);
                $finish;
            end
            else begin
                $display("CSRW writes 0x%0x", eInst.data);
            end
        end
        */
    endrule

    // Stage 5: Memory
    // Send memory request to dMem
    rule doMemory(csrf.started);
        let element = e2m.first;
        e2m.deq;
        let eInst = element.eInst;

        if(!element.isPoisoned) begin
            // memory
            if(eInst.iType == Ld) begin
                dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
                $display("[M ] pc: %h LOAD from addr: %h poisoned: %b", element.pc, eInst.addr, element.isPoisoned);
            end else if(eInst.iType == St) begin
                dMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
                $display("[M ] pc: %h STORE to addr: %h data: %h poisoned: %b", element.pc, eInst.addr, eInst.data, element.isPoisoned);
            end else begin
                $display("[M ] pc: %h NO MEM OP poisoned: %b", element.pc, element.isPoisoned);
            end
        end else begin
            $display("[M ] pc: %h POISONED (discarded)", element.pc);
        end

        // pass to next stage
        let m2wbEle = Memory2WriteBack {pc: element.pc, eInst: eInst, isPoisoned: element.isPoisoned};
        m2wb.enq(m2wbEle);

    endrule

    // Stage 6: Write Back
    // Receive memory response from dMem (if applicable) and write to register file
    rule doWriteBack(csrf.started);
        let element = m2wb.first;
        m2wb.deq;
        let eInst = element.eInst;

        // remove from sb
        sb.remove;

        if(!element.isPoisoned) begin
            // receive memory response (only if not poisoned, since poisoned loads don't send requests)
            if(eInst.iType == Ld) begin
                eInst.data <- dMem.resp;
                $display("[WB] pc: %h LOAD data: %h", element.pc, eInst.data);
            end

            // write back to reg file
            if(isValid(eInst.dst)) begin
                rf.wr(fromMaybe(?, eInst.dst), eInst.data);
                $display("[WB] pc: %h WRITE r%d = %h", element.pc, fromMaybe(?, eInst.dst), eInst.data);
            end

            // CSR write for sending data to host & stats
            csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
            if(eInst.iType == Csrw) begin
                $display("[WB] pc: %h CSR WRITE csr%h = %h", element.pc, fromMaybe(?, eInst.csr), eInst.data);
            end

            $display("[WB] pc: %h COMMIT poisoned: %b", element.pc, element.isPoisoned);
        end else begin
            $display("[WB] pc: %h POISONED (no writeback)", element.pc);
        end
    endrule

    // Memory initialization
    Bool memReady = iMem.init.done() && dMem.init.done();
    rule test (!memReady);
        let e = tagged InitDone;
        iMem.init.request.put(e);
        dMem.init.request.put(e);
    endrule

    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if ( !csrf.started && memReady );
        csrf.start(0); // only 1 core, id = 0
        pc[0] <= startpc;
    endmethod

    interface iMemInit = iMem.init;
    interface dMemInit = dMem.init;
endmodule
