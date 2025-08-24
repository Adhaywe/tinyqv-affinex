# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

PERIPHERAL_NUM = 37 

# The number of bits in the fractional part of the fixed-point number
FRAC_BITS = 8 
# 16-bit mask and sign bit for Q8.8
MASK16 = 0xFFFF
SIGN16 = 0x8000

def float_to_q8_8(val: float) -> int:
    """Converts a float to a 16-bit Q8.8 fixed-point integer."""
    q = int(round(val * (1 << FRAC_BITS))) & MASK16
    return q

def q8_8_to_float(u16: int) -> float:
    """Converts a 16-bit Q8.8 fixed-point integer to a float."""
    if u16 & SIGN16:
        u16 -= (1 << 16)
    return u16 / float(1 << FRAC_BITS)

def to_s16(u16: int) -> int:
    """Converts a 16-bit unsigned integer to a signed 16-bit integer."""
    return u16 - (1 << 16) if (u16 & SIGN16) else u16

def wrap_u16(signed_val: int) -> int:
    """Wraps a signed integer to a 16-bit unsigned value."""
    return signed_val & MASK16

def hw_affine_q8_8(a, b, d, e, tx, ty, x, y):
    """
    Performs the affine transformation in software to generate the expected result.
    This function simulates the hardware's Q8.8 fixed-point arithmetic.
    """
    # Convert all inputs to signed 16-bit for calculation
    a = to_s16(a)
    b = to_s16(b)
    d = to_s16(d)
    e = to_s16(e)
    tx = to_s16(tx)
    ty = to_s16(ty)
    x = to_s16(x)
    y = to_s16(y)
    
    # Perform multiplication and addition
    tmpx = a * x + b * y
    tmpy = d * x + e * y
    
    # Right shift to account for fixed-point format, then add translation
    ox = (tmpx >> FRAC_BITS) + tx
    oy = (tmpy >> FRAC_BITS) + ty
    
    # Return 16-bit wrapped results
    return wrap_u16(ox), wrap_u16(oy)


# Memory mapped register addresses
ADDR_CONTROL    = 0x00
ADDR_STATUS     = 0x04
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
ADDR_FIFO_XIN   = 0x30
ADDR_FIFO_YIN   = 0x34
ADDR_FIFO_XOUT  = 0x38
ADDR_FIFO_YOUT  = 0x3C


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start affine test")

    # Set the clock period to 100 ns (10 MHz)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    
    # Reset DUT
    await tqv.reset()

    # --- Test functions ---
    async def single_input_test(desc, a, b, d, e, tx, ty, x, y):
        await tqv.write_word_reg(ADDR_A, a)
        await tqv.write_word_reg(ADDR_B, b)
        await tqv.write_word_reg(ADDR_D, d)
        await tqv.write_word_reg(ADDR_E, e)
        await tqv.write_word_reg(ADDR_XIN, x)
        await tqv.write_word_reg(ADDR_YIN, y)
        await tqv.write_word_reg(ADDR_CONTROL, 1)  # single input mode

        # Wait for the computation to finish (it's multi-cycle)
        await ClockCycles(dut.clk, 200)

        # Read the output values (we only care about the lower 16 bits)
        out_x = (await tqv.read_word_reg(ADDR_XOUT)) & MASK16
        out_y = (await tqv.read_word_reg(ADDR_YOUT)) & MASK16
        
        # Calculate expected values using the Q8.8 software model
        exp_x, exp_y = hw_affine_q8_8(a, b, d, e, tx, ty, x, y)

        assert out_x == exp_x, f"{desc} X mismatch: got {out_x:#06x}, expected {exp_x:#06x}"
        assert out_y == exp_y, f"{desc} Y mismatch: got {out_y:#06x}, expected {exp_y:#06x}"
        dut._log.info(f"{desc} single-input passes")



    # --- test cases ---
    dut._log.info("---Testing Affine accelerator---")

    test_cases = {
        "Scale":    (float_to_q8_8(2), 0, 0, float_to_q8_8(2), 0, 0),
        "Rotate90": (0, float_to_q8_8(-1), float_to_q8_8(1), 0, 0, 0),
        "ReflectX": (float_to_q8_8(-1), 0, 0, float_to_q8_8(1), 0, 0),
        "ReflectY": (float_to_q8_8(1),  0, 0, float_to_q8_8(-1), 0, 0),
        #"ShearXY":  (float_to_q8_8(1), float_to_q8_8(0.5),
       #               float_to_q8_8(0.5), float_to_q8_8(1), 0, 0)
    }

    dut._log.info("---Testing single input case---")

    x = float_to_q8_8(1.5)
    y = float_to_q8_8(-2.25)

    for name, coeffs in test_cases.items():
        await single_input_test(f"Single-{name}", *coeffs, x, y)
