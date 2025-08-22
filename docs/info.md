<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

The peripheral index is the number TinyQV will use to select your peripheral.  You will pick a free
slot when raising the pull request against the main TinyQV repository, and can fill this in then.  You
also need to set this value as the PERIPHERAL_NUM in your test script.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

# Affinex - RISC-V Affine Transformation Accelerator

Author: Adam Gebregziaber

Peripheral index: nn

## What it does

Signle-point and batch affine transformations .. to be continued

## Register map

Document the registers that are used to interact with your peripheral

| Address | Name       | Access | Description           |
|---------|------------|--------|-----------------------|
| 0x00    | CONTROL    | R/W    | Control               |
| 0x04    | STATUS     | R/W    | Status                |
| 0x08    | A          | R/W    | Coeffient a           |
| 0x0C    | B          | R/W    | Coeffient b           |
| 0x10    | D          | R/W    | Coeffient d           |
| 0x14    | E          | R/W    | Coeffient e           |
| 0x18    | TX         | R/W    | translation vector tx |
| 0x1C    | TY         | R/W    | translation vector ty |
| 0x20    | XIN        | R/W    | Single input X        |
| 0x24    | YIN        | R/W    | Single input Y        |
| 0x28    | XOUT       | R/W    | Output X              |
| 0x2C    | YOUT       | R/W    | Output Y              |
| 0x30    | FIFO_XIN   | R/W    | FIFO input X          |
| 0x34    | FIFO_YIN   | R/W    | FIFO input Y          |
| 0x38    | FIFO_XOUT  | R/W    | FIFO output X         |
| 0x3C    | FIFO_YOUT  | R/W    | FIFO output Y         |

## How to test

Single-Input Test Cases
| Transformation | a  | b   | d   | e  | tx   | ty   | Input (x, y) | Expected Output (x’, y’) |
| -------------- | -- | --- | --- | -- | ---- | ---- | ------------ | ------------------------ |
| Identity       | 1  | 0   | 0   | 1  | 0    | 0    | (1.5, -2.25) | (1.5, -2.25)             |
| Scale ×2       | 2  | 0   | 0   | 2  | 0    | 0    | (1.5, -2.25) | (3.0, -4.5)              |
| Rotate 90°     | 0  | -1  | 1   | 0  | 0    | 0    | (1.5, -2.25) | (2.25, 1.5)              |
| ReflectX       | -1 | 0   | 0   | 1  | 0    | 0    | (1.5, -2.25) | (-1.5, -2.25)            |
| ReflectY       | 1  | 0   | 0   | -1 | 0    | 0    | (1.5, -2.25) | (1.5, 2.25)              |
| Shear XY       | 1  | 0.5 | 0.5 | 1  | 0    | 0    | (1.5, -2.25) | (0.375, 0.75)            |
| Translation    | 1  | 0   | 0   | 1  | 0.25 | -0.5 | (1.5, -2.25) | (1.75, -2.75)            |

Batch Test Cases

Input Points
P0 = (0x00008000, 0x00008000) = (0.5, 0.5)

P1 = (0xFFFF0000, 0x00020000) = (-1.0, 2.0)

P2 = (0x00018000, 0xFFFE8000) = (1.5, -1.5)

| Transformation | a  | b   | d   | e  | tx | ty | Input | Expected Output |
| -------------- | -- | --- | --- | -- | -- | -- | ----- | --------------- |
| Identity       | 1  | 0   | 0   | 1  | 0  | 0  | P0    | (0.5, 0.5)      |
|                |    |     |     |    |    |    | P1    | (-1.0, 2.0)     |
|                |    |     |     |    |    |    | P2    | (1.5, -1.5)     |
| Scale ×2       | 2  | 0   | 0   | 2  | 0  | 0  | P0    | (1.0, 1.0)      |
|                |    |     |     |    |    |    | P1    | (-2.0, 4.0)     |
|                |    |     |     |    |    |    | P2    | (3.0, -3.0)     |
| Rotate 90°     | 0  | -1  | 1   | 0  | 0  | 0  | P0    | (-0.5, 0.5)     |
|                |    |     |     |    |    |    | P1    | (-2.0, -1.0)    |
|                |    |     |     |    |    |    | P2    | (1.5, 1.5)      |
| ReflectX       | -1 | 0   | 0   | 1  | 0  | 0  | P0    | (-0.5, 0.5)     |
|                |    |     |     |    |    |    | P1    | (1.0, 2.0)      |
|                |    |     |     |    |    |    | P2    | (-1.5, -1.5)    |
| ReflectY       | 1  | 0   | 0   | -1 | 0  | 0  | P0    | (0.5, -0.5)     |
|                |    |     |     |    |    |    | P1    | (-1.0, -2.0)    |
|                |    |     |     |    |    |    | P2    | (1.5, 1.5)      |
| Shear XY       | 1  | 0.5 | 0.5 | 1  | 0  | 0  | P0    | (0.75, 0.75)    |
|                |    |     |     |    |    |    | P1    | (0.0, 1.5)      |
|                |    |     |     |    |    |    | P2    | (0.75, -0.75)   |

## External hardware

List external hardware used in your project (e.g. PMOD, LED display, etc), if any
