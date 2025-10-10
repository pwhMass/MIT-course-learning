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

---

## Proj 修复记录 - 2025-10-10

### RISC-V 多核项目程序编译修复

#### 问题描述
在 Proj 目录的测试程序编译过程中遇到多个编译错误：
1. **CSR 名称不识别**: 新版 RISC-V 工具链（gcc 15.1.0）不再识别非标准 CSR 名称 `mtohost`
2. **Python 版本兼容**: `trans_vmh.py` 脚本使用 Python 2 语法，需要迁移到 Python 3
3. **工具链路径**: 原始 Makefile 使用旧的工具链路径
4. **测试文件缺失**: assembly/Makefile 中定义了不存在的 `simple` 测试
5. **架构参数**: 多核项目需要原子指令扩展和 CSR 支持

#### 修复内容

##### 1. 修复 assembly/Makefile
**文件**: `MIT6.175/Proj/programs/assembly/Makefile`

**修改 1 - 移除不存在的测试**:
```makefile
# 修改前
rv32ui_tests = \
	simple \
	add addi \
	...

# 修改后
rv32ui_tests = \
	add addi \
	...
```
**原因**: 源文件目录中不存在 `simple.S` 文件

**修改 2 - 更新工具链路径和架构参数**:
```makefile
# 修改前
RISCV_TOOL_DIR := /home/adam/riscv32-special-a/bin
RISCV_GCC_OPTS := -static -fvisibility=hidden -nostdlib -nostartfiles -Wa,-march=rv32ia

# 修改后
RISCV_TOOL_DIR := /home/peng/projects/riscv/bin
RISCV_GCC_OPTS := -static -fvisibility=hidden -nostdlib -nostartfiles -Wa,-march=rv32ia_zicsr -mabi=ilp32
```

**修改 3 - 添加 ELF2HEX 工具路径**:
```makefile
# 添加
ELF2HEX_TOOL_DIR := /home/peng/projects/riscv/bin
RISCV_ELF2HEX := $(ELF2HEX_TOOL_DIR)/elf2hex
```

##### 2. 修复 benchmarks/Makefile
**文件**: `MIT6.175/Proj/programs/benchmarks/Makefile`

```makefile
# 修改前
RISCV_TOOL_DIR := /home/adam/riscv32-special-a/bin
RISCV_GCC_OPTS := -static -Wa,-march=rv32ia -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf

# 修改后
RISCV_TOOL_DIR := /home/peng/projects/riscv/bin
RISCV_GCC_OPTS := -static -march=rv32ia_zicsr -mabi=ilp32 -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf
ELF2HEX_TOOL_DIR := /home/peng/projects/riscv/bin
RISCV_ELF2HEX := $(ELF2HEX_TOOL_DIR)/elf2hex
```

##### 3. 修复 mc_bench/Makefile
**文件**: `MIT6.175/Proj/programs/mc_bench/Makefile`

```makefile
# 修改前
RISCV_TOOL_DIR := /home/adam/riscv32-special-a/bin
RISCV_GCC_OPTS := -static -Wa,-march=rv32ia -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf

# 修改后
RISCV_TOOL_DIR := /home/peng/projects/riscv/bin
RISCV_GCC_OPTS := -static -march=rv32ia_zicsr -mabi=ilp32 -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf
ELF2HEX_TOOL_DIR := /home/peng/projects/riscv/bin
RISCV_ELF2HEX := $(ELF2HEX_TOOL_DIR)/elf2hex
```

##### 4. 修复 CSR 指令 - 汇编宏
**文件**: `MIT6.175/Proj/programs/assembly/macros/riscv_test.h`

将所有使用 CSR 名称的地方改为使用 CSR 编号 `0x780`：

```c
// 修改前
#define PRINT_NEWLINE(tmp_reg) \
    la tmp_reg, 0x0001000A; \
    csrw mtohost, tmp_reg

// 修改后
#define PRINT_NEWLINE(tmp_reg) \
    la tmp_reg, 0x0001000A; \
    csrw 0x780, tmp_reg
```

**共修改 3 处**:
- `PRINT_NEWLINE` 宏中 1 处
- `PRINT_INT` 宏中 2 处
- `RVTEST_CODE_END` 宏中 1 处

**原因**: 新版 RISC-V 汇编器不再识别非标准 CSR 名称 `mtohost`，需要使用 CSR 编号 `0x780` 直接访问。

##### 5. 修复 CSR 指令 - C 代码内联汇编
**文件**: `MIT6.175/Proj/programs/benchmarks/common/syscalls.c`

```c
// 修改前
void printInt(uint32_t c) {
    int lo = (c & 0x0000FFFF) | (((uint32_t)PrintIntLow) << 16);
    asm volatile ("csrw mtohost, %0" : : "r" (lo));
    // ...
}

// 修改后
void printInt(uint32_t c) {
    int lo = (c & 0x0000FFFF) | (((uint32_t)PrintIntLow) << 16);
    asm volatile ("csrw 0x780, %0" : : "r" (lo));
    // ...
}
```

**修改位置**:
- `printInt()` 函数: 2 处
- `printChar()` 函数: 1 处
- `toHostExit()` 函数: 1 处

