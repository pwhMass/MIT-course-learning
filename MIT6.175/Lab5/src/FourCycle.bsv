// FourCycle.bsv
//
// This is a four cycle implementation of the RISC-V processor.

import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import RFile::*;

import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;
import DelayedMemory::*;
import MemInit::*;


import IMemory::*;
import DMemory::*;

typedef enum {
	Fetch,
	Decode,
	Execute,
	WriteBack
} Stage deriving(Bits, Eq, FShow);

typedef union tagged {
    void Fetch;
    void Decode;
    Tuple3#(DecodedInst,Data,Data) Execute;
    ExecInst WriteBack;
} StageData deriving (Bits, Eq);

(* synthesize *)
module mkProc(Proc);
    Reg#(Addr)    pc <- mkRegU;
    RFile         rf <- mkRFile;
    DelayedMemory mem <- mkDelayedMemory;
	let dummyInit     <- mkDummyMemInit;
    CsrFile       csrf <- mkCsrFile;
    // Reg#(Stage) stage <- mkReg(Fetch);
    Reg#(StageData) stageData <- mkReg(tagged Fetch);

    

    Bool memReady = mem.init.done() && dummyInit.done();
    rule test (!memReady);
        let e = tagged InitDone;
        mem.init.request.put(e);
        dummyInit.request.put(e);
    endrule




    
    rule doFetch(csrf.started &&& stageData matches tagged Fetch);
        stageData <= tagged Decode;

        mem.req(MemReq {op:Ld,addr:pc,data:?});
        

    endrule

    rule doDecode(csrf.started &&& stageData matches tagged Decode);
        
    
        Data inst <- mem.resp();
        // decode
        DecodedInst dInst = decode(inst);

        // read general purpose register values 
        Data rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
        Data rVal2 = rf.rd2(fromMaybe(?, dInst.src2));

        stageData <= tagged Execute tuple3(dInst,rVal1,rVal2);
        

        // trace - print the instruction
        $display("pc: %h inst: (%h) expanded: ", pc, inst, showInst(inst));
	    $fflush(stdout);
    endrule

    rule doExecute(csrf.started &&& stageData matches tagged Execute {.dInst,.rVal1,.rVal2} );
        
        

        // read CSR values (for CSRR inst)
        Data csrVal = csrf.rd(fromMaybe(?, dInst.csr));

        // execute
        ExecInst eInst = exec(dInst, rVal1, rVal2, pc, ?, csrVal);  
		// The fifth argument above is the predicted pc, to detect if it was mispredicted. 
		// Since there is no branch prediction, this field is sent with a random value

        // memory
        if(eInst.iType == Ld) begin
            mem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
        end else if(eInst.iType == St) begin
            mem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
        end

		// commit

        

        // check unsupported instruction at commit time. Exiting
        if(eInst.iType == Unsupported) begin
            $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", pc);
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

        stageData <= tagged WriteBack(eInst);
        
    endrule

    rule doWriteBack(csrf.started &&& stageData matches tagged WriteBack .eInst );

        Data data = eInst.data;
        if (eInst.iType == Ld) data <- mem.resp();

        // write back to reg file
        if(isValid(eInst.dst)) begin
            rf.wr(fromMaybe(?, eInst.dst), data);
        end

        // update the pc depending on whether the branch is taken or not
        pc <= eInst.brTaken ? eInst.addr : pc + 4;

        // CSR write for sending data to host & stats
        csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);

        stageData <= tagged Fetch;
    endrule

    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if (!csrf.started && memReady);
        csrf.start(0); // only 1 core, id = 0
        pc <= startpc;
    endmethod

    interface iMemInit = mem.init;
    interface dMemInit = dummyInit;
endmodule
