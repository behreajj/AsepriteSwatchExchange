# Aseprite Swatch Exchange

This is an Adobe Swatch Exchange (`.ase`) and Adobe Color (`.aco`) import-export dialog for use with the [Aseprite](https://www.aseprite.org/) [scripting API](https://www.aseprite.org/docs/scripting/). Support for both files is **partial**.

## ACO Files

`.aco` files support palettes in RGB, HSB, CMYK, CIE LAB and Grayscale formats. Color channels are stored as unsigned 16-bit integers, i.e. in the range `[0, 65535]`.

[Krita](https://krita.org/en/) is currently the standard against which `.aco` files are tested. For that reason, grayscale is stored in linear space, not gamma. Krita's conversion to and from 16-bit integers does not seem to follow the `.aco` specification. 

There are two versions of the `.aco` format. Version 2 includes names per each swatch. Since Aseprite does not name palettes swatches, this script reads and writes version 1 only. Version 2 is supposed to follow after 1, with the redundancy adding backwards compatibility. `.aco` files starting with the version 2 header may not be imported properly.

Rudimentary formulas for CMYK are included because they seemed better than throwing an unsupported exception. However, they should not be taken seriously.

### ASE Files

`.ase` files support palettes in RGB, CMYK, CIE LAB and grayscale formats. HSB is not supported, and reverts to RGB. Color values are stored as 32-bit floating point real numbers. Swatches include names. This script writes the 6-digit hexadecimal code as name; it does not read the name on import. As with the `.aco` format, CMYK should not be taken seriously.

RGB-format `.ase` palettes can be downloaded from [Lospec](https://lospec.com/palette-list).