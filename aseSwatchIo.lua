--[[
    ACO:
    https://devblog.cyotek.com/post/reading-photoshop-color-swatch-aco-files-using-csharp
    https://devblog.cyotek.com/post/writing-photoshop-color-swatch-aco-files-using-csharp

    ASE:
    https://devblog.cyotek.com/post/reading-adobe-swatch-exchange-ase-files-using-csharp
    https://devblog.cyotek.com/post/writing-adobe-swatch-exchange-ase-files-using-csharp
]]

local colorFormats = { "GRAY", "RGB", "LAB" }
local colorSpaces = { "ADOBE_RGB", "S_RGB" }
local grayMethods = { "HSI", "HSL", "HSV", "LUMA" }
local fileExts = { "ase" }

local defaults = {
    -- TODO: Support aco format. If so, you'll need HSB->RGB, RGB->HSB.
    colorFormat = "RGB",
    colorSpace = "S_RGB",
    grayMethod = "LUMA"
}

---@param l number
---@param a number
---@param b number
---@return number
---@return number
---@return number
local function cieLabToCieXyz(l, a, b)
    local y = (l + 16.0) * 0.008620689655172414
    local x = a * 0.002 + y
    local z = y - b * 0.005

    local ye3 = y * y * y
    local xe3 = x * x * x
    local ze3 = z * z * z

    y = ye3 > 0.008856 and ye3
        or (y - 0.13793103448275862) * 0.12841751101180157
    x = xe3 > 0.008856 and xe3
        or (x - 0.13793103448275862) * 0.12841751101180157
    z = ze3 > 0.008856 and ze3
        or (z - 0.13793103448275862) * 0.12841751101180157

    x = x * 0.95047
    z = z * 1.08883

    return x, y, z
end

---@param y number
---@return number
local function cieLumToAdobeGray(y)
    return y ^ 0.4547069271758437
end

---@param y number
---@return number
local function cieLumTosGray(y)
    return y <= 0.0031308 and y * 12.92
        or (y ^ 0.41666666666667) * 1.055 - 0.055
end

---@param x number
---@param y number
---@param z number
---@return number
---@return number
---@return number
local function cieXyzToCieLab(x, y, z)
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

    return l, a, b
end

---@param x number
---@param y number
---@param z number
---@return number
---@return number
---@return number
local function cieXyzToLinearAdobeRgb(x, y, z)
    local r01Linear = 2.04137 * x - 0.56495 * y - 0.34469 * z
    local g01Linear = -0.96927 * x + 1.87601 * y + 0.04156 * z
    local b01Linear = 0.01345 * x - 0.11839 * y + 1.01541 * z
    return r01Linear, g01Linear, b01Linear
end

---@param x number
---@param y number
---@param z number
---@return number
---@return number
---@return number
local function cieXyzToLinearsRgb(x, y, z)
    local r01Linear = 3.2408123 * x - 1.5373085 * y - 0.49858654 * z
    local g01Linear = -0.969243 * x + 1.8759663 * y + 0.041555032 * z
    local b01Linear = 0.0556384 * x - 0.20400746 * y + 1.0571296 * z
    return r01Linear, g01Linear, b01Linear
end

---@param c number
---@param m number
---@param y number
---@param k number
---@return number
---@return number
---@return number
local function cmykToRgb(c, m, y, k)
    local u = 1.0 - k
    local r01 = (1.0 - c) * u
    local g01 = (1.0 - m) * u
    local b01 = (1.0 - y) * u
    return r01, g01, b01
end

---@param r01Gamma number
---@param g01Gamma number
---@param b01Gamma number
---@return number
---@return number
---@return number
local function gammaAdobeRgbToLinearAdobeRgb(r01Gamma, g01Gamma, b01Gamma)
    local r01Linear = r01Gamma ^ 2.19921875
    local g01Linear = g01Gamma ^ 2.19921875
    local b01Linear = b01Gamma ^ 2.19921875
    return r01Linear, g01Linear, b01Linear
end

