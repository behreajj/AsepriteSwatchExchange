local colorFormats = { "RGB", "GRAY", "LAB" }
local colorSpaces = { "ADOBE_RGB", "S_RGB" }
local fileExts = { "ase" }

local defaults = {
    -- TODO: Support aco format.
    colorFormat = "RGB",
    colorSpace = "S_RGB"
}

local dlg = Dialog { title = "ASE Palette IO" }

dlg:combobox {
    id = "colorFormat",
    label = "Format:",
    option = defaults.colorFormat,
    options = colorFormats,
    focus = false,
    onchange = function()
        local args = dlg.data
        local colorFormat = args.colorFormat --[[@as string]]
        dlg:modify { id = "colorSpace", visible = colorFormat == "LAB"
            or colorFormat == "GRAY" }
    end
}

dlg:newrow { always = false }

dlg:combobox {
    id = "colorSpace",
    label = "Space:",
    option = defaults.colorSpace,
    options = colorSpaces,
    focus = false,
    visible = defaults.colorFormat == "LAB"
        or defaults.colorFormat == "GRAY"
}

dlg:separator { id = "cancelSep" }

dlg:file {
    id = "importFilepath",
    label = "Open:",
    filetypes = fileExts,
    open = true,
    focus = true
}

dlg:newrow { always = false }

