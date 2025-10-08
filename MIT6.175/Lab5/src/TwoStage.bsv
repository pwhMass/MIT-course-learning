// TwoStage.bsv
//
// This is a two stage pipelined implementation of the RISC-V processor.

import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import MemInit::*;
import RFile::*;
import DMemory::*;
import IMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;

typedef Bit#(1) Epoch;

typedef struct {
	DecodedInst dInst;
	Addr pc;
	Addr predPc;
    Epoch iEpoch;
} Dec2Ex deriving (Bits, Eq);

(* synthesize *)
module mkProc(Proc);
    Ehr#(2, Addr) pc <- mkEhrU; 
    RFile         rf <- mkRFile;
	IMemory     iMem <- mkIMemory;
    DMemory     dMem <- mkDMemory;
    CsrFile     csrf <- mkCsrFile;

    Fifo#(2, Dec2Ex) d2e <- mkCFFifo;
    Reg#(Epoch) epoch <- mkReg(0);



    // start of the main rule ---------------------------------------

    rule doProcDeocde(csrf.started);
        Data inst = iMem.req(pc[0]);

        // predict
        let ppc = pc[0] + 4;

        // update pc
        pc[0] <= ppc;

        d2e.enq(Dec2Ex {dInst:decode(inst), pc: pc[0],predPc: ppc,iEpoch: epoch });

        $display("pc: %h inst: (%h) epoch: %b expanded: %s", pc[0], inst, epoch, showInst(inst));
        
        
    endrule


    rule doProcExec(csrf.started);
        let element = d2e.first;
        d2e.deq;

        let dInst = element.dInst;


        if(element.iEpoch == epoch) begin

            // read general purpose register values 
            Data rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
            Data rVal2 = rf.rd2(fromMaybe(?, dInst.src2));

            // read CSR values (for CSRR inst)
            Data csrVal = csrf.rd(fromMaybe(?, dInst.csr));

            // execute
            ExecInst eInst = exec(dInst, rVal1, rVal2, element.pc, element.predPc, csrVal);  
            // The fifth argument above is the predicted pc, to detect if it was mispredicted. 
            // Since there is no branch prediction, this field is sent with a random value

            // memory
            if(eInst.iType == Ld) begin
                eInst.data <- dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
            end else if(eInst.iType == St) begin
                let d <- dMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
            end

            // commit

            // trace - print the instruction
            
            $fflush(stdout);

            // check unsupported instruction at commit time. Exiting
            if(eInst.iType == Unsupported) begin
                $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", element.pc);
                $finish;
            end

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

            // write back to reg file
            if(isValid(eInst.dst)) begin
                rf.wr(fromMaybe(?, eInst.dst), eInst.data);
            end

            // update the pc depending on whether the branch is taken or not
            if(eInst.mispredict) begin
                pc[1] <= eInst.addr;
                epoch <= ~epoch;
            end

            // CSR write for sending data to host & stats
            csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
        end
    endrule

    // end of the main rule ---------------------------------------


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
