--[[
    ACO:
    https://devblog.cyotek.com/post/reading-photoshop-color-swatch-aco-files-using-csharp
    https://devblog.cyotek.com/post/writing-photoshop-color-swatch-aco-files-using-csharp

    ASE:
    https://devblog.cyotek.com/post/reading-adobe-swatch-exchange-ase-files-using-csharp
    https://devblog.cyotek.com/post/writing-adobe-swatch-exchange-ase-files-using-csharp
]]

local colorFormats = { "CMYK", "GRAY", "HSB", "RGB", "LAB" }
local colorSpaces = { "ADOBE_RGB", "S_RGB" }
local grayMethods = { "HSI", "HSL", "HSV", "LUMA" }
local fileExts = { "aco", "ase" }

local defaults = {
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

---@param hue number
---@param sat number
---@param val number
---@return number
---@return number
---@return number
local function hsvToRgb(hue, sat, val)
    local h = (hue % 1.0) * 6.0
    local s = math.min(math.max(sat, 0.0), 1.0)
    local v = math.min(math.max(val, 0.0), 1.0)

    local sector = math.floor(h)
    local secf = sector + 0.0
    local tint1 = v * (1.0 - s)
    local tint2 = v * (1.0 - s * (h - secf))
    local tint3 = v * (1.0 - s * (1.0 + secf - h))

    if sector == 0 then
        return v, tint3, tint1
    elseif sector == 1 then
        return tint2, v, tint1
    elseif sector == 2 then
        return tint1, v, tint3
    elseif sector == 3 then
        return tint1, tint2, v
    elseif sector == 4 then
        return tint3, tint1, v
    elseif sector == 5 then
        return v, tint1, tint2
    end

    return 0.0, 0.0, 0.0
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

---@param fileData string
---@param colorSpace "ADOBE_SRGB"|"S_RGB"
---@return Color[]
local function readAco(fileData, colorSpace)
    ---@type Color[]
    local aseColors = { Color { r = 0, g = 0, b = 0, a = 0 } }

    local strsub = string.sub
    local strunpack = string.unpack
    local floor = math.floor
    local max = math.max
    local min = math.min

    local isAdobe = colorSpace == "ADOBE_RGB"

    local fmtGry = 0x0008
    local fmtLab = 0x0007
    local fmtCmyk = 0x0002
    local fmtHsb = 0x0001

    local initHead = strunpack(">I2", strsub(fileData, 1, 2))
    local numColors = strunpack(">I2", strsub(fileData, 3, 4))
    local initIsV2 = initHead == 0x0002
    local blockLen = 10

    -- print(string.format("%02X", initHead))
    -- print(initIsV2)
    -- print(string.format("numColors: %d", numColors))

    local i = 0
    local j = 5
    while i < numColors do
        i = i + 1

        -- print(string.format("\ni: %d, j: %d", i, j))

        local fmt = strunpack(">I2", strsub(fileData, j, j + 1))
        local upkw = strunpack(">I2", strsub(fileData, j + 2, j + 3))
        local upkx = strunpack(">I2", strsub(fileData, j + 4, j + 5))
        local upky = strunpack(">I2", strsub(fileData, j + 6, j + 7))
        local upkz = strunpack(">I2", strsub(fileData, j + 8, j + 9))

        -- print(string.format("fmt: %d (0x%02x)", fmt, fmt))
        -- print(string.format("upw: %d (0x%02x)", upkw, upkw))
        -- print(string.format("upx: %d (0x%02x)", upkx, upkx))
        -- print(string.format("upy: %d (0x%02x)", upky, upky))
        -- print(string.format("upz: %d (0x%02x)", upkz, upkz))

        local r01 = 0.0
        local g01 = 0.0
        local b01 = 0.0

        if fmt == fmtGry then
            local gray = (upkw * 0.0001) ^ (1.0 / 2.2)
            r01 = gray
            g01 = gray
            b01 = gray

            -- print(strfmt("GRAY: %.3f", gray))
        elseif fmt == fmtLab then
            -- Inverted order due to Krita.
            -- See for comparison:
            -- https://github.com/mayth/AcoDraw/blob/master/AcoDraw/ColorConverter.cs
            local l = upky / 655.35
            local a = (upkx - 32768) / 257.0
            local b = (upkw - 32768) / 257.0

            local x, y, z = cieLabToCieXyz(l, a, b)

            local r01Linear = 0.0
            local g01Linear = 0.0
            local b01Linear = 0.0

            if isAdobe then
                r01Linear, g01Linear, b01Linear = cieXyzToLinearAdobeRgb(x, y, z)
                r01, g01, b01 = linearAdobeRgbToGammaAdobeRgb(r01Linear, g01Linear, b01Linear)
            else
                r01Linear, g01Linear, b01Linear = cieXyzToLinearsRgb(x, y, z)
                r01, g01, b01 = linearsRgbToGammasRgb(r01Linear, g01Linear, b01Linear)
            end

            -- print(strfmt(
            --     "LAB: l: %.3f, a: %.3f, b: %.3f",
            --     l, a, b))
        elseif fmt == fmtCmyk then
            local c = 1.0 - upkw / 65535.0
            local m = 1.0 - upkx / 65535.0
            local y = 1.0 - upky / 65535.0
            local k = 1.0 - upkz / 65535.0
            r01, g01, b01 = cmykToRgb(c, m, y, k)

            -- print(strfmt(
            --     "CMYK: c: %.3f, m: %.3f, y: %.3f, k: %.3f",
            --     c, m, y, k))
        elseif fmt == fmtHsb then
            local hue = upkw / 65535.0
            local saturation = upkx / 65535.0
            local value = upky / 65535.0
            r01, g01, b01 = hsvToRgb(hue, saturation, value)

            -- print(strfmt(
            --     "HSB: h: %.3f, s: %.3f, b: %.3f",
            --     hue, saturation, value))
        else
            r01 = upkw / 65535.0
            g01 = upkx / 65535.0
            b01 = upky / 65535.0

            -- print(strfmt(
            --     "RGB: r01: %.3f, g01: %.3f, b01: %.3f",
            --     r01, g01, b01))
        end

        local r8 = floor(min(max(r01, 0.0), 1.0) * 255.0 + 0.5)
        local g8 = floor(min(max(g01, 0.0), 1.0) * 255.0 + 0.5)
        local b8 = floor(min(max(b01, 0.0), 1.0) * 255.0 + 0.5)

        -- print(string.format(
        --     "r8: %d, g8: %d, b8: %d, (#%06x)",
        --     r8, g8, b8, r8 << 0x10 | g8 << 0x08 | b8))

        local aseColor = Color { r = r8, g = g8, b = b8, a = 255 }
        aseColors[1 + i] = aseColor

        if initIsV2 then
            -- Slots 10 and 11 are used by a constant 0.
            -- Length of the name is in characters, which are utf16, plus
            -- a terminal zero.
            -- local spacer = strunpack(">I2", strsub(fileData, j + 10, j + 11))
            local lenName = strunpack(">I2", strsub(fileData, j + 12, j + 13))
            -- print(string.format("spacer: 0x%02X", spacer))
            -- print(string.format("lenName: %d (0x%02X)", lenName, lenName))
            blockLen = 10
                + 2 -- spacer
                + 2 -- string length
                + (lenName + 1) * 2
        end

        j = j + blockLen
    end

    return aseColors
end

---@param fileData string
---@param colorSpace "ADOBE_SRGB"|"S_RGB"
---@return Color[]
local function readAse(fileData, colorSpace)
    ---@type Color[]
    local aseColors = { Color { r = 0, g = 0, b = 0, a = 0 } }

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

---@param r01 number
---@param g01 number
---@param b01 number
---@return number
---@return number
---@return number
local function rgbToHsv(r01, g01, b01)
    local gbmx = math.max(g01, b01)
    local gbmn = math.min(g01, b01)
    local mx = math.max(r01, gbmx)
    if mx < 0.00392156862745098 then
        return 0.0, 0.0, 0.0
    end
    local mn = math.min(r01, gbmn)
    local diff = mx - mn
    if diff < 0.00392156862745098 then
        local light = (mx + mn) * 0.5
        if light > 0.996078431372549 then
            return 0.0, 0.0, 1.0
        end
        return 0.0, 0.0, mx
    end
    local hue = 0.0
    if r01 == mx then
        hue = (g01 - b01) / diff
        if g01 < b01 then hue = hue + 6.0 end
    elseif g01 == mx then
        hue = 2.0 + (b01 - r01) / diff
    else
        hue = 4.0 + (r01 - g01) / diff
    end

    return hue / 6.0, diff / mx, mx
end

---@param palette Palette
---@param colorFormat "CMYK"|"GRAY"|"HSB"|"LAB"|"RGB"
---@param colorSpace "ADOBE_SRGB"|"S_RGB"
---@param grayMethod "HSI"|"HSL"|"HSV"|"LUMA"
---@return string
local function writeAco(palette, colorFormat, colorSpace, grayMethod)
    -- Cache commonly used methods.
    local strbyte = string.byte
    local strfmt = string.format
    local strpack = string.pack
    local tconcat = table.concat
    local tinsert = table.insert
    local floor = math.floor
    local max = math.max
    local min = math.min

    local lenPalette = #palette

    ---@type string[]
    local binWords = {}
    local numColors = 0

    local writeLab = colorFormat == "LAB"
    local writeGry = colorFormat == "GRAY"
    local writeCmyk = colorFormat == "CMYK"
    local writeHsb = colorFormat == "HSB"
    local calcLinear = writeLab or writeGry or writeCmyk

    local isAdobe = colorSpace == "ADOBE_RGB"

    local isGryHsv = grayMethod == "HSV"
    local isGryHsi = grayMethod == "HSI"
    local isGryHsl = grayMethod == "HSL"
    local isGryLuma = grayMethod == "LUMA"
    local isGryAdobeY = isAdobe and isGryLuma

    -- Color space varies by user preference.
    local pkColorFormat = strpack(">I2", 0)
    if writeGry then
        pkColorFormat = strpack(">I2", 8)
    elseif writeLab then
        pkColorFormat = strpack(">I2", 7)
    elseif writeCmyk then
        pkColorFormat = strpack(">I2", 2)
    elseif writeHsb then
        pkColorFormat = strpack(">I2", 1)
    end

    local i = 0
    while i < lenPalette do
        local aseColor = palette:getColor(i)
        if aseColor.alpha > 0 then
            numColors = numColors + 1

            -- Unpack color.
            local r8 = aseColor.red
            local g8 = aseColor.green
            local b8 = aseColor.blue

            local r01Gamma = r8 / 255.0
            local g01Gamma = g8 / 255.0
            local b01Gamma = b8 / 255.0

            local pkw = strpack(">I2", 0)
            local pkx = pkw
            local pky = pkw
            local pkz = pkw

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

                    -- Krita treats this as being in linear space.
                    local gray16 = floor((gray ^ 2.2) * 10000.0 + 0.5)
                    pkw = strpack(">I2", gray16)
                elseif writeCmyk then
                    local gray = grayMethodHsv(r01Gamma, g01Gamma, b01Gamma)
                    local c, m, y, black = rgbToCmyk(r01Gamma, g01Gamma, b01Gamma, gray)

                    -- Ink is inverted.
                    local c16 = floor((1.0 - c) * 65535.0 + 0.5)
                    local m16 = floor((1.0 - m) * 65535.0 + 0.5)
                    local y16 = floor((1.0 - y) * 65535.0 + 0.5)
                    local k16 = floor((1.0 - black) * 65535.0 + 0.5)

                    pkw = strpack(">I2", c16)
                    pkx = strpack(">I2", m16) -- TODO: Is this flipped with y?
                    pky = strpack(">I2", y16)
                    pkz = strpack(">I2", k16)
                elseif writeLab then
                    local l, a, b = cieXyzToCieLab(xCie, yCie, zCie)

                    -- Krita's interpretation of Lab format differs from the
                    -- file format specification.
                    -- https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/#50577411_pgfId-1055819
                    -- "The first three values in the color data are lightness,
                    -- a chrominance, and b chrominance . Lightness is a 16-bit
                    -- value from 0...10000. Chrominance components are
                    -- each 16-bit values from -12800...12700."
                    local l16 = floor(l * 655.35 + 0.5)
                    local a16 = 32768 + floor(257.0 * min(max(a, -127.5), 127.5))
                    local b16 = 32768 + floor(257.0 * min(max(b, -127.5), 127.5))

                    pkw = strpack(">I2", b16)
                    pkx = strpack(">I2", a16)
                    pky = strpack(">I2", l16)
                end
            elseif writeHsb then
                local h01, s01, v01 = rgbToHsv(r01Gamma, g01Gamma, b01Gamma)

                local h16 = floor(h01 * 65535.0 + 0.5)
                local s16 = floor(s01 * 65535.0 + 0.5)
                local v16 = floor(v01 * 65535.0 + 0.5)

                pkw = strpack(">I2", h16)
                pkx = strpack(">I2", s16)
                pky = strpack(">I2", v16)
            else
                local r16 = floor(r01Gamma * 65535.0 + 0.5)
                local g16 = floor(g01Gamma * 65535.0 + 0.5)
                local b16 = floor(b01Gamma * 65535.0 + 0.5)

                pkw = strpack(">I2", r16)
                pkx = strpack(">I2", g16)
                pky = strpack(">I2", b16)
            end

            binWords[#binWords + 1] = pkColorFormat
            binWords[#binWords + 1] = pkw
            binWords[#binWords + 1] = pkx
            binWords[#binWords + 1] = pky
            binWords[#binWords + 1] = pkz
        end

        i = i + 1
    end

    local pkNumColors = strpack(">I2", numColors)
    local pkVersion = strpack(">I2", 0x0001)
    tinsert(binWords, 1, pkNumColors)
    tinsert(binWords, 1, pkVersion)
    return tconcat(binWords, "")
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
                    local c, m, y, black = rgbToCmyk(r01Gamma, g01Gamma, b01Gamma, gray)

                    pkx = strpack(">f", c)
                    pky = strpack(">f", m)
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
        if fileExt ~= "ase" and fileExt ~= "aco" then
            app.alert {
                title = "Error",
                text = "File format must be ase or aco."
            }
            return
        end

        local binFile, err = io.open(importFilepath, "rb")
        if err ~= nil then
            if binFile then binFile:close() end
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

        if (not isAsef) and fileExt == "ase" then
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

        ---@type Color[]s
        local aseColors = {}
        if fileExt == "aco" then
            aseColors = readAco(fileData, colorSpace)
        else
            aseColors = readAse(fileData, colorSpace)
        end
        binFile:close()

        ---@diagnostic disable-next-line: deprecated
        local activeSprite = app.activeSprite
        if not activeSprite then
            local lenColors <const> = #aseColors
            local rtLen <const> = math.max(16,
                math.ceil(math.sqrt(math.max(1, lenColors))))

            -- local newFilePrefs = app.preferences.new_file
            local spec = ImageSpec {
                -- width = newFilePrefs.width,
                -- height = newFilePrefs.height,
                width = rtLen,
                height = rtLen,
                colorMode = ColorMode.RGB,
                transparentColor = 0
            }
            spec.colorSpace = ColorSpace { sRGB = true }

            local image = Image(spec)
            local pxItr = image:pixels()
            local index = 0
            for pixel in pxItr do
                if index < lenColors then
                    index = index + 1
                    local aseColor = aseColors[index]
                    pixel(aseColor.rgbaPixel)
                end
            end

            activeSprite = Sprite(spec)
            activeSprite.filename = app.fs.fileName(importFilepath)
            activeSprite.cels[1].image = image
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

        local fileExt = string.lower(app.fs.fileExtension(exportFilepath))
        if fileExt ~= "ase" and fileExt ~= "aco" then
            app.alert {
                title = "Error",
                text = "File format must be ase or aco."
            }
            return
        end

        local binFile, err = io.open(exportFilepath, "wb")
        if err ~= nil then
            if binFile then binFile:close() end
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

        local binStr = ""
        if fileExt == "aco" then
            binStr = writeAco(palette, colorFormat, colorSpace, grayMethod)
        else
            binStr = writeAse(palette, colorFormat, colorSpace, grayMethod)
        end
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