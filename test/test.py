# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

PERIPHERAL_NUM = 37 

# Fixed-point Q8.8 helpers
FRAC_BITS = 8
MASK16 = 0xFFFF
SIGN16 = 0x8000

def float_to_q8_8(val: float) -> int:
    q = int(round(val * (1 << FRAC_BITS)))
    return q & MASK16

def to_s16(u16: int) -> int:
    return u16 - (1 << 16) if (u16 & SIGN16) else u16

def wrap_u16(signed_val: int) -> int:
    return signed_val & MASK16

def hw_affine_q8_8(a, b, d, e, tx, ty, x, y):
    a, b, d, e, tx, ty, x, y = map(to_s16, (a, b, d, e, tx, ty, x, y))
    tmpx = a * x + b * y
    tmpy = d * x + e * y
    ox = (tmpx >> FRAC_BITS) + tx
    oy = (tmpy >> FRAC_BITS) + ty
    return wrap_u16(ox), wrap_u16(oy)

# Register addresses
ADDR_CONTROL    = 0x00
ADDR_A          = 0x08
ADDR_B          = 0x0C
ADDR_D          = 0x10
ADDR_E          = 0x14
ADDR_TX         = 0x18
ADDR_TY         = 0x1C
ADDR_XIN        = 0x20
ADDR_YIN        = 0x24
ADDR_XOUT       = 0x28
ADDR_YOUT       = 0x2C