dlg:button {
    id = "importButton",
    text = "&IMPORT",
    focus = false,
    onclick = function()
        local args = dlg.data
        local importFilepath = args.importFilepath --[[@as string]]

        if (not importFilepath) or (#importFilepath < 1)
            or (not app.fs.isFile(importFilepath)) then
            app.alert {
                title = "Error",
                text = "Invalid file path."
            }
            return
        end

        local fileExt = string.lower(app.fs.fileExtension(importFilepath))
        if fileExt ~= "ase" then
            app.alert {
                title = "Error",
                text = "File format is not ase."
            }
            return
        end

        local binFile, err = io.open(importFilepath, "rb")
        if err ~= nil then
            app.alert { title = "Error", text = err }
            return
        end
        if binFile == nil then return end

        local fileData = binFile:read("a")
        local lenFileData = #fileData

        local strchar = string.char
        local strfmt = string.format
        local tconcat = table.concat

        local strsub = string.sub
        local strunpack = string.unpack
        local floor = math.floor
        local max = math.max
        local min = math.min

        -- Little endian is indicated with '<'.
        -- 'i' is a signed integer, 'I' is unsigned.
        -- n indicates the number of bytes, where 2 is a 16-bit short and
        -- 4 is a 32-bit integer.
        -- 'f' is a float real number.
        local asefHeader = strunpack(">i4", strsub(fileData, 1, 4))
        local isAsef = asefHeader == 0x41534546
        -- print(strfmt("asefHeader: 0x%08x", asefHeader))
        -- print(isAsef)

        if not isAsef then
            -- https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md#header
            local asepriteHeader = strunpack("I2", strsub(fileData, 5, 6))
            -- print(strfmt("asepriteHeader: %04x", asepriteHeader))

            if asepriteHeader == 0xa5e0 then
                binFile:close()
                if #app.sprites <= 0 then
                    Sprite { fromFile = importFilepath }
                else
                    ---@diagnostic disable-next-line: deprecated
                    local activeSprite = app.activeSprite
                    if activeSprite then
                        local palette = Palette { fromFile = importFilepath }
                        if palette then
                            local oldColorMode = activeSprite.colorMode
                            if oldColorMode == ColorMode.INDEXED then
                                app.command.ChangePixelFormat { format = "rgb" }
                            end
                            activeSprite:setPalette(palette)
                            if oldColorMode == ColorMode.INDEXED then
                                app.command.ChangePixelFormat { format = "indexed" }
                            end
                        end
                    end
                end
                return
            end

            binFile:close()
            app.alert { title = "Error", text = "ASEF header not found." }
            return
        end

        -- Ignore version block (0010).

        -- local numColors = strunpack(">i4", strsub(fileData, 9, 12))
        -- print("numColors: " .. numColors)

        -- Handle different color spaces.
        local colorSpace = args.colorSpace
            or defaults.colorSpace --[[@as string]]
        local isAdobe = colorSpace == "ADOBE_RGB"

        ---@type Color[]
        local aseColors = { Color { r = 0, g = 0, b = 0, a = 0 } }
        local groupNesting = 0
        local cmykWarning = false

        local i = 13
        while i < lenFileData do
            local blockLen = 2
            local blockHeader = strunpack(">i2", strsub(fileData, i, i + 1))
            if blockHeader == 0x0001 then
                -- print("Color block.")

                --Excludes header start.
                blockLen = strunpack(">i4", strsub(fileData, i + 2, i + 5))
                -- print("blockLen: " .. blockLen)

                -- The length is the number of chars in a string. The string
                -- is encoded in UTF-16, so it'd be 2x number of binary chars.
                -- A terminal zero is included in the length.
                --
                -- Ase files downloaded from Lospec use their lower-case 6 digit
                -- hexadecimal value as a name, e.g., "aabbcc".
                local lenChars16 = strunpack(">i2", strsub(fileData, i + 6, i + 7))
                -- print("lenChars16: " .. lenChars16)

                -- local nameChars = {}
                -- local j = 0
                -- while j < lenChars16 do
                --     local k = i + 8 + j * 2
                --     local bin16 = strsub(fileData, k, k + 1)
                --     local int16 = strunpack(">i2", bin16)
                --     local char8 = ""
                --     if int16 then char8 = strchar(int16) end
                --     j = j + 1
                --     nameChars[j] = char8

                -- print("bin16: " .. bin16)
                -- print("int16: " .. int16)
                -- print(strfmt("char16: \"%s\"", char8))
                -- end
                -- local name = tconcat(nameChars, "")
                -- print("name: " .. name)

                local iOffset = lenChars16 * 2 + i
                local colorFormat = strunpack(">i4", strsub(fileData, iOffset + 8, iOffset + 11))
                if colorFormat == 0x52474220 then
                    -- print("RGB color space.")

                    local r01 = strunpack(">f", strsub(fileData, iOffset + 12, iOffset + 15))
                    local g01 = strunpack(">f", strsub(fileData, iOffset + 16, iOffset + 19))
                    local b01 = strunpack(">f", strsub(fileData, iOffset + 20, iOffset + 23))
                    -- print(strfmt("%.6f, %.6f, %.6f", r01, g01, b01))

                    local r8 = floor(min(max(r01, 0.0), 1.0) * 255.0 + 0.5)
                    local g8 = floor(min(max(g01, 0.0), 1.0) * 255.0 + 0.5)
                    local b8 = floor(min(max(b01, 0.0), 1.0) * 255.0 + 0.5)
                    -- print(strfmt("r: %03d, g: %03d, b: %03d", r8, g8, b8))
                    -- print(strfmt("#%06x \n", r8 << 0x10 | g8 << 0x08 | b8))

                    aseColors[#aseColors + 1] = Color { r = r8, g = g8, b = b8, a = 255 }
                elseif colorFormat == 0x434d594b then
                    -- print("CMYK color space")

                    cmykWarning = true
                elseif colorFormat == 0x4c616220      -- "Lab "
                    or colorFormat == 0x4c414220 then -- "LAB "
                    -- print("Lab color space")

                    local l01 = strunpack(">f", strsub(fileData, iOffset + 12, iOffset + 15))
                    local a = strunpack(">f", strsub(fileData, iOffset + 16, iOffset + 19))
                    local b = strunpack(">f", strsub(fileData, iOffset + 20, iOffset + 23))
                    local l = l01 * 100.0

                    local vy = (l + 16.0) * 0.008620689655172414
                    local vx = a * 0.002 + vy
                    local vz = vy - b * 0.005

                    local vye3 = vy * vy * vy
                    local vxe3 = vx * vx * vx
                    local vze3 = vz * vz * vz

                    vy = vye3 > 0.008856 and vye3
                        or (vy - 0.13793103448275862) * 0.12841751101180157
                    vx = vxe3 > 0.008856 and vxe3
                        or (vx - 0.13793103448275862) * 0.12841751101180157
                    vz = vze3 > 0.008856 and vze3
                        or (vz - 0.13793103448275862) * 0.12841751101180157

                    vx = vx * 0.95047
                    vz = vz * 1.08883

                    local r01Linear = 0.0
                    local g01Linear = 0.0
                    local b01Linear = 0.0

                    local r01Gamma = 0.0
                    local g01Gamma = 0.0
                    local b01Gamma = 0.0

                    if isAdobe then
                        r01Linear = 2.04137 * vx - 0.56495 * vy - 0.34469 * vz
                        g01Linear = -0.96927 * vx + 1.87601 * vy + 0.04156 * vz
                        b01Linear = 0.01345 * vx - 0.11839 * vy + 1.01541 * vz

                        r01Gamma = r01Linear ^ 0.4547069271758437
                        g01Gamma = g01Linear ^ 0.4547069271758437
                        b01Gamma = b01Linear ^ 0.4547069271758437
                    else
                        r01Linear = 3.2408123 * vx - 1.5373085 * vy - 0.49858654 * vz
                        g01Linear = -0.969243 * vx + 1.8759663 * vy + 0.041555032 * vz
                        b01Linear = 0.0556384 * vx - 0.20400746 * vy + 1.0571296 * vz

                        r01Gamma = r01Linear <= 0.0031308
                            and r01Linear * 12.92
                            or (r01Linear ^ 0.41666666666667) * 1.055 - 0.055
                        g01Gamma = g01Linear <= 0.0031308
                            and g01Linear * 12.92
                            or (g01Linear ^ 0.41666666666667) * 1.055 - 0.055
                        b01Gamma = b01Linear <= 0.0031308
                            and b01Linear * 12.92
                            or (b01Linear ^ 0.41666666666667) * 1.055 - 0.055
                    end

                    local r8 = floor(min(max(r01Gamma, 0.0), 1.0) * 255.0 + 0.5)
                    local g8 = floor(min(max(g01Gamma, 0.0), 1.0) * 255.0 + 0.5)
                    local b8 = floor(min(max(b01Gamma, 0.0), 1.0) * 255.0 + 0.5)

                    aseColors[#aseColors + 1] = Color { r = r8, g = g8, b = b8, a = 255 }
                elseif colorFormat == 0x47726179      -- "Gray"
                    or colorFormat == 0x47524159 then -- "GRAY"
                    -- print("Gray color space")

                    local v01 = strunpack(">f", strsub(fileData, iOffset + 12, iOffset + 15))
                    local v8 = floor(min(max(v01, 0.0), 1.0) * 255.0 + 0.5)
                    aseColors[#aseColors + 1] = Color { r = v8, g = v8, b = v8, a = 255 }
                end

                -- Include block header in length.
                blockLen = blockLen + 2
            elseif blockHeader == 0xc001 then
                -- print("Group start block.")

                -- TODO: You should try to handle these...
                groupNesting = groupNesting + 1
            elseif blockHeader == 0xc002 then
                -- print("Group end block.")

                groupNesting = groupNesting - 1
            end

            i = i + blockLen
        end

        binFile:close()

        local lenAseColors = #aseColors
        local palette = Palette(lenAseColors)
        local j = 0
        while j < lenAseColors do
            palette:setColor(j, aseColors[1 + j])
            j = j + 1
        end

        ---@diagnostic disable-next-line: deprecated
        local activeSprite = app.activeSprite
        if not activeSprite then
            local newFilePrefs = app.preferences.new_file
            local spriteSpec = ImageSpec {
                width = newFilePrefs.width,
                height = newFilePrefs.height,
                colorMode = ColorMode.RGB,
                transparentColor = 0
            }
            spriteSpec.colorSpace = ColorSpace { sRGB = true }
            activeSprite = Sprite(spriteSpec)
        end

        local oldColorMode = activeSprite.colorMode
        if oldColorMode == ColorMode.INDEXED then
            app.command.ChangePixelFormat { format = "rgb" }
        end
        activeSprite:setPalette(palette)
        if oldColorMode == ColorMode.INDEXED then
            app.command.ChangePixelFormat { format = "indexed" }
        end

        if cmykWarning then
            app.alert {
                title = "Error",
                text = "Colors in CMYK were not loaded."
            }
        end
    end
}

dlg:separator { id = "exportSep" }

dlg:newrow { always = false }

dlg:file {
    id = "exportFilepath",
    label = "Save:",
    filetypes = fileExts,
    save = true,
    focus = false
}

dlg:newrow { always = false }

dlg:button {
    id = "exportButton",
    text = "&EXPORT",
    focus = false,
    onclick = function()
        ---@diagnostic disable-next-line: deprecated
        local activeSprite = app.activeSprite
        if not activeSprite then
            app.alert {
                title = "Error",
                text = "There is no active sprite."
            }
            return
        end

        local args = dlg.data
        local exportFilepath = args.exportFilepath --[[@as string]]

        if (not exportFilepath) or (#exportFilepath < 1) then
            app.alert {
                title = "Error",
                text = "Invalid file path."
            }
            return
        end

        local fileExt = string.lower(
            app.fs.fileExtension(exportFilepath))
        if fileExt ~= "ase" then
            app.alert {
                title = "Error",
                text = "File format is not ase."
            }
            return
        end

        local binFile, err = io.open(exportFilepath, "wb")
        if err ~= nil then
            app.alert { title = "Error", text = err }
            return
        end
        if binFile == nil then return end

        ---@diagnostic disable-next-line: deprecated
        local activeFrame = app.activeFrame or activeSprite.frames[1]
        local frIdx = activeFrame.frameNumber

        -- In rare cases, e.g., a sprite opened from a sequence of indexed
        -- color mode files, there may be multiple palettes in the sprite.
        local palettes = activeSprite.palettes
        local paletteIdx = frIdx
        local lenPalettes = #palettes
        if paletteIdx > lenPalettes then paletteIdx = 1 end
        local palette = palettes[paletteIdx]
        local lenPalette = #palette

        -- Handle different color formats. (CMYK not supported.)
        local colorFormat = args.colorFormat
            or defaults.colorFormat --[[@as string]]
        local writeLab = colorFormat == "LAB"
        local writeGry = colorFormat == "GRAY"
        local calcLinear = writeLab or writeGry

        -- Handle different color spaces.
        local colorSpace = args.colorSpace
            or defaults.colorSpace --[[@as string]]
        local isAdobe = colorSpace == "ADOBE_RGB"

        -- Cache functions used in loop.
        local strfmt = string.format
        local strpack = string.pack
        local strbyte = string.byte
        local tconcat = table.concat
        local tinsert = table.insert

        -- Pack constants.
        local pkSignature = strpack(">i4", 0x41534546) -- "ASEF"
        local pkVersion = strpack(">i4", 0x00010000)
        local pkEntryHeader = strpack(">i2", 0x0001)
        local pkNormalColorMode = strpack(">i2", 0x0002) -- global|spot|normal
        local pkLenChars16 = strpack(">i2", 7)           -- eg., "aabbcc" & 0
        local pkStrTerminus = strpack(">i2", 0)

        -- Block length and color space vary by user preference.
        local pkBlockLen = strpack(">i4", 34)
        local pkColorFormat = strpack(">i4", 0x52474220) -- "RGB "
        if writeGry then
            pkBlockLen = strpack(">i4", 26)
            pkColorFormat = strpack(">i4", 0x47524159) -- "GRAY"
        elseif writeLab then
            pkColorFormat = strpack(">i4", 0x4c414220) -- "LAB "
        end

        ---@type string[]
        local binWords = {}
        local numColors = 0

        local i = 0
        while i < lenPalette do
            local aseColor = palette:getColor(i)
            if aseColor.alpha > 0 then
                numColors = numColors + 1

                -- Unpack color.
                local r8 = aseColor.red
                local g8 = aseColor.green
                local b8 = aseColor.blue

                -- Write name.
                local hex24 = r8 << 0x10 | g8 << 0x08 | b8
                local nameStr8 = strfmt("%06x", hex24)

                -- Write color blcok header.
                binWords[#binWords + 1] = pkEntryHeader
                binWords[#binWords + 1] = pkBlockLen
                binWords[#binWords + 1] = pkLenChars16

                -- Write name to 16-bit characters.
                local j = 0
                while j < 6 do
                    j = j + 1
                    local int8 = strbyte(nameStr8, j, j + 1)
                    local int16 = strpack(">i2", int8)
                    binWords[#binWords + 1] = int16
                end
                binWords[#binWords + 1] = pkStrTerminus -- 16

                binWords[#binWords + 1] = pkColorFormat -- 20

                local r01Gamma = r8 / 255.0
                local g01Gamma = g8 / 255.0
                local b01Gamma = b8 / 255.0

                local pkx = strpack(">f", r01Gamma)
                local pky = strpack(">f", g01Gamma)
                local pkz = strpack(">f", b01Gamma)

                if calcLinear then
                    local r01Linear = 0.0
                    local g01Linear = 0.0
                    local b01Linear = 0.0
                    local y = 0.0

                    if isAdobe then
                        r01Linear = r01Gamma ^ 2.19921875
                        g01Linear = g01Gamma ^ 2.19921875
                        b01Linear = b01Gamma ^ 2.19921875
                        y = 0.29738 * r01Linear + 0.62735 * g01Linear + 0.07527 * b01Linear
                    else
                        r01Linear = r01Gamma <= 0.04045
                            and r01Gamma * 0.077399380804954
                            or ((r01Gamma + 0.055) * 0.9478672985782) ^ 2.4
                        g01Linear = g01Gamma <= 0.04045
                            and g01Gamma * 0.077399380804954
                            or ((g01Gamma + 0.055) * 0.9478672985782) ^ 2.4
                        b01Linear = b01Gamma <= 0.04045
                            and b01Gamma * 0.077399380804954
                            or ((b01Gamma + 0.055) * 0.9478672985782) ^ 2.4
                        y = 0.21264935 * r01Linear + 0.71516913 * g01Linear + 0.07218152 * b01Linear
                    end

                    if writeGry then
                        local gray = 0.0
                        if isAdobe then
                            gray = y ^ 0.4547069271758437
                        else
                            gray = y <= 0.0031308 and y * 12.92
                                or (y ^ 0.41666666666667) * 1.055 - 0.055
                        end

                        pkx = strpack(">f", gray)
                        binWords[#binWords + 1] = pkx -- 24
                    elseif writeLab then
                        local x = 0.0
                        local z = 0.0
                        if isAdobe then
                            x = 0.57667 * r01Linear + 0.18555 * g01Linear + 0.18819 * b01Linear
                            z = 0.02703 * r01Linear + 0.07069 * g01Linear + 0.99110 * b01Linear
                        else
                            x = 0.41241086 * r01Linear + 0.35758457 * g01Linear + 0.1804538 * b01Linear
                            z = 0.019331759 * r01Linear + 0.11919486 * g01Linear + 0.95039004 * b01Linear
                        end

                        local vx = x * 1.0521110608435826
                        vx = vx > 0.008856
                            and vx ^ 0.3333333333333333
                            or 7.787 * vx + 0.13793103448275862

                        local vy = y
                        vy = vy > 0.008856
                            and vy ^ 0.3333333333333333
                            or 7.787 * vy + 0.13793103448275862

                        local vz = z * 0.9184170164304805
                        vz = vz > 0.008856
                            and vz ^ 0.3333333333333333
                            or 7.787 * vz + 0.13793103448275862

                        local l = 116.0 * vy - 16.0
                        local a = 500.0 * (vx - vy)
                        local b = 200.0 * (vy - vz)

                        pkx = strpack(">f", l * 0.01)
                        pky = strpack(">f", a)
                        pkz = strpack(">f", b)

                        binWords[#binWords + 1] = pkx -- 24
                        binWords[#binWords + 1] = pky -- 28
                        binWords[#binWords + 1] = pkz -- 32
                    end
                else
                    binWords[#binWords + 1] = pkx -- 24
                    binWords[#binWords + 1] = pky -- 28
                    binWords[#binWords + 1] = pkz -- 32
                end

                binWords[#binWords + 1] = pkNormalColorMode -- 34 RGB, 26 Gray
            end

            i = i + 1
        end

        local pkNumColors = strpack(">i4", numColors)
        tinsert(binWords, 1, pkNumColors)
        tinsert(binWords, 1, pkVersion)
        tinsert(binWords, 1, pkSignature)

        binFile:write(tconcat(binWords, ""))
        binFile:close()

        app.alert {
            title = "Success",
            text = "File exported."
        }
    end
}

dlg:separator { id = "cancelSep" }

dlg:button {
    id = "cancel",
    text = "&CANCEL",
    focus = false,
    onclick = function()
        dlg:close()
    end
}

dlg:show { wait = false }