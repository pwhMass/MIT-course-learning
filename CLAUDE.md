# Claude Code 项目记录 - MIT 6.175

## Lab5 修复记录 - 2025-09-21

### RISC-V汇编编译修复

#### 问题描述
在Lab5的RISC-V汇编测试编译过程中遇到多个编译错误：
1. CSR指令需要zicsr扩展支持的错误
2. elf2hex工具路径重复导致的文件找不到问题
3. Python脚本Windows行尾符兼容性问题

#### 修复内容

##### 1. 修复CSR扩展支持
**文件**: `MIT6.175/Lab5/programs/assembly/Makefile:46`
```makefile
# 修改前
RISCV_GCC_OPTS = -static -fvisibility=hidden -nostdlib -nostartfiles -Wa,-march=rv32i -mabi=ilp32

# 修改后
RISCV_GCC_OPTS = -static -fvisibility=hidden -nostdlib -nostartfiles -Wa,-march=rv32i_zicsr -mabi=ilp32
```

**原因**: RISC-V测试宏使用了CSR指令(csrr, csrw)来读取性能计数器和管理处理器状态，需要zicsr扩展支持。

##### 2. 修复VMH生成路径问题
**文件**: `MIT6.175/Lab5/programs/assembly/Makefile:78`
```makefile
# 修改前
$(RISCV_ELF2HEX) $(VMH_WIDTH) $(VMH_DEPTH) $(asm_build_bin_dir)/$< >> $(asm_build_vmh_dir)/temp

# 修改后
$(RISCV_ELF2HEX) $(VMH_WIDTH) $(VMH_DEPTH) $(asm_build_bin_dir)/$(notdir $<) >> $(asm_build_vmh_dir)/temp
```

**原因**: Makefile模式规则中$<变量包含完整路径，与$(asm_build_bin_dir)组合导致路径重复。

##### 3. 修复Python脚本行尾符
**文件**: `MIT6.175/Lab5/programs/trans_vmh.py`
```bash
dos2unix /home/peng/projects/learn-6.175/MIT6.175/Lab5/programs/trans_vmh.py
```

**原因**: Python脚本包含Windows行尾符(\r\n)，在Linux环境下执行时shebang行解析失败。

#### 技术要点
- **RISC-V模块化设计**: zicsr扩展是可选的，提供控制状态寄存器访问指令
- **VMH格式**: Verilog Memory Hex格式，用于在硬件仿真器中加载测试程序
- **跨平台兼容性**: WSL环境下需注意文件格式转换

#### 验证结果
- 所有32个RISC-V汇编测试程序编译成功
- VMH文件正确生成，可用于硬件仿真
- 构建过程无致命错误

#### 环境信息
- 工具链: `riscv32-elf-ubuntu-24.04-gcc-nightly-2025.09.20-nightly`
- 工具链源: https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/2025.09.20/riscv32-elf-ubuntu-24.04-gcc-nightly-2025.09.20-nightly.tar.xz
- elf2hex工具源: https://github.com/riscvarchive/riscv-fesvr.git
- 目标架构: rv32i + zicsr扩展
- 构建目录: `../build/assembly/`

#### 注意事项
- libSegFault.so的LD_PRELOAD警告可以忽略，不影响功能
- 该修复适用于WSL环境下的MIT 6.175课程Lab5实验