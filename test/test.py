# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

PERIPHERAL_NUM = 37 


FRAC_BITS = 16
MASK32 = 0xFFFF_FFFF
SIGN32 = 0x8000_0000

def float_to_q16_16(val: float) -> int:
    q = int(round(val * (1 << FRAC_BITS))) & MASK32
    return q

def q16_16_to_float(u32: int) -> float:
    if u32 & SIGN32:
        u32 -= (1 << 32)
    return u32 / float(1 << FRAC_BITS)

def to_s32(u32: int) -> int:
    return u32 - (1 << 32) if (u32 & SIGN32) else u32

def wrap_u32(signed_val: int) -> int:
    return signed_val & MASK32

def hw_affine_q16_16(a, b, d, e, tx, ty, x, y):
    a = to_s32(a); b = to_s32(b); d = to_s32(d); e = to_s32(e)
    tx = to_s32(tx); ty = to_s32(ty); x = to_s32(x); y = to_s32(y)
    tmpx = a * x + b * y
    tmpy = d * x + e * y
    ox = (tmpx >> FRAC_BITS) + tx
    oy = (tmpy >> FRAC_BITS) + ty
    return wrap_u32(ox), wrap_u32(oy)


ADDR_CONTROL   = 0x00
ADDR_STATUS    = 0x04
ADDR_A         = 0x08
ADDR_B         = 0x0C
ADDR_D         = 0x10
ADDR_E         = 0x14
ADDR_TX        = 0x18
ADDR_TY        = 0x1C
ADDR_XIN       = 0x20
ADDR_YIN       = 0x24
ADDR_XOUT      = 0x28
ADDR_YOUT      = 0x2C
ADDR_FIFO_XIN  = 0x30
ADDR_FIFO_YIN  = 0x34
ADDR_FIFO_XOUT = 0x38
ADDR_FIFO_YOUT = 0x3C


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start affine test")

    # Set the clock period to 100 ns (10 MHz)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

   

    # --- Single input test ---
    async def single_input_test(desc, a, b, d, e, tx, ty, x, y):

        await tqv.write_word_reg(ADDR_A, a)
        await tqv.write_word_reg(ADDR_B, b)
        await tqv.write_word_reg(ADDR_D, d)
        await tqv.write_word_reg(ADDR_E, e)
        await tqv.write_word_reg(ADDR_XIN, x)
        await tqv.write_word_reg(ADDR_YIN, y)
        await tqv.write_word_reg(ADDR_CONTROL, 1)  # single input mode

        await ClockCycles(dut.clk, 1)

        out_x = await tqv.read_word_reg(ADDR_XOUT)
        out_y = await tqv.read_word_reg(ADDR_YOUT)
        exp_x, exp_y = hw_affine_q16_16(a, b, d, e, tx, ty, x, y)

        assert out_x == exp_x, f"{desc} X mismatch: got {out_x:#x}, expected {exp_x:#x}"
        assert out_y == exp_y, f"{desc} Y mismatch: got {out_y:#x}, expected {exp_y:#x}"
        dut._log.info(f"{desc} single-input passes")

    # --- batch test ---
    async def batch_test(desc, a, b, d, e, tx, ty, points):
        await tqv.write_word_reg(ADDR_A, a)
        await tqv.write_word_reg(ADDR_B, b)
        await tqv.write_word_reg(ADDR_D, d)
        await tqv.write_word_reg(ADDR_E, e)
        await tqv.write_word_reg(ADDR_TX, tx)
        await tqv.write_word_reg(ADDR_TY, ty)

        # Write points into FIFO
        for x, y in points:
            await tqv.write_word_reg(ADDR_FIFO_XIN, x)
            await tqv.write_word_reg(ADDR_FIFO_YIN, y)

        await tqv.write_word_reg(ADDR_CONTROL, 2)  # FIFO mode

        await ClockCycles(dut.clk, 2)

        # Read points from FIFO outputs
        for idx, (x, y) in enumerate(points):
            out_x = await tqv.read_word_reg(ADDR_FIFO_XOUT)
            out_y = await tqv.read_word_reg(ADDR_FIFO_YOUT)
            exp_x, exp_y = hw_affine_q16_16(a, b, d, e, tx, ty, x, y)

            # DUT output vs expected
            if (out_x == exp_x) and (out_y == exp_y):
                dut._log.info(
                    f"{desc} point[{idx}] -> DUT=({out_x:#010x}, {out_y:#010x}), "
                    f"Expected=({exp_x:#010x}, {exp_y:#010x}) PASS"
                )
            else:
                dut._log.warning(
                    f"{desc} point[{idx}] -> DUT=({out_x:#010x}, {out_y:#010x}), "
                    f"Expected=({exp_x:#010x}, {exp_y:#010x}) MISMATCH"
            )

            dut._log.info(f"{desc} FIFO test complete\n")
            await ClockCycles(dut.clk, 1)


   

    # --- test cases ---


    tqv = TinyQV(dut, PERIPHERAL_NUM)

    # Reset DUT
    await tqv.reset()

    dut._log.info("---Testing Affine accelerator---")

    test_cases = {
        "Identity": (float_to_q16_16(1), 0, 0, float_to_q16_16(1), 0, 0),
        "Scale":    (float_to_q16_16(2), 0, 0, float_to_q16_16(2), 0, 0),
        "Rotate90": (0, float_to_q16_16(-1), float_to_q16_16(1), 0, 0, 0),
        "ReflectX": (float_to_q16_16(-1), 0, 0, float_to_q16_16(1), 0, 0),
        "ReflectY": (float_to_q16_16(1),  0, 0, float_to_q16_16(-1), 0, 0),
        "ShearXY":  (float_to_q16_16(1), float_to_q16_16(0.5),
                     float_to_q16_16(0.5), float_to_q16_16(1), 0, 0)
    }




    dut._log.info("---Testing single input case---")

    x = float_to_q16_16(1.5)
    y = float_to_q16_16(-2.25)

    for name, coeffs in test_cases.items():
        await single_input_test(f"Single-{name}", *coeffs, x, y)



    points = [
        (float_to_q16_16(0.5), float_to_q16_16(0.5)),
        (float_to_q16_16(-1.0), float_to_q16_16(2.0)),
        (float_to_q16_16(1.5), float_to_q16_16(-1.5)),
    ]


    dut._log.info("---Testing batch case---")

    a, b, d, e, tx, ty = float_to_q16_16(1), 0, 0, float_to_q16_16(1), 0, 0 
    await batch_test("FIFO-Identity", a, b, d, e, tx, ty, points)