---@param r01Gamma number
---@param g01Gamma number
---@param b01Gamma number
---@return number
---@return number
---@return number
local function gammasRgbToLinearsRgb(r01Gamma, g01Gamma, b01Gamma)
    local r01Linear = r01Gamma <= 0.04045
        and r01Gamma * 0.077399380804954
        or ((r01Gamma + 0.055) * 0.9478672985782) ^ 2.4
    local g01Linear = g01Gamma <= 0.04045
        and g01Gamma * 0.077399380804954
        or ((g01Gamma + 0.055) * 0.9478672985782) ^ 2.4
    local b01Linear = b01Gamma <= 0.04045
        and b01Gamma * 0.077399380804954
        or ((b01Gamma + 0.055) * 0.9478672985782) ^ 2.4
    return r01Linear, g01Linear, b01Linear
end

---@param r01 number
---@param g01 number
---@param b01 number
---@return number
local function grayMethodHsi(r01, g01, b01)
    return (r01 + g01 + b01) / 3.0
end

---@param r01 number
---@param g01 number
---@param b01 number
---@return number
local function grayMethodHsl(r01, g01, b01)
    return (math.min(r01, g01, b01) + math.max(r01, g01, b01)) / 2.0
end

---@param r01 number
---@param g01 number
---@param b01 number
---@return number
local function grayMethodHsv(r01, g01, b01)
    return math.max(r01, g01, b01)
end

---@param r01Linear number
---@param g01Linear number
---@param b01Linear number
---@return number
---@return number
---@return number
local function linearAdobeRgbToGammaAdobeRgb(r01Linear, g01Linear, b01Linear)
    local r01Gamma = r01Linear ^ 0.4547069271758437
    local g01Gamma = g01Linear ^ 0.4547069271758437
    local b01Gamma = b01Linear ^ 0.4547069271758437
    return r01Gamma, g01Gamma, b01Gamma
end

---@param r01Linear number
---@param g01Linear number
---@param b01Linear number
---@return number
---@return number
---@return number
local function linearAdobeRgbToCieXyz(r01Linear, g01Linear, b01Linear)
    local x = 0.57667 * r01Linear + 0.18555 * g01Linear + 0.18819 * b01Linear
    local y = 0.29738 * r01Linear + 0.62735 * g01Linear + 0.07527 * b01Linear
    local z = 0.02703 * r01Linear + 0.07069 * g01Linear + 0.99110 * b01Linear
    return x, y, z
end

---@param r01Linear number
---@param g01Linear number
---@param b01Linear number
---@return number
---@return number
---@return number
local function linearsRgbToCieXyz(r01Linear, g01Linear, b01Linear)
    local x = 0.41241086 * r01Linear + 0.35758457 * g01Linear + 0.1804538 * b01Linear
    local y = 0.21264935 * r01Linear + 0.71516913 * g01Linear + 0.07218152 * b01Linear
    local z = 0.019331759 * r01Linear + 0.11919486 * g01Linear + 0.95039004 * b01Linear
    return x, y, z
end

---@param r01Linear number
---@param g01Linear number
---@param b01Linear number
---@return number
---@return number
---@return number
local function linearsRgbToGammasRgb(r01Linear, g01Linear, b01Linear)
    local r01Gamma = r01Linear <= 0.0031308
        and r01Linear * 12.92
        or (r01Linear ^ 0.41666666666667) * 1.055 - 0.055
    local g01Gamma = g01Linear <= 0.0031308
        and g01Linear * 12.92
        or (g01Linear ^ 0.41666666666667) * 1.055 - 0.055
    local b01Gamma = b01Linear <= 0.0031308
        and b01Linear * 12.92
        or (b01Linear ^ 0.41666666666667) * 1.055 - 0.055
    return r01Gamma, g01Gamma, b01Gamma
end

---@param r01 number
---@param g01 number
---@param b01 number
---@param gray number
---@return number
---@return number
---@return number
---@return number
local function rgbToCmyk(r01, g01, b01, gray)
    local c = 0.0
    local m = 0.0
    local y = 0.0
    local k = 1.0 - gray
    if k ~= 1.0 then
        local scalar = 1.0 / (1.0 - k)
        c = (1.0 - r01 - k) * scalar
        m = (1.0 - g01 - k) * scalar
        y = (1.0 - b01 - k) * scalar
    end
    return c, m, y, k
end

