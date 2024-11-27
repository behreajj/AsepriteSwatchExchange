--[[
    ACO & ASE:
    https://medium.com/swlh/mastering-adobe-color-file-formats-d29e43fde8eb

    ACO:
    https://devblog.cyotek.com/post/reading-photoshop-color-swatch-aco-files-using-csharp
    https://devblog.cyotek.com/post/writing-photoshop-color-swatch-aco-files-using-csharp

    GIMP Lab format support:
    https://gitlab.gnome.org/GNOME/gimp/blob/gimp-2-10/app/core/gimppalette-load.c#L413
    https://gitlab.gnome.org/GNOME/gimp/-/merge_requests/849

    Krita Lab format support:
    https://github.com/KDE/krita/blob/master/libs/pigment/resources/KoColorSet.cpp#L1658

    Adobe spec:
    https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/#50577411_pgfId-1055819

    ASE:
    https://devblog.cyotek.com/post/reading-adobe-swatch-exchange-ase-files-using-csharp
    https://devblog.cyotek.com/post/writing-adobe-swatch-exchange-ase-files-using-csharp

    GIMP ASE support (NEW):
    https://gitlab.gnome.org/GNOME/gimp/blob/gimp-2-10/app/core/gimppalette-load.c#L931

    CIE-sRGB, CIE-AdobeRGB formulae:
    https://www.easyrgb.com/en/math.php

    Display P3 conversions to and from CIE XYZ:
    https://www.w3.org/TR/css-color-4/#color-conversion-code
    https://fujiwaratko.sakura.ne.jp/infosci/colorspace/colorspace2_e.html

    Ase files can be downloaded from https://color.adobe.com/ .
    This confirms that LAB format for Krita is right and GIMP is wrong.
    Bug report: https://gitlab.gnome.org/GNOME/gimp/-/issues/12478
]]

local colorFormats <const> = { "CMYK", "GRAY", "HSB", "LAB", "RGB" }
local colorSpaces <const> = { "ADOBE_RGB", "DISPLAY_P3", "S_RGB" }
local externalRefs <const> = { "GIMP", "KRITA", "OTHER" }
local fileExts <const> = { "aco", "act", "ase" }
local grayMethods <const> = { "HSI", "HSL", "HSV", "LUMA" }

local defaults <const> = {
    colorFormat = "RGB",
    colorSpace = "S_RGB",
    grayMethod = "LUMA",
    externalRef = "KRITA",
    preserveIndices = false
}

---@param l number
---@param a number
---@param b number
---@return number x
---@return number y
---@return number z
---@nodiscard
local function cieLabToCieXyz(l, a, b)
    local y = (l + 16.0) * 0.008620689655172414
    local x = a * 0.002 + y
    local z = y - b * 0.005

    local ye3 <const> = (y * y) * y
    local xe3 <const> = (x * x) * x
    local ze3 <const> = (z * z) * z

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
---@nodiscard
local function cieLumToAdobeGray(y)
    return y ^ 0.4547069271758437
end

---@param y number
---@return number
---@nodiscard
local function cieLumTosGray(y)
    return y <= 0.0031308 and y * 12.92
        or (y ^ 0.41666666666667) * 1.055 - 0.055
end

---@param x number
---@param y number
---@param z number
---@return number l
---@return number a
---@return number b
---@nodiscard
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

    local l <const> = 116.0 * vy - 16.0
    local a <const> = 500.0 * (vx - vy)
    local b <const> = 200.0 * (vy - vz)

    return l, a, b
end

---@param x number
---@param y number
---@param z number
---@return number r01Lnear
---@return number g01Lnear
---@return number b01Lnear
---@nodiscard
local function cieXyzToLinearAdobeRgb(x, y, z)
    return 2.04137 * x - 0.56495 * y - 0.34469 * z,
        -0.96927 * x + 1.87601 * y + 0.04156 * z,
        0.01345 * x - 0.11839 * y + 1.01541 * z
end

---@param x number
---@param y number
---@param z number
---@return number r01Lnear
---@return number g01Lnear
---@return number b01Lnear
---@nodiscard
local function cieXyzToLinearP3(x, y, z)
    return 2.493497 * x - 0.9313836 * y - 0.4027108 * z,
        -0.829489 * x + 1.7626641 * y + 0.023624687 * z,
        0.03584583 * x - 0.07617239 * y + 0.9568845 * z
end

---@param x number
---@param y number
---@param z number
---@return number r01Linear
---@return number g01Linear
---@return number b01Linear
---@nodiscard
local function cieXyzToLinearsRgb(x, y, z)
    return 3.2408123 * x - 1.5373085 * y - 0.49858654 * z,
        -0.969243 * x + 1.8759663 * y + 0.041555032 * z,
        0.0556384 * x - 0.20400746 * y + 1.0571296 * z
end

---@param c number
---@param m number
---@param y number
---@param k number
---@return number r01Gamma
---@return number g01Gamma
---@return number b01Gamma
---@nodiscard
local function cmykToRgb(c, m, y, k)
    local u <const> = 1.0 - k
    local r01 <const> = (1.0 - c) * u
    local g01 <const> = (1.0 - m) * u
    local b01 <const> = (1.0 - y) * u
    return r01, g01, b01
end

---@param r01Gamma number
---@param g01Gamma number
---@param b01Gamma number
---@return number r01Linear
---@return number g01Linear
---@return number b01Linear
---@nodiscard
local function gammaAdobeRgbToLinearAdobeRgb(r01Gamma, g01Gamma, b01Gamma)
    return r01Gamma ^ 2.19921875,
        g01Gamma ^ 2.19921875,
        b01Gamma ^ 2.19921875
end

---@param r01Gamma number
---@param g01Gamma number
---@param b01Gamma number
---@return number r01Linear
---@return number g01Linear
---@return number b01Linear
---@nodiscard
local function gammasRgbToLinearsRgb(r01Gamma, g01Gamma, b01Gamma)
    local r01Linear <const> = r01Gamma <= 0.04045
        and r01Gamma * 0.077399380804954
        or ((r01Gamma + 0.055) * 0.9478672985782) ^ 2.4
    local g01Linear <const> = g01Gamma <= 0.04045
        and g01Gamma * 0.077399380804954
        or ((g01Gamma + 0.055) * 0.9478672985782) ^ 2.4
    local b01Linear <const> = b01Gamma <= 0.04045
        and b01Gamma * 0.077399380804954
        or ((b01Gamma + 0.055) * 0.9478672985782) ^ 2.4
    return r01Linear, g01Linear, b01Linear
end