async def single_input_test(dut, tqv, desc, a, b, d, e, tx, ty, x, y):
    q_a = float_to_q8_8(a)
    q_b = float_to_q8_8(b)
    q_d = float_to_q8_8(d)
    q_e = float_to_q8_8(e)
    q_tx = float_to_q8_8(tx)
    q_ty = float_to_q8_8(ty)
    q_x = float_to_q8_8(x)
    q_y = float_to_q8_8(y)

    await tqv.write_word_reg(ADDR_A, q_a)
    await tqv.write_word_reg(ADDR_B, q_b)
    await tqv.write_word_reg(ADDR_D, q_d)
    await tqv.write_word_reg(ADDR_E, q_e)
    await tqv.write_word_reg(ADDR_TX, q_tx)
    await tqv.write_word_reg(ADDR_TY, q_ty)
    await tqv.write_word_reg(ADDR_XIN, q_x)
    await tqv.write_word_reg(ADDR_YIN, q_y)
    await tqv.write_word_reg(ADDR_CONTROL, 1)

    await ClockCycles(dut.clk, 200)

    out_x = (await tqv.read_word_reg(ADDR_XOUT)) & MASK16
    out_y = (await tqv.read_word_reg(ADDR_YOUT)) & MASK16

    exp_x, exp_y = hw_affine_q8_8(q_a, q_b, q_d, q_e, q_tx, q_ty, q_x, q_y)

    assert out_x == exp_x, f"{desc} X mismatch: got {out_x:#06x}, expected {exp_x:#06x}"
    assert out_y == exp_y, f"{desc} Y mismatch: got {out_y:#06x}, expected {exp_y:#06x}"
    dut._log.info(f"{desc} passes")

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")
    
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    
    await tqv.reset()
    
    # Normal Test Cases
    await single_input_test(dut, tqv, "Identity-Normal", 1, 0, 0, 1, 0, 0, 1.5, -2.25)
    await single_input_test(dut, tqv, "Scale2-Normal", 2, 0, 0, 2, 0, 0, 1.5, -2.25)
    await single_input_test(dut, tqv, "Rotate90-Normal", 0, -1, 1, 0, 0, 0, 1.5, -2.25)
    await single_input_test(dut, tqv, "ReflectX-Normal", -1, 0, 0, 1, 0, 0, 1.5, -2.25)
    await single_input_test(dut, tqv, "ReflectY-Normal", 1, 0, 0, -1, 0, 0, 1.5, -2.25)
    await single_input_test(dut, tqv, "ShearXY-Normal", 1, 0.5, 0.5, 1, 0, 0, 1.5, -2.25)
    await single_input_test(dut, tqv, "Translate-Normal", 1, 0, 0, 1, 0.25, -0.5, 1.5, -2.25)
    
    # Corner Cases (original tests)
    await single_input_test(dut, tqv, "Identity-Zero", 1.0, 0, 0, 1.0, 0, 0, 0, 0)
    await single_input_test(dut, tqv, "Identity-One-One", 1.0, 0, 0, 1.0, 0, 0, 1.0, 1.0)
    await single_input_test(dut, tqv, "Identity-Frac", 1.0, 0, 0, 1.0, 0, 0, 1.5, -2.25)
    await single_input_test(dut, tqv, "Identity-MaxPos", 1.0, 0, 0, 1.0, 0, 0, 127.0, 127.0)
    await single_input_test(dut, tqv, "Identity-MaxNeg", 1.0, 0, 0, 1.0, 0, 0, -128.0, -128.0)

    await single_input_test(dut, tqv, "Scale2-Zero", 2.0, 0, 0, 2.0, 0, 0, 0, 0)
    await single_input_test(dut, tqv, "Scale2-One-One", 2.0, 0, 0, 2.0, 0, 0, 1.0, 1.0)
    await single_input_test(dut, tqv, "Scale2-Frac", 2.0, 0, 0, 2.0, 0, 0, 1.5, -2.25)
    await single_input_test(dut, tqv, "Scale2-MaxPos", 2.0, 0, 0, 2.0, 0, 0, 127.0, 127.0)
    await single_input_test(dut, tqv, "Scale2-MaxNeg", 2.0, 0, 0, 2.0, 0, 0, -128.0, -128.0)

    await single_input_test(dut, tqv, "Rotate90-Zero", 0, -1.0, 1.0, 0, 0, 0, 0, 0)
    await single_input_test(dut, tqv, "Rotate90-One-One", 0, -1.0, 1.0, 0, 0, 0, 1.0, 1.0)
    await single_input_test(dut, tqv, "Rotate90-Frac", 0, -1.0, 1.0, 0, 0, 0, 1.5, -2.25)
    await single_input_test(dut, tqv, "Rotate90-MaxPos", 0, -1.0, 1.0, 0, 0, 0, 127.0, 127.0)
    await single_input_test(dut, tqv, "Rotate90-MaxNeg", 0, -1.0, 1.0, 0, 0, 0, -128.0, -128.0)

    await single_input_test(dut, tqv, "ReflectX-Zero", -1.0, 0, 0, 1.0, 0, 0, 0, 0)
    await single_input_test(dut, tqv, "ReflectX-One-One", -1.0, 0, 0, 1.0, 0, 0, 1.0, 1.0)
    await single_input_test(dut, tqv, "ReflectX-Frac", -1.0, 0, 0, 1.0, 0, 0, 1.5, -2.25)
    await single_input_test(dut, tqv, "ReflectX-MaxPos", -1.0, 0, 0, 1.0, 0, 0, 127.0, 127.0)
    await single_input_test(dut, tqv, "ReflectX-MaxNeg", -1.0, 0, 0, 1.0, 0, 0, -128.0, -128.0)

    await single_input_test(dut, tqv, "ReflectY-Zero", 1.0, 0, 0, -1.0, 0, 0, 0, 0)
    await single_input_test(dut, tqv, "ReflectY-One-One", 1.0, 0, 0, -1.0, 0, 0, 1.0, 1.0)
    await single_input_test(dut, tqv, "ReflectY-Frac", 1.0, 0, 0, -1.0, 0, 0, 1.5, -2.25)
    await single_input_test(dut, tqv, "ReflectY-MaxPos", 1.0, 0, 0, -1.0, 0, 0, 127.0, 127.0)
    await single_input_test(dut, tqv, "ReflectY-MaxNeg", 1.0, 0, 0, -1.0, 0, 0, -128.0, -128.0)

    await single_input_test(dut, tqv, "ShearXY-Zero", 1.0, 0.5, 0.5, 1.0, 0, 0, 0, 0)
    await single_input_test(dut, tqv, "ShearXY-One-One", 1.0, 0.5, 0.5, 1.0, 0, 0, 1.0, 1.0)
    await single_input_test(dut, tqv, "ShearXY-Frac", 1.0, 0.5, 0.5, 1.0, 0, 0, 1.5, -2.25)
    await single_input_test(dut, tqv, "ShearXY-MaxPos", 1.0, 0.5, 0.5, 1.0, 0, 0, 127.0, 127.0)
    await single_input_test(dut, tqv, "ShearXY-MaxNeg", 1.0, 0.5, 0.5, 1.0, 0, 0, -128.0, -128.0)

    await single_input_test(dut, tqv, "Translate-Zero", 1.0, 0, 0, 1.0, 5.0, -3.0, 0, 0)
    await single_input_test(dut, tqv, "Translate-One-One", 1.0, 0, 0, 1.0, 5.0, -3.0, 1.0, 1.0)
    await single_input_test(dut, tqv, "Translate-Frac", 1.0, 0, 0, 1.0, 5.0, -3.0, 1.5, -2.25)
    await single_input_test(dut, tqv, "Translate-MaxPos", 1.0, 0, 0, 1.0, 5.0, -3.0, 127.0, 127.0)
    await single_input_test(dut, tqv, "Translate-MaxNeg", 1.0, 0, 0, 1.0, 5.0, -3.0, -128.0, -128.0)