---@param palette Palette
---@param colorFormat "CMYK"|"GRAY"|"LAB"|"RGB"
---@param colorSpace "ADOBE_SRGB"|"S_RGB"
---@param grayMethod "HSI"|"HSL"|"HSV"|"LUMA"
---@return string
local function writeAse(palette, colorFormat, colorSpace, grayMethod)
    -- Cache commonly used methods.
    local strbyte = string.byte
    local strfmt = string.format
    local strpack = string.pack
    local tconcat = table.concat
    local tinsert = table.insert

    local lenPalette = #palette

    ---@type string[]
    local binWords = {}
    local numColors = 0

    local writeLab = colorFormat == "LAB"
    local writeGry = colorFormat == "GRAY"
    local writeCmyk = colorFormat == "CMYK"
    local calcLinear = writeLab or writeGry or writeCmyk

    local isAdobe = colorSpace == "ADOBE_RGB"

    local isGryHsv = grayMethod == "HSV"
    local isGryHsi = grayMethod == "HSI"
    local isGryHsl = grayMethod == "HSL"
    local isGryLuma = grayMethod == "LUMA"
    local isGryAdobeY = isAdobe and isGryLuma

    -- Block length and color space vary by user preference.
    local pkBlockLen = strpack(">i4", 34)
    local pkColorFormat = strpack(">i4", 0x52474220) -- "RGB "
    if writeGry then
        pkBlockLen = strpack(">i4", 26)
        pkColorFormat = strpack(">i4", 0x47524159) -- "GRAY"
    elseif writeLab then
        pkColorFormat = strpack(">i4", 0x4c414220) -- "LAB "
    elseif writeCmyk then
        pkBlockLen = strpack(">i4", 38)
        pkColorFormat = strpack(">i4", 0x434D594B) -- "CMYK"
    end

    local pkEntryHeader = strpack(">i2", 0x0001)
    local pkNormalColorMode = strpack(">i2", 0x0002) -- global|spot|normal
    local pkLenChars16 = strpack(">i2", 7)           -- eg., "aabbcc" & 0
    local pkStrTerminus = strpack(">i2", 0)

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

            -- Write color block header.
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

            -- Default to standard RGB.
            local pkx = strpack(">f", r01Gamma)
            local pky = strpack(">f", g01Gamma)
            local pkz = strpack(">f", b01Gamma)

            if calcLinear then
                local r01Linear = 0.0
                local g01Linear = 0.0
                local b01Linear = 0.0

                local xCie = 0.0
                local yCie = 0.0
                local zCie = 0.0

                if isAdobe then
                    r01Linear, g01Linear, b01Linear = gammaAdobeRgbToLinearAdobeRgb(r01Gamma, g01Gamma, b01Gamma)
                    xCie, yCie, zCie = linearAdobeRgbToCieXyz(r01Linear, g01Linear, b01Linear)
                else
                    r01Linear, g01Linear, b01Linear = gammasRgbToLinearsRgb(r01Gamma, g01Gamma, b01Gamma)
                    xCie, yCie, zCie = linearsRgbToCieXyz(r01Linear, g01Linear, b01Linear)
                end

                if writeGry then
                    local gray = 0.0
                    if isGryHsi then
                        gray = grayMethodHsi(r01Gamma, g01Gamma, b01Gamma)
                    elseif isGryHsl then
                        gray = grayMethodHsl(r01Gamma, g01Gamma, b01Gamma)
                    elseif isGryHsv then
                        gray = grayMethodHsv(r01Gamma, g01Gamma, b01Gamma)
                    elseif isGryAdobeY then
                        gray = cieLumToAdobeGray(yCie)
                    else
                        gray = cieLumTosGray(yCie)
                    end

                    pkx = strpack(">f", gray)
                    binWords[#binWords + 1] = pkx -- 24
                elseif writeCmyk then
                    local gray = grayMethodHsv(r01Gamma, g01Gamma, b01Gamma)
                    local c, n, y, black = rgbToCmyk(r01Gamma, g01Gamma, b01Gamma, gray)

                    pkx = strpack(">f", c)
                    pky = strpack(">f", n)
                    pkz = strpack(">f", y)
                    local pkw = strpack(">f", black)

                    binWords[#binWords + 1] = pkx -- 24
                    binWords[#binWords + 1] = pky -- 28
                    binWords[#binWords + 1] = pkz -- 32
                    binWords[#binWords + 1] = pkw -- 36
                elseif writeLab then
                    local l, a, b = cieXyzToCieLab(xCie, yCie, zCie)

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

            binWords[#binWords + 1] = pkNormalColorMode -- 34 RGB, 26 Gray, 38 CMYK
        end

        i = i + 1
    end

    local pkNumColors = strpack(">i4", numColors)
    local pkVersion = strpack(">i4", 0x00010000)   -- 1.00
    local pkSignature = strpack(">i4", 0x41534546) -- "ASEF"

    tinsert(binWords, 1, pkNumColors)
    tinsert(binWords, 1, pkVersion)
    tinsert(binWords, 1, pkSignature)
    return tconcat(binWords, "")
end

local dlg = Dialog { title = "ASE Palette IO" }

dlg:combobox {
    id = "colorFormat",
    label = "Format:",
    option = defaults.colorFormat,
    options = colorFormats,
    focus = false
}

dlg:newrow { always = false }

dlg:combobox {
    id = "colorSpace",
    label = "Space:",
    option = defaults.colorSpace,
    options = colorSpaces,
    focus = false
}

dlg:newrow { always = false }

dlg:combobox {
    id = "grayMethod",
    label = "GRAY:",
    option = defaults.grayMethod,
    options = grayMethods,
    focus = false
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

---@param fileData string
---@param colorSpace "ADOBE_SRGB"|"S_RGB"
---@return Color[]
local function readAse(fileData, colorSpace)
    ---@type Color[]
    local aseColors = { Color { r = 0, g = 0, b = 0, a = 0 } }

    local strchar = string.char
    local strfmt = string.format
    local tconcat = table.concat

    local strsub = string.sub
    local strunpack = string.unpack
    local floor = math.floor
    local max = math.max
    local min = math.min

    local lenFileData = #fileData
    local isAdobe = colorSpace == "ADOBE_RGB"
    local groupNesting = 0

    -- Ignore version block (0010) in chars 5, 6, 7, 8.
    -- local numColors = strunpack(">i4", strsub(fileData, 9, 12))
    -- print("numColors: " .. numColors)

    local i = 13
    while i < lenFileData do
        local blockLen = 2
        local blockHeader = strunpack(">i2", strsub(fileData, i, i + 1))
        local isGroup = blockHeader == 0xc001
        local isEntry = blockHeader == 0x0001
        if isGroup or isEntry then
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

            if isEntry then
                -- print("Color block.")

                local iOffset = lenChars16 * 2 + i
                local colorFormat = strunpack(">i4", strsub(fileData, iOffset + 8, iOffset + 11))
                if colorFormat == 0x52474220 then
                    -- print("RGB color space.")

                    local r01 = strunpack(">f", strsub(fileData, iOffset + 12, iOffset + 15))
                    local g01 = strunpack(">f", strsub(fileData, iOffset + 16, iOffset + 19))
                    local b01 = strunpack(">f", strsub(fileData, iOffset + 20, iOffset + 23))
                    -- print(strfmt("%.6f, %.6f, %.6f", r01, g01, b01))

                    aseColors[#aseColors + 1] = Color {
                        r = floor(min(max(r01, 0.0), 1.0) * 255.0 + 0.5),
                        g = floor(min(max(g01, 0.0), 1.0) * 255.0 + 0.5),
                        b = floor(min(max(b01, 0.0), 1.0) * 255.0 + 0.5),
                        a = 255
                    }
                elseif colorFormat == 0x434d594b then
                    -- print("CMYK color space")

                    local c = strunpack(">f", strsub(fileData, iOffset + 12, iOffset + 15))
                    local m = strunpack(">f", strsub(fileData, iOffset + 16, iOffset + 19))
                    local y = strunpack(">f", strsub(fileData, iOffset + 20, iOffset + 23))
                    local k = strunpack(">f", strsub(fileData, iOffset + 24, iOffset + 27))

                    local r01, g01, b01 = cmykToRgb(c, m, y, k)

                    aseColors[#aseColors + 1] = Color {
                        r = floor(min(max(r01, 0.0), 1.0) * 255.0 + 0.5),
                        g = floor(min(max(g01, 0.0), 1.0) * 255.0 + 0.5),
                        b = floor(min(max(b01, 0.0), 1.0) * 255.0 + 0.5),
                        a = 255
                    }
                elseif colorFormat == 0x4c616220      -- "Lab "
                    or colorFormat == 0x4c414220 then -- "LAB "
                    -- print("Lab color space")

                    local l = strunpack(">f", strsub(fileData, iOffset + 12, iOffset + 15))
                    local a = strunpack(">f", strsub(fileData, iOffset + 16, iOffset + 19))
                    local b = strunpack(">f", strsub(fileData, iOffset + 20, iOffset + 23))

                    local x, y, z = cieLabToCieXyz(l * 100.0, a, b)

                    local r01Linear = 0.0
                    local g01Linear = 0.0
                    local b01Linear = 0.0

                    local r01Gamma = 0.0
                    local g01Gamma = 0.0
                    local b01Gamma = 0.0

                    if isAdobe then
                        r01Linear, g01Linear, b01Linear = cieXyzToLinearAdobeRgb(x, y, z)
                        r01Gamma, g01Gamma, b01Gamma = linearAdobeRgbToGammaAdobeRgb(r01Linear, g01Linear, b01Linear)
                    else
                        r01Linear, g01Linear, b01Linear = cieXyzToLinearsRgb(x, y, z)
                        r01Gamma, g01Gamma, b01Gamma = linearsRgbToGammasRgb(r01Linear, g01Linear, b01Linear)
                    end

                    aseColors[#aseColors + 1] = Color {
                        r = floor(min(max(r01Gamma, 0.0), 1.0) * 255.0 + 0.5),
                        g = floor(min(max(g01Gamma, 0.0), 1.0) * 255.0 + 0.5),
                        b = floor(min(max(b01Gamma, 0.0), 1.0) * 255.0 + 0.5),
                        a = 255
                    }
                elseif colorFormat == 0x47726179      -- "Gray"
                    or colorFormat == 0x47524159 then -- "GRAY"
                    -- print("Gray color space")

                    local v01 = strunpack(">f", strsub(fileData, iOffset + 12, iOffset + 15))
                    local v8 = floor(min(max(v01, 0.0), 1.0) * 255.0 + 0.5)
                    aseColors[#aseColors + 1] = Color { r = v8, g = v8, b = v8, a = 255 }
                end
            else
                -- print("Group begin block.")

                groupNesting = groupNesting + 1
            end

            -- Include block header in length.
            blockLen = blockLen + 2
        elseif blockHeader == 0xc002 then
            -- print("Group end block.")

            groupNesting = groupNesting - 1
        end

        i = i + blockLen
    end

    return aseColors
end

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

        -- Preserve fore- and background colors.
        local fgc = app.fgColor
        app.fgColor = Color {
            r = fgc.red,
            g = fgc.green,
            b = fgc.blue,
            a = fgc.alpha
        }

        app.command.SwitchColors()
        local bgc = app.fgColor
        app.fgColor = Color {
            r = bgc.red,
            g = bgc.green,
            b = bgc.blue,
            a = bgc.alpha
        }
        app.command.SwitchColors()

        -- Little endian is indicated with '<'.
        -- 'i' is a signed integer, 'I' is unsigned.
        -- n indicates the number of bytes, where 2 is a 16-bit short and
        -- 4 is a 32-bit integer.
        -- 'f' is a float real number.
        local fileData = binFile:read("a")
        local asefHeader = string.unpack(">i4", string.sub(fileData, 1, 4))
        local isAsef = asefHeader == 0x41534546
        -- print(strfmt("asefHeader: 0x%08x", asefHeader))
        -- print(isAsef)

        if not isAsef then
            -- https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md#header
            local asepriteHeader = string.unpack("I2", string.sub(fileData, 5, 6))
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

        -- Handle different color spaces.
        local colorSpace = args.colorSpace
            or defaults.colorSpace --[[@as string]]

        local aseColors = readAse(fileData, colorSpace)

        binFile:close()

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
        local lenAseColors = #aseColors

        app.transaction(function()
            palette:resize(lenAseColors)
            local j = 0
            while j < lenAseColors do
                palette:setColor(j, aseColors[1 + j])
                j = j + 1
            end
        end)

        if oldColorMode == ColorMode.INDEXED then
            app.command.ChangePixelFormat { format = "indexed" }
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

        -- Unpack arguments.
        local args = dlg.data
        local exportFilepath = args.exportFilepath --[[@as string]]
        local colorFormat = args.colorFormat
            or defaults.colorFormat --[[@as string]]
        local colorSpace = args.colorSpace
            or defaults.colorSpace --[[@as string]]
        local grayMethod = args.grayMethod
            or defaults.grayMethod --[[@as string]]

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

        local binStr = writeAse(palette, colorFormat, colorSpace, grayMethod)
        binFile:write(binStr)
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