**文件**: `MIT6.175/Proj/programs/mc_bench/common/syscalls.c`

相同的修改应用到多核测试的 syscalls.c 文件（4 处相同位置）。

##### 6. 修复 Python 脚本
**文件**: `MIT6.175/Proj/programs/trans_vmh.py`

将 Python 2 语法迁移到 Python 3：

```python
# 修改前
#!/usr/bin/env python

if len(sys.argv) != 3:
    print 'Usage: ./trans_vmh [input vmh] [output vmh]'
    raise

for i in xrange(1, len(lines), 8):
    for j in reversed(xrange(0, 8)):
        # ...

# 修改后
#!/usr/bin/env python3

if len(sys.argv) != 3:
    print('Usage: ./trans_vmh [input vmh] [output vmh]')
    raise Exception('Invalid arguments')

for i in range(1, len(lines), 8):
    for j in reversed(range(0, 8)):
        # ...
```

**主要变化**:
1. Shebang 改为 `python3`
2. `print` 语句改为函数调用：`print()`
3. `xrange()` 改为 `range()`
4. `raise` 改为 `raise Exception()`

#### 技术要点

##### RISC-V 架构配置详解
**rv32ia_zicsr** 参数解析：
- `rv32`: 32 位 RISC-V 基础架构
- `i`: 基础整数指令集（**不含** C 压缩指令扩展）
- `a`: **原子指令扩展** - 多核同步必需（LR/SC、AMO 指令）
- `zicsr`: **控制状态寄存器扩展** - CSR 访问指令（csrr/csrw）
- `-mabi=ilp32`: 32 位整数 ABI

**为什么需要这些扩展**:
- **原子指令 (a)**: Proj 是多核项目，需要原子操作实现核间同步（自旋锁、Dekker 算法等）
- **CSR 支持 (zicsr)**: 测试宏使用 CSR 读取性能计数器（cycle、instret）和实现 tohost 通信
- **禁止压缩指令**: 你的处理器设计只支持 32 位标准指令，不支持 16 位压缩指令

##### CSR 0x780 (mtohost) 说明
`mtohost` 是 MIT 6.175 课程使用的**自定义 CSR**，用于：
- 从处理器向主机（仿真器）发送消息
- 打印调试信息（字符、整数）
- 报告测试结果（pass/fail）
- 性能计数器输出

虽然在 `encoding.h` 中定义为 `0x780`，但新版工具链不再允许使用自定义 CSR 名称，必须直接使用编号。

##### VMH 格式
VMH (Verilog Memory Hex) 文件特点：
- 8 字节（64 位）对齐的十六进制内存镜像
- `trans_vmh.py` 将 elf2hex 生成的 8B/行格式转换为 64B/行格式
- 用于 Bluesim 仿真器加载程序到内存
- 每个测试程序对应一个 `.vmh` 文件

#### 验证结果
编译成功生成 **52 个 VMH 文件**：

| 测试类别 | VMH 文件数 | 说明 |
|---------|-----------|------|
| **assembly** | 37 | RISC-V 指令测试、分支预测测试、Cache 测试 |
| **benchmarks** | 5 | 单核性能测试（median、qsort、towers、vvadd、multiply） |
| **mc_bench** | 10 | 多核测试（hello、print、同步原语、并行计算） |
| **总计** | **52** | 全部编译成功，无错误 |

#### 环境信息
- **工具链**: `riscv32-unknown-elf-gcc 15.1.0` (2025.09.20 nightly)
- **工具链源**: https://github.com/riscv-collab/riscv-gnu-toolchain
- **elf2hex 工具源**: https://github.com/riscvarchive/riscv-fesvr.git
- **目标架构**: rv32ia_zicsr (32 位基础 + 原子 + CSR，禁止压缩)
- **Python 版本**: Python 3
- **构建目录**: `MIT6.175/Proj/programs/build/`

#### 注意事项
1. **CSR 命名限制**: 新版 RISC-V 工具链（gcc 15.x）移除了对非标准 CSR 名称的支持，必须使用数字编号
2. **原子指令必需**: 多核项目必须包含 `a` 扩展，否则无法编译 mc_bench 中的同步代码
3. **RWX 段警告**: 链接时的 "LOAD segment with RWX permissions" 警告可以忽略，这是测试程序的正常现象
4. **Python 环境**: 确保系统使用 Python 3，或修改 Makefile 中的 `python` 为 `python3`
5. **工具链一致性**: 所有 Makefile 使用相同的工具链路径和编译选项，确保一致性

#### 与 Lab5 修复的区别
| 项目 | Lab5 | Proj |
|------|------|------|
| 架构 | `rv32i_zicsr` | `rv32ia_zicsr` |
| 原子指令 | ❌ 不需要 | ✅ 必需（多核） |
| CSR 修复 | 仅汇编宏 | 汇编宏 + C 代码 |
| Python | 行尾符修复 | Python 2→3 迁移 |
| 测试数量 | 32 个 | 52 个 |

#### 后续工作
- [ ] 验证 VMH 文件在 Bluesim 仿真器中正确加载
- [ ] 测试多核处理器与 mc_bench 程序的兼容性
- [ ] 检查性能计数器输出格式
- [ ] 确认原子指令在缓存一致性协议中正确实现