---@param r01 number
---@param g01 number
---@param b01 number
---@return number
---@nodiscard
local function grayMethodHsi(r01, g01, b01)
    return (r01 + g01 + b01) / 3.0
end

---@param r01 number
---@param g01 number
---@param b01 number
---@return number
---@nodiscard
local function grayMethodHsl(r01, g01, b01)
    return (math.min(r01, g01, b01) + math.max(r01, g01, b01)) * 0.5
end

---@param r01 number
---@param g01 number
---@param b01 number
---@return number
---@nodiscard
local function grayMethodHsv(r01, g01, b01)
    return math.max(r01, g01, b01)
end

---@param hue number
---@param sat number
---@param val number
---@return number r01Gamma
---@return number g01Gamma
---@return number b01Gamma
---@nodiscard
local function hsvToRgb(hue, sat, val)
    local h <const> = (hue % 1.0) * 6.0
    local s <const> = math.min(math.max(sat, 0.0), 1.0)
    local v <const> = math.min(math.max(val, 0.0), 1.0)

    local sector <const> = math.floor(h)
    local secf <const> = sector + 0.0
    local tint1 <const> = v * (1.0 - s)
    local tint2 <const> = v * (1.0 - s * (h - secf))
    local tint3 <const> = v * (1.0 - s * (1.0 + secf - h))

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
    elseif sector == 6 then
        return v, tint3, tint1
    end

    return 0.0, 0.0, 0.0
end

---@param r01Linear number
---@param g01Linear number
---@param b01Linear number
---@return number r01Gamma
---@return number g01Gamma
---@return number b01Gamma
---@nodiscard
local function linearAdobeRgbToGammaAdobeRgb(r01Linear, g01Linear, b01Linear)
    return r01Linear ^ 0.4547069271758437,
        g01Linear ^ 0.4547069271758437,
        b01Linear ^ 0.4547069271758437
end

---@param r01Linear number
---@param g01Linear number
---@param b01Linear number
---@return number x
---@return number y
---@return number z
---@nodiscard
local function linearAdobeRgbToCieXyz(r01Linear, g01Linear, b01Linear)
    return 0.57667 * r01Linear + 0.18555 * g01Linear + 0.18819 * b01Linear,
        0.29738 * r01Linear + 0.62735 * g01Linear + 0.07527 * b01Linear,
        0.02703 * r01Linear + 0.07069 * g01Linear + 0.99110 * b01Linear
end

---@param r01Linear number
---@param g01Linear number
---@param b01Linear number
---@return number x
---@return number y
---@return number z
---@nodiscard
local function linearP3ToCieXyz(r01Linear, g01Linear, b01Linear)
    return 0.48657095 * r01Linear + 0.2656677 * g01Linear + 0.19821729 * b01Linear,
        0.22897457 * r01Linear + 0.69173855 * g01Linear + 0.07928691 * b01Linear,
        0.0 * r01Linear + 0.04511338 * g01Linear + 1.0439444 * b01Linear
end

---@param r01Linear number
---@param g01Linear number
---@param b01Linear number
---@return number x
---@return number y
---@return number z
---@nodiscard
local function linearsRgbToCieXyz(r01Linear, g01Linear, b01Linear)
    return 0.41241086 * r01Linear + 0.35758457 * g01Linear + 0.1804538 * b01Linear,
        0.21264935 * r01Linear + 0.71516913 * g01Linear + 0.07218152 * b01Linear,
        0.019331759 * r01Linear + 0.11919486 * g01Linear + 0.95039004 * b01Linear
end

---@param r01Linear number
---@param g01Linear number
---@param b01Linear number
---@return number r01Gamma
---@return number g01Gamma
---@return number b01Gamma
---@nodiscard
local function linearsRgbToGammasRgb(r01Linear, g01Linear, b01Linear)
    local r01Gamma <const> = r01Linear <= 0.0031308
        and r01Linear * 12.92
        or (r01Linear ^ 0.41666666666667) * 1.055 - 0.055
    local g01Gamma <const> = g01Linear <= 0.0031308
        and g01Linear * 12.92
        or (g01Linear ^ 0.41666666666667) * 1.055 - 0.055
    local b01Gamma <const> = b01Linear <= 0.0031308
        and b01Linear * 12.92
        or (b01Linear ^ 0.41666666666667) * 1.055 - 0.055
    return r01Gamma, g01Gamma, b01Gamma
end

---@param fileData string
---@param colorSpace "ADOBE_RGB"|"DISPLAY_P3"|"S_RGB"
---@param externalRef "GIMP"|"KRITA"
---@return Color[]
---@nodiscard
local function readAco(fileData, colorSpace, externalRef)
    ---@type Color[]
    local aseColors <const> = { Color { r = 0, g = 0, b = 0, a = 0 } }

    local strsub <const> = string.sub
    local strunpack <const> = string.unpack
    local floor <const> = math.floor
    local max <const> = math.max
    local min <const> = math.min

    local isAdobe <const> = colorSpace == "ADOBE_RGB"
    local isP3 <const> = colorSpace == "DISPLAY_P3"
    local isKrita <const> = externalRef == "KRITA"
    local exponent = 1.0
    if isKrita then exponent = 1.0 / 2.2 end

    local fmtGry <const> = 0x0008
    local fmtLab <const> = 0x0007
    local fmtCmyk <const> = 0x0002
    local fmtHsb <const> = 0x0001

    local initHead <const> = strunpack(">I2", strsub(fileData, 1, 2))
    local numColors <const> = strunpack(">I2", strsub(fileData, 3, 4))
    local initIsV2 <const> = initHead == 0x0002
    local blockLen = 10

    -- print(string.format("%02X", initHead))
    -- print(initIsV2)
    -- print(string.format("numColors: %d", numColors))

    local i = 0
    local j = 5
    while i < numColors do
        i = i + 1

        -- print(string.format("\ni: %d, j: %d", i, j))

        local fmt <const> = strunpack(">I2", strsub(fileData, j, j + 1))

        local upkwStr <const> = strsub(fileData, j + 2, j + 3)
        local upkxStr <const> = strsub(fileData, j + 4, j + 5)
        local upkyStr <const> = strsub(fileData, j + 6, j + 7)
        local upkzStr <const> = strsub(fileData, j + 8, j + 9)

        local upkw <const> = strunpack(">I2", upkwStr)
        local upkx = strunpack(">I2", upkxStr)
        local upky = strunpack(">I2", upkyStr)
        local upkz <const> = strunpack(">I2", upkzStr)

        -- print(string.format("fmt: %d (0x%02x)", fmt, fmt))
        -- print(string.format("upw: %d (0x%02x)", upkw, upkw))
        -- print(string.format("upx: %d (0x%02x)", upkx, upkx))
        -- print(string.format("upy: %d (0x%02x)", upky, upky))
        -- print(string.format("upz: %d (0x%02x)", upkz, upkz))

        local r01 = 0.0
        local g01 = 0.0
        local b01 = 0.0

        if fmt == fmtGry then
            local gray <const> = (upkw * 0.0001) ^ exponent
            r01 = gray
            g01 = gray
            b01 = gray

            -- print(strfmt("GRAY: %.3f", gray))
        elseif fmt == fmtLab then
            local l = 0.0
            local a = 0.0
            local b = 0.0

            if isKrita then
                l = upky / 655.35
                a = (upkx - 32768) / 257.0
                b = (upkw - 32768) / 257.0
            else
                upkx = strunpack(">i2", upkxStr)
                upky = strunpack(">i2", upkyStr)

                l = upkw * 0.01
                a = upkx * 0.01
                b = upky * 0.01
            end

            local x <const>, y <const>, z <const> = cieLabToCieXyz(l, a, b)

            local r01Linear = 0.0
            local g01Linear = 0.0
            local b01Linear = 0.0

            if isAdobe then
                r01Linear, g01Linear, b01Linear = cieXyzToLinearAdobeRgb(x, y, z)
                r01, g01, b01 = linearAdobeRgbToGammaAdobeRgb(r01Linear, g01Linear, b01Linear)
            elseif isP3 then
                r01Linear, g01Linear, b01Linear = cieXyzToLinearP3(x, y, z)
                r01, g01, b01 = linearsRgbToGammasRgb(r01Linear, g01Linear, b01Linear)
            else
                r01Linear, g01Linear, b01Linear = cieXyzToLinearsRgb(x, y, z)
                r01, g01, b01 = linearsRgbToGammasRgb(r01Linear, g01Linear, b01Linear)
            end

            -- print(strfmt(
            --     "LAB: l: %.3f, a: %.3f, b: %.3f",
            --     l, a, b))
        elseif fmt == fmtCmyk then
            local c <const> = 1.0 - upkw / 65535.0
            local m <const> = 1.0 - upkx / 65535.0
            local y <const> = 1.0 - upky / 65535.0
            local k <const> = 1.0 - upkz / 65535.0
            r01, g01, b01 = cmykToRgb(c, m, y, k)

            -- print(strfmt(
            --     "CMYK: c: %.3f, m: %.3f, y: %.3f, k: %.3f",
            --     c, m, y, k))
        elseif fmt == fmtHsb then
            local hue <const> = upkw / 65535.0
            local saturation <const> = upkx / 65535.0
            local value <const> = upky / 65535.0
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

        local r8 <const> = floor(min(max(r01, 0.0), 1.0) * 255.0 + 0.5)
        local g8 <const> = floor(min(max(g01, 0.0), 1.0) * 255.0 + 0.5)
        local b8 <const> = floor(min(max(b01, 0.0), 1.0) * 255.0 + 0.5)

        -- print(string.format(
        --     "r8: %d, g8: %d, b8: %d, (#%06x)",
        --     r8, g8, b8, r8 << 0x10 | g8 << 0x08 | b8))

        local aseColor <const> = Color { r = r8, g = g8, b = b8, a = 255 }
        aseColors[1 + i] = aseColor

        if initIsV2 then
            -- Slots 10 and 11 are used by a constant 0.
            -- Length of the name is in characters, which are utf16, plus
            -- a terminal zero.
            -- local spacer = strunpack(">I2", strsub(fileData, j + 10, j + 11))
            local lenName <const> = strunpack(">I2", strsub(fileData, j + 12, j + 13))
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
---@param preserveIndices boolean
---@return Color[]
---@nodiscard
local function readAct(fileData, preserveIndices)
    local lenFileData <const> = #fileData
    local is772 <const> = lenFileData == 772
    local numColors = 256
    -- local alphaIndex = -1
    if is772 then
        -- Neither GIMP nor Krita supports 772, so this was tested with
        -- palettes from https://fornaxvoid.com/colorpalettes/ .
        local ncParsed <const> = string.unpack(">I2", string.sub(fileData, 769, 770))
        numColors = math.min(ncParsed, 256)
        -- print(string.format(
        --     "ncParsed: %d, numColors: %d",
        --     ncParsed, numColors))

        -- local aiParsed <const> = string.unpack(">I2", string.sub(fileData, 771, 772))
        -- if aiParsed > 0 and aiParsed < numColors then
        -- alphaIndex = aiParsed
        -- end
        -- print(string.format(
        --     "aiParsed: %d, alphaIndex: %d",
        --     aiParsed, alphaIndex))
    end

    local strbyte <const> = string.byte

    ---@type table<integer, integer[]>
    local hexDict <const> = {}
    local uniqueCount = 0
    local i = 0
    local j = 0
    while i < numColors do
        -- if i ~= alphaIndex then
        local r <const>, g <const>, b <const> = strbyte(fileData, 1 + j, 3 + j)
        local hex <const> = 0xff000000 | b << 0x10 | g << 0x08 | r

        if hexDict[hex] then
            local indices <const> = hexDict[hex]
            indices[#indices + 1] = 1 + i
        else
            hexDict[hex] = { 1 + i }
            uniqueCount = uniqueCount + 1
        end
        -- end
        i = i + 1
        j = j + 3
    end

    ---@type Color[]
    local aseColors <const> = {}
    if preserveIndices then
        for hex, idcs in pairs(hexDict) do
            local r <const> = hex & 0xff
            local g <const> = hex >> 0x08 & 0xff
            local b <const> = hex >> 0x10 & 0xff
            local aseColor <const> = Color { r = r, g = g, b = b, a = 255 }

            local lenIdcs <const> = #idcs
            local k = 0
            while k < lenIdcs do
                k = k + 1
                local idx <const> = idcs[k]
                aseColors[idx] = aseColor
            end
        end
    else
        ---@type integer[]
        local sortedSet <const> = {}
        for hex, _ in pairs(hexDict) do
            sortedSet[#sortedSet + 1] = hex
        end

        table.sort(sortedSet, function(a, b)
            return hexDict[a][1] < hexDict[b][1]
        end)

        local k = 0
        while k < uniqueCount do
            k = k + 1
            local hex <const> = sortedSet[k]
            local r <const> = hex & 0xff
            local g <const> = hex >> 0x08 & 0xff
            local b <const> = hex >> 0x10 & 0xff
            aseColors[k] = Color { r = r, g = g, b = b, a = 255 }
        end

        if #aseColors < 256 then
            table.insert(aseColors, 1, Color { r = 0, g = 0, b = 0, a = 0 })
        end
    end

    return aseColors
end

---@param fileData string
---@param colorSpace "ADOBE_RGB"|"DISPLAY_P3"|"S_RGB"
---@param externalRef "GIMP"|"KRITA"|"OTHER"
---@return Color[]
---@nodiscard
local function readAse(fileData, colorSpace, externalRef)
    ---@type Color[]
    local aseColors <const> = { Color { r = 0, g = 0, b = 0, a = 0 } }

    local strlower <const> = string.lower
    local strsub <const> = string.sub
    local strunpack <const> = string.unpack
    local floor <const> = math.floor
    local max <const> = math.max
    local min <const> = math.min

    local isGimp = externalRef == "GIMP"
    local isKrita = externalRef == "KRITA"
    local lScalar = 100.0
    if isGimp then lScalar = 1.0 end
    if isKrita then lScalar = 100.0 end

    local lenFileData <const> = #fileData
    local isAdobe <const> = colorSpace == "ADOBE_RGB"
    local isP3 <const> = colorSpace == "DISPLAY_P3"
    local groupNesting = 0

    -- Ignore version block (0010) in chars 5, 6, 7, 8.
    -- local numColors = strunpack(">i4", strsub(fileData, 9, 12))
    -- print("numColors: " .. numColors)

    local i = 13
    while i < lenFileData do
        local blockLen = 2
        local blockHeader <const> = strunpack(">i2", strsub(fileData, i, i + 1))
        local isGroup <const> = blockHeader == 0xc001
        local isEntry <const> = blockHeader == 0x0001
        if isGroup or isEntry then
            -- Excludes header start.
            blockLen = strunpack(">i4", strsub(fileData, i + 2, i + 5))
            -- print("blockLen: " .. blockLen)

            -- The length is the number of chars in a string. The string
            -- is encoded in UTF-16, so it'd be 2x number of binary chars.
            -- A terminal zero is included in the length.
            --
            -- Ase files downloaded from Lospec use their lower-case 6 digit
            -- hexadecimal value as a name, e.g., "aabbcc".
            local lenChars16 <const> = strunpack(">i2", strsub(fileData, i + 6, i + 7))
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

                local iOffset <const> = lenChars16 * 2 + i

                -- Color formats do not need to be unpacked, since they are
                -- human readable strings.
                local colorFormat <const> = strlower(strsub(fileData, iOffset + 8, iOffset + 11))
                if colorFormat == "rgb " then
                    -- print("RGB color space.")

                    local r01 <const> = strunpack(">f", strsub(fileData, iOffset + 12, iOffset + 15))
                    local g01 <const> = strunpack(">f", strsub(fileData, iOffset + 16, iOffset + 19))
                    local b01 <const> = strunpack(">f", strsub(fileData, iOffset + 20, iOffset + 23))
                    -- print(strfmt("%.6f, %.6f, %.6f", r01, g01, b01))

                    aseColors[#aseColors + 1] = Color {
                        r = floor(min(max(r01, 0.0), 1.0) * 255.0 + 0.5),
                        g = floor(min(max(g01, 0.0), 1.0) * 255.0 + 0.5),
                        b = floor(min(max(b01, 0.0), 1.0) * 255.0 + 0.5),
                        a = 255
                    }
                elseif colorFormat == "cmyk" then
                    -- print("CMYK color space")

                    local c <const> = strunpack(">f", strsub(fileData, iOffset + 12, iOffset + 15))
                    local m <const> = strunpack(">f", strsub(fileData, iOffset + 16, iOffset + 19))
                    local y <const> = strunpack(">f", strsub(fileData, iOffset + 20, iOffset + 23))
                    local k <const> = strunpack(">f", strsub(fileData, iOffset + 24, iOffset + 27))

                    local r01, g01, b01 = cmykToRgb(c, m, y, k)
                    if isGimp then
                        if isAdobe then
                            r01, g01, b01 = linearAdobeRgbToGammaAdobeRgb(r01, g01, b01)
                        elseif isP3 then
                            r01, g01, b01 = linearsRgbToGammasRgb(r01, g01, b01)
                        else
                            r01, g01, b01 = linearsRgbToGammasRgb(r01, g01, b01)
                        end
                    end

                    aseColors[#aseColors + 1] = Color {
                        r = floor(min(max(r01, 0.0), 1.0) * 255.0 + 0.5),
                        g = floor(min(max(g01, 0.0), 1.0) * 255.0 + 0.5),
                        b = floor(min(max(b01, 0.0), 1.0) * 255.0 + 0.5),
                        a = 255
                    }
                elseif colorFormat == "lab " then
                    -- print("Lab color space")

                    local l <const> = strunpack(">f", strsub(fileData, iOffset + 12, iOffset + 15))
                    local a <const> = strunpack(">f", strsub(fileData, iOffset + 16, iOffset + 19))
                    local b <const> = strunpack(">f", strsub(fileData, iOffset + 20, iOffset + 23))

                    local x <const>, y <const>, z <const> = cieLabToCieXyz(l * lScalar, a, b)

                    local r01Linear = 0.0
                    local g01Linear = 0.0
                    local b01Linear = 0.0

                    local r01Gamma = 0.0
                    local g01Gamma = 0.0
                    local b01Gamma = 0.0

                    if isAdobe then
                        r01Linear, g01Linear, b01Linear = cieXyzToLinearAdobeRgb(x, y, z)
                        r01Gamma, g01Gamma, b01Gamma = linearAdobeRgbToGammaAdobeRgb(r01Linear, g01Linear, b01Linear)
                    elseif isP3 then
                        r01Linear, g01Linear, b01Linear = cieXyzToLinearP3(x, y, z)
                        r01Gamma, g01Gamma, b01Gamma = linearsRgbToGammasRgb(r01Linear, g01Linear, b01Linear)
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
                elseif colorFormat == "gray" then
                    -- print("Gray color space")

                    local v01 <const> = strunpack(">f", strsub(fileData, iOffset + 12, iOffset + 15))
                    local v8 <const> = floor(min(max(v01, 0.0), 1.0) * 255.0 + 0.5)
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
---@return number c
---@return number m
---@return number y
---@return number k
---@nodiscard
local function rgbToCmyk(r01, g01, b01, gray)
    local c = 0.0
    local m = 0.0
    local y = 0.0
    local k <const> = 1.0 - gray
    if k ~= 1.0 then
        local scalar <const> = 1.0 / (1.0 - k)
        c = (1.0 - r01 - k) * scalar
        m = (1.0 - g01 - k) * scalar
        y = (1.0 - b01 - k) * scalar
    end
    return c, m, y, k
end

---@param r01 number
---@param g01 number
---@param b01 number
---@return number h
---@return number s
---@return number v
---@nodiscard
local function rgbToHsv(r01, g01, b01)
    local gbmx <const> = math.max(g01, b01)
    local gbmn <const> = math.min(g01, b01)
    local mx <const> = math.max(r01, gbmx)
    if mx < 0.00392156862745098 then
        return 0.0, 0.0, 0.0
    end
    local mn <const> = math.min(r01, gbmn)
    local diff <const> = mx - mn
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
---@return string
---@nodiscard
local function writeAct(palette)
    ---@type table<integer, integer>
    local hexDict <const> = {}
    local uniqueCount = 0
    local lenPalette <const> = #palette
    local h = 0
    while h < lenPalette do
        local aseColor <const> = palette:getColor(h)
        if aseColor.alpha > 0 then
            local r8 <const> = aseColor.red
            local g8 <const> = aseColor.green
            local b8 <const> = aseColor.blue
            local hex <const> = 0xff000000 | b8 << 0x10 | g8 << 0x08 | r8
            if uniqueCount < 256 and (not hexDict[hex]) then
                hexDict[hex] = uniqueCount
                uniqueCount = uniqueCount + 1
            end
        end
        h = h + 1
    end

    ---@type string[]
    local binWords <const> = {}
    local strchar <const> = string.char
    for hex, idx in pairs(hexDict) do
        local r8 <const> = hex & 0xff
        local g8 <const> = hex >> 0x08 & 0xff
        local b8 <const> = hex >> 0x10 & 0xff
        local j <const> = idx * 3
        binWords[1 + j] = strchar(r8)
        binWords[2 + j] = strchar(g8)
        binWords[3 + j] = strchar(b8)
    end

    local char0 <const> = strchar(0)
    while #binWords < 768 do binWords[#binWords + 1] = char0 end
    return table.concat(binWords, "")
end

---@param palette Palette
---@param colorFormat "CMYK"|"GRAY"|"HSB"|"LAB"|"RGB"
---@param colorSpace "ADOBE_RGB"|"DISPLAY_P3"|"S_RGB"
---@param grayMethod "HSI"|"HSL"|"HSV"|"LUMA"
---@param externalRef "GIMP"|"KRITA"
---@return string
---@nodiscard
local function writeAco(
    palette,
    colorFormat,
    colorSpace,
    grayMethod,
    externalRef)
    -- Cache commonly used methods.
    local strpack <const> = string.pack
    local tconcat <const> = table.concat
    local tinsert <const> = table.insert
    local floor <const> = math.floor
    local max <const> = math.max
    local min <const> = math.min

    local lenPalette <const> = #palette

    ---@type string[]
    local binWords <const> = {}
    local numColors = 0

    local writeLab <const> = colorFormat == "LAB"
    local writeGry <const> = colorFormat == "GRAY"
    local writeCmyk <const> = colorFormat == "CMYK"
    local writeHsb <const> = colorFormat == "HSB"
    local calcLinear <const> = writeLab or writeGry or writeCmyk

    local isAdobe <const> = colorSpace == "ADOBE_RGB"
    local isP3 <const> = colorSpace == "DISPLAY_P3"
    local isKrita <const> = externalRef == "KRITA"

    -- Krita and GIMP treat gray differently
    local exponent = 1.0
    if isKrita then exponent = 2.2 end

    local isGryHsv <const> = grayMethod == "HSV"
    local isGryHsi <const> = grayMethod == "HSI"
    local isGryHsl <const> = grayMethod == "HSL"
    local isGryLuma <const> = grayMethod == "LUMA"
    local isGryAdobeY <const> = isAdobe and isGryLuma
    local isGryP3Y <const> = isP3 and isGryLuma

    local pkZero <const> = strpack(">I2", 0)
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
        local aseColor <const> = palette:getColor(i)
        if aseColor.alpha > 0 then
            -- Unpack color.
            local r8 <const> = aseColor.red
            local g8 <const> = aseColor.green
            local b8 <const> = aseColor.blue

            local r01Gamma <const> = r8 / 255.0
            local g01Gamma <const> = g8 / 255.0
            local b01Gamma <const> = b8 / 255.0

            local pkw = pkZero
            local pkx = pkZero
            local pky = pkZero
            local pkz = pkZero

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
                elseif isP3 then
                    r01Linear, g01Linear, b01Linear = gammasRgbToLinearsRgb(r01Gamma, g01Gamma, b01Gamma)
                    xCie, yCie, zCie = linearP3ToCieXyz(r01Linear, g01Linear, b01Linear)
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
                    elseif isGryP3Y then
                        gray = cieLumTosGray(yCie)
                    else
                        gray = cieLumTosGray(yCie)
                    end

                    -- Krita treats gray as being in linear space.
                    -- Photopea does not open gray correctly.
                    -- https://1j01.github.io/anypalette.js/demo opens these
                    -- as much darker.
                    local gray16 <const> = floor((gray ^ exponent) * 10000.0 + 0.5)
                    pkw = strpack(">I2", gray16)
                elseif writeCmyk then
                    local gray <const> = grayMethodHsv(r01Gamma, g01Gamma, b01Gamma)
                    local c <const>, m <const>, y <const>, k <const> = rgbToCmyk(r01Gamma, g01Gamma, b01Gamma, gray)

                    -- Ink is inverted.
                    local c16 <const> = floor((1.0 - c) * 65535.0 + 0.5)
                    local m16 <const> = floor((1.0 - m) * 65535.0 + 0.5)
                    local y16 <const> = floor((1.0 - y) * 65535.0 + 0.5)
                    local k16 <const> = floor((1.0 - k) * 65535.0 + 0.5)

                    pkw = strpack(">I2", c16)
                    pkx = strpack(">I2", m16)
                    pky = strpack(">I2", y16)
                    pkz = strpack(">I2", k16)
                elseif writeLab then
                    local l <const>, a <const>, b <const> = cieXyzToCieLab(xCie, yCie, zCie)

                    -- Krita's interpretation of Lab format differs from the
                    -- file format specification:
                    -- "The first three values in the color data are lightness,
                    -- a chrominance, and b chrominance . Lightness is a 16-bit
                    -- value from 0...10000. Chrominance components are
                    -- each 16-bit values from -12800...12700."
                    local l16 = 0
                    local a16 = 0
                    local b16 = 0

                    if isKrita then
                        l16 = floor(l * 655.35 + 0.5)
                        a16 = 32768 + floor(257.0 * min(max(a, -127.5), 127.5))
                        b16 = 32768 + floor(257.0 * min(max(b, -127.5), 127.5))

                        pky = strpack(">I2", l16)
                        pkx = strpack(">I2", a16)
                        pkw = strpack(">I2", b16)
                    else
                        -- This opens correctly in Photopea https://www.photopea.com/ .
                        l16 = floor(l * 100.0 + 0.5)
                        a16 = floor(min(max(a, -127.5), 127.5)) * 100
                        b16 = floor(min(max(b, -127.5), 127.5)) * 100

                        pkw = strpack(">I2", l16)
                        pkx = strpack(">i2", a16)
                        pky = strpack(">i2", b16)
                    end
                end
            elseif writeHsb then
                local h01 <const>, s01 <const>, v01 <const> = rgbToHsv(r01Gamma, g01Gamma, b01Gamma)

                local h16 <const> = floor(h01 * 65535.0 + 0.5)
                local s16 <const> = floor(s01 * 65535.0 + 0.5)
                local v16 <const> = floor(v01 * 65535.0 + 0.5)

                pkw = strpack(">I2", h16)
                pkx = strpack(">I2", s16)
                pky = strpack(">I2", v16)
            else
                local r16 <const> = floor(r01Gamma * 65535.0 + 0.5)
                local g16 <const> = floor(g01Gamma * 65535.0 + 0.5)
                local b16 <const> = floor(b01Gamma * 65535.0 + 0.5)

                pkw = strpack(">I2", r16)
                pkx = strpack(">I2", g16)
                pky = strpack(">I2", b16)
            end

            local n5 <const> = numColors * 5
            numColors = numColors + 1

            binWords[1 + n5] = pkColorFormat
            binWords[2 + n5] = pkw
            binWords[3 + n5] = pkx
            binWords[4 + n5] = pky
            binWords[5 + n5] = pkz
        end

        i = i + 1
    end

    local pkNumColors <const> = strpack(">I2", numColors)
    local pkVersion <const> = strpack(">I2", 0x0001)
    tinsert(binWords, 1, pkNumColors)
    tinsert(binWords, 1, pkVersion)
    return tconcat(binWords, "")
end

---@param palette Palette
---@param colorFormat "CMYK"|"GRAY"|"LAB"|"RGB"
---@param colorSpace "ADOBE_RGB"|"DISPLAY_P3"|"S_RGB"
---@param grayMethod "HSI"|"HSL"|"HSV"|"LUMA"
---@param externalRef "GIMP"|"KRITA"|"OTHER"
---@return string
---@nodiscard
local function writeAse(
    palette,
    colorFormat,
    colorSpace,
    grayMethod,
    externalRef)
    -- Cache commonly used methods.
    local strbyte <const> = string.byte
    local strfmt <const> = string.format
    local strpack <const> = string.pack
    local tconcat <const> = table.concat

    local lenPalette <const> = #palette

    ---@type string[]
    local bin <const> = {}
    local lenBin = 0
    local numColors = 0

    local pkSignature <const> = strpack(">i4", 0x41534546) -- "ASEF"
    local pkVersion <const> = strpack(">i4", 0x00010000)   -- 1.00

    -- If signed pack is used, then this raises an integer overflow error.
    local groupOpen <const> = strpack(">I2", 0xc001)
    local groupName <const> = "Palette"
    local lenGroupName <const> = #groupName
    local pkLenGroupName <const> = strpack(">i2", lenGroupName + 1)
    local pkStrTerminus <const> = strpack(">i2", 0)
    local pkGroupBlockLen <const> = strpack(">i4", 2 + 2 * (lenGroupName + 1))

    bin[lenBin + 1] = pkSignature
    bin[lenBin + 2] = pkVersion
    bin[lenBin + 3] = "" -- Number of blocks (overwritten at end)
    bin[lenBin + 4] = groupOpen
    bin[lenBin + 5] = pkGroupBlockLen
    bin[lenBin + 6] = pkLenGroupName
    lenBin = lenBin + 6

    -- Write group name to 16-bit characters.
    local h = 0
    while h < lenGroupName do
        h = h + 1
        local int8 <const> = strbyte(groupName, h, h + 1)
        local int16 <const> = strpack(">i2", int8)
        lenBin = lenBin + 1
        bin[lenBin] = int16
    end
    lenBin = lenBin + 1
    bin[lenBin] = pkStrTerminus

    local writeLab <const> = colorFormat == "LAB"
    local writeGry <const> = colorFormat == "GRAY"
    local writeCmyk <const> = colorFormat == "CMYK"
    local calcLinear <const> = writeLab or writeGry or writeCmyk

    local isAdobe <const> = colorSpace == "ADOBE_RGB"
    local isP3 <const> = colorSpace == "DISPLAY_P3"

    local isGryHsv <const> = grayMethod == "HSV"
    local isGryHsi <const> = grayMethod == "HSI"
    local isGryHsl <const> = grayMethod == "HSL"
    local isGryLuma <const> = grayMethod == "LUMA"
    local isGryAdobeY <const> = isAdobe and isGryLuma
    local isGryP3Y <const> = isP3 and isGryLuma

    local lScalar = 0.01
    local isGimp <const> = externalRef == "GIMP"
    local isKrita <const> = externalRef == "KRITA"
    if isGimp then lScalar = 1.0 end
    if isKrita then lScalar = 0.01 end

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

    local pkEntryHeader <const> = strpack(">i2", 0x0001)
    local pkNormalColorMode <const> = strpack(">i2", 0x0002) -- global|spot|normal
    local pkLenChars16 <const> = strpack(">i2", 7)           -- eg., "aabbcc" & 0

    local i = 0
    while i < lenPalette do
        local aseColor <const> = palette:getColor(i)
        if aseColor.alpha > 0 then
            numColors = numColors + 1

            -- Unpack color.
            local r8 <const> = aseColor.red
            local g8 <const> = aseColor.green
            local b8 <const> = aseColor.blue

            -- Write name.
            local hex24 <const> = r8 << 0x10 | g8 << 0x08 | b8
            local nameStr8 <const> = strfmt("%06x", hex24)

            -- Write color block header.
            bin[lenBin + 1] = pkEntryHeader
            bin[lenBin + 2] = pkBlockLen
            bin[lenBin + 3] = pkLenChars16
            lenBin = lenBin + 3

            -- Write name to 16-bit characters.
            local j = 0
            while j < 6 do
                j = j + 1
                local int8 <const> = strbyte(nameStr8, j, j + 1)
                local int16 <const> = strpack(">i2", int8)
                lenBin = lenBin + 1
                bin[lenBin] = int16
            end
            lenBin = lenBin + 1
            bin[lenBin] = pkStrTerminus -- 16

            lenBin = lenBin + 1
            bin[lenBin] = pkColorFormat -- 20

            local r01Gamma <const> = r8 / 255.0
            local g01Gamma <const> = g8 / 255.0
            local b01Gamma <const> = b8 / 255.0

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
                elseif isP3 then
                    r01Linear, g01Linear, b01Linear = gammasRgbToLinearsRgb(r01Gamma, g01Gamma, b01Gamma)
                    xCie, yCie, zCie = linearP3ToCieXyz(r01Linear, g01Linear, b01Linear)
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
                    elseif isGryP3Y then
                        gray = cieLumTosGray(yCie)
                    else
                        gray = cieLumTosGray(yCie)
                    end

                    pkx = strpack(">f", gray)
                    lenBin = lenBin + 1
                    bin[lenBin] = pkx -- 24
                elseif writeCmyk then
                    local gray = 0.0
                    local c = 0.0
                    local m = 0.0
                    local y = 0.0
                    local k = 0.0
                    if isGimp then
                        gray = grayMethodHsv(r01Linear, g01Linear, b01Linear)
                        c, m, y, k = rgbToCmyk(r01Linear, g01Linear, b01Linear, gray)
                    else
                        gray = grayMethodHsv(r01Gamma, g01Gamma, b01Gamma)
                        c, m, y, k = rgbToCmyk(r01Gamma, g01Gamma, b01Gamma, gray)
                    end

                    pkx = strpack(">f", c)
                    pky = strpack(">f", m)
                    pkz = strpack(">f", y)
                    local pkw <const> = strpack(">f", k)

                    bin[lenBin + 1] = pkx -- 24
                    bin[lenBin + 2] = pky -- 28
                    bin[lenBin + 3] = pkz -- 32
                    bin[lenBin + 4] = pkw -- 36
                    lenBin = lenBin + 4
                elseif writeLab then
                    local l <const>, a <const>, b <const> = cieXyzToCieLab(xCie, yCie, zCie)

                    pkx = strpack(">f", l * lScalar)
                    pky = strpack(">f", a)
                    pkz = strpack(">f", b)

                    bin[lenBin + 1] = pkx -- 24
                    bin[lenBin + 2] = pky -- 28
                    bin[lenBin + 3] = pkz -- 32
                    lenBin = lenBin + 3
                end
            else
                bin[lenBin + 1] = pkx -- 24
                bin[lenBin + 2] = pky -- 28
                bin[lenBin + 3] = pkz -- 32
                lenBin = lenBin + 3
            end

            lenBin = lenBin + 1
            bin[lenBin] = pkNormalColorMode -- 34 RGB, 26 Gray, 38 CMYK
        end

        i = i + 1
    end

    -- Open and close group are considered 2 extra blocks.
    local pkNumBlocks <const> = strpack(">i4", numColors + 2)
    bin[3] = pkNumBlocks

    local groupClose <const> = strpack(">I2", 0xc002)
    local groupZero <const> = strpack(">i4", 0)

    lenBin = lenBin + 1
    bin[lenBin] = groupClose
    lenBin = lenBin + 1
    bin[lenBin] = groupZero

    return tconcat(bin)
end

local dlg <const> = Dialog { title = "ASE Palette IO" }

dlg:combobox {
    id = "colorFormat",
    label = "Format:",
    option = defaults.colorFormat,
    options = colorFormats,
    focus = false,
    onchange = function()
        local args <const> = dlg.data

        local cf <const> = args.colorFormat --[[@as string]]
        local isGray <const> = cf == "GRAY"
        local isLab <const> = cf == "LAB"
        local isCmyk <const> = cf == "CMYK"

        local gm <const> = args.grayMethod --[[@as string]]
        local isLuma <const> = gm == "LUMA"

        dlg:modify { id = "grayMethod", visible = isGray }
        dlg:modify { id = "colorSpace", visible = isLab or isCmyk
            or (isGray and isLuma) }
        dlg:modify { id = "externalRef", visible = isLab or isCmyk or isGray }
    end
}

dlg:newrow { always = false }

dlg:combobox {
    id = "grayMethod",
    label = "Method:",
    option = defaults.grayMethod,
    options = grayMethods,
    focus = false,
    visible = defaults.colorSpace == "GRAY",
    onchange = function()
        local args <const> = dlg.data
        local cf <const> = args.colorFormat --[[@as string]]
        local gm <const> = args.grayMethod --[[@as string]]
        local isGray <const> = cf == "GRAY"
        local isLab <const> = cf == "LAB"
        local isLuma <const> = gm == "LUMA"
        dlg:modify { id = "colorSpace", visible = isLab or (isGray and isLuma) }
    end
}

dlg:newrow { always = false }

dlg:combobox {
    id = "colorSpace",
    label = "Space:",
    option = defaults.colorSpace,
    options = colorSpaces,
    focus = false,
    visible = defaults.colorSpace == "LAB"
        or defaults.colorSpace == "CMYK"
        or (defaults.colorSpace == "GRAY"
            and defaults.grayMethod == "LUMA")
}

dlg:newrow { always = false }

dlg:combobox {
    id = "externalRef",
    label = "External:",
    option = defaults.externalRef,
    options = externalRefs,
    focus = false,
    visible = defaults.colorSpace == "LAB"
        or defaults.colorSpace == "CMYK"
}

dlg:newrow { always = false }

dlg:check {
    id = "preserveIndices",
    label = "Act:",
    text = "All 256",
    selected = defaults.preserveIndices
}

dlg:separator { id = "importSep" }

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
        local args <const> = dlg.data
        local importFilepath <const> = args.importFilepath --[[@as string]]

        if (not importFilepath) or (#importFilepath < 1)
            or (not app.fs.isFile(importFilepath)) then
            app.alert {
                title = "Error",
                text = "Invalid file path."
            }
            return
        end

        local fileExt <const> = string.lower(app.fs.fileExtension(importFilepath))
        if fileExt ~= "ase" and fileExt ~= "aco" and fileExt ~= "act" then
            app.alert {
                title = "Error",
                text = "File format must be ase, aco or act."
            }
            return
        end

        local binFile <const>, err <const> = io.open(importFilepath, "rb")
        if err ~= nil then
            if binFile then binFile:close() end
            app.alert { title = "Error", text = err }
            return
        end
        if binFile == nil then return end

        -- As a precaution against crashes, do not allow slices UI interface
        -- to be active.
        local appTool <const> = app.tool
        if appTool then
            local toolName <const> = appTool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        -- Preserve fore- and background colors.
        local fgc <const> = app.fgColor
        app.fgColor = Color {
            r = fgc.red,
            g = fgc.green,
            b = fgc.blue,
            a = fgc.alpha
        }

        app.command.SwitchColors()
        local bgc <const> = app.fgColor
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
        local fileData <const> = binFile:read("a")
        binFile:close()
        local asefHeader <const> = string.sub(fileData, 1, 4)
        local isAsef <const> = asefHeader == "ASEF"
        -- print(strfmt("asefHeader: 0x%08x", asefHeader))
        -- print(isAsef)

        if (not isAsef) and fileExt == "ase" then
            -- https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md#header
            local asepriteHeader <const> = string.unpack("I2", string.sub(fileData, 5, 6))
            -- print(strfmt("asepriteHeader: %04x", asepriteHeader))

            if asepriteHeader == 0xa5e0 then
                if #app.sprites <= 0 then
                    Sprite { fromFile = importFilepath }
                else
                    local activeSprite <const> = app.sprite
                    if activeSprite then
                        local palette <const> = Palette { fromFile = importFilepath }
                        if palette then
                            local oldColorMode <const> = activeSprite.colorMode
                            if oldColorMode == ColorMode.INDEXED then
                                app.command.ChangePixelFormat { format = "rgb" }
                            end
                            activeSprite:setPalette(palette)
                            if oldColorMode == ColorMode.INDEXED then
                                app.command.ChangePixelFormat { format = "indexed" }
                                -- Could set transparent color index... but
                                -- you'd have to open the file as a sprite,
                                -- then get the index and palette, then close
                                -- the sprite.
                            end
                        end
                    end
                end
                return
            end

            app.alert { title = "Error", text = "ASEF header not found." }
            return
        end

        -- Handle different color spaces.
        local colorSpace <const> = args.colorSpace
            or defaults.colorSpace --[[@as string]]
        local externalRef <const> = args.externalRef
            or defaults.externalRef --[[@as string]]

        -- For ACT files generated by the mGBA emulator, it may be important
        -- to preserve index order.
        local preserveIndices <const> = args.preserveIndices
            or defaults.preserveIndices --[[@as boolean]]

        ---@type Color[]s
        local aseColors = {}
        if fileExt == "aco" then
            aseColors = readAco(fileData, colorSpace, externalRef)
        elseif fileExt == "act" then
            aseColors = readAct(fileData, preserveIndices)
        else
            aseColors = readAse(fileData, colorSpace, externalRef)
        end

        local activeSprite = app.sprite
        if not activeSprite then
            local lenColors <const> = #aseColors
            local rtLen <const> = math.max(8,
                math.ceil(math.sqrt(math.max(1, lenColors))))

            local spec <const> = ImageSpec {
                width = rtLen,
                height = rtLen,
                colorMode = ColorMode.RGB,
                transparentColor = 0
            }
            spec.colorSpace = ColorSpace { sRGB = true }

            local image <const> = Image(spec)
            local pxItr <const> = image:pixels()
            local index = 0
            for pixel in pxItr do
                if index < lenColors then
                    index = index + 1
                    local aseColor <const> = aseColors[index]
                    pixel(aseColor.rgbaPixel)
                end
            end

            activeSprite = Sprite(spec)
            activeSprite.filename = app.fs.fileName(importFilepath)
            activeSprite.cels[1].image = image
        end

        local oldColorMode <const> = activeSprite.colorMode
        if oldColorMode == ColorMode.INDEXED then
            app.command.ChangePixelFormat { format = "rgb" }
        end

        local activeFrame <const> = app.frame or activeSprite.frames[1]
        local frIdx <const> = activeFrame.frameNumber

        -- In rare cases, e.g., a sprite opened from a sequence of indexed
        -- color mode files, there may be multiple palettes in the sprite.
        local paletteIdx = frIdx
        local palettes <const> = activeSprite.palettes
        local lenPalettes <const> = #palettes
        if paletteIdx > lenPalettes then paletteIdx = 1 end
        local palette <const> = palettes[paletteIdx]
        local lenAseColors <const> = #aseColors

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
    text = "E&XPORT",
    focus = false,
    onclick = function()
        local activeSprite <const> = app.sprite
        if not activeSprite then
            app.alert {
                title = "Error",
                text = "There is no active sprite."
            }
            return
        end

        -- Unpack arguments.
        local args <const> = dlg.data
        local exportFilepath <const> = args.exportFilepath --[[@as string]]
        local colorFormat <const> = args.colorFormat
            or defaults.colorFormat --[[@as string]]
        local colorSpace <const> = args.colorSpace
            or defaults.colorSpace --[[@as string]]
        local grayMethod <const> = args.grayMethod
            or defaults.grayMethod --[[@as string]]
        local externalRef <const> = args.externalRef
            or defaults.externalRef --[[@as string]]

        if (not exportFilepath) or (#exportFilepath < 1) then
            app.alert {
                title = "Error",
                text = "Invalid file path."
            }
            return
        end

        local fileExt <const> = string.lower(app.fs.fileExtension(exportFilepath))
        if fileExt ~= "ase" and fileExt ~= "aco" and fileExt ~= "act" then
            app.alert {
                title = "Error",
                text = "File format must be ase, aco or act."
            }
            return
        end

        local binFile <const>, err <const> = io.open(exportFilepath, "wb")
        if err ~= nil then
            if binFile then binFile:close() end
            app.alert { title = "Error", text = err }
            return
        end
        if binFile == nil then return end

        local appTool <const> = app.tool
        if appTool then
            local toolName <const> = appTool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        local activeFrame <const> = app.frame or activeSprite.frames[1]
        local frIdx <const> = activeFrame.frameNumber

        -- In rare cases, e.g., a sprite opened from a sequence of indexed
        -- color mode files, there may be multiple palettes in the sprite.
        local palettes <const> = activeSprite.palettes
        local paletteIdx = frIdx
        local lenPalettes <const> = #palettes
        if paletteIdx > lenPalettes then paletteIdx = 1 end
        local palette <const> = palettes[paletteIdx]

        local binStr = ""
        if fileExt == "aco" then
            binStr = writeAco(palette, colorFormat, colorSpace, grayMethod,
                externalRef)
        elseif fileExt == "act" then
            binStr = writeAct(palette)
        else
            binStr = writeAse(palette, colorFormat, colorSpace, grayMethod,
                externalRef)
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

dlg:show {
    autoscrollbars = true,
    wait = false
}