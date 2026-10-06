function Read-UInt16 {
    param([byte[]] $Bytes, [int] $Offset)

    if ($Offset -lt 0 -or $Offset + 2 -gt $Bytes.Length) {
        throw "Invalid PE offset: $Offset"
    }
    [BitConverter]::ToUInt16($Bytes, $Offset)
}

function Read-UInt32 {
    param([byte[]] $Bytes, [int] $Offset)

    if ($Offset -lt 0 -or $Offset + 4 -gt $Bytes.Length) {
        throw "Invalid PE offset: $Offset"
    }
    [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Convert-RvaToOffset {
    param(
        [UInt32] $Rva,
        [object[]] $Sections,
        [int] $FileLength
    )

    foreach ($section in $Sections) {
        $sectionSize = [Math]::Max($section.VirtualSize, $section.RawSize)
        if ($Rva -ge $section.VirtualAddress -and
            $Rva -lt $section.VirtualAddress + $sectionSize) {
            $offset = [int]($section.RawOffset + $Rva - $section.VirtualAddress)
            if ($offset -lt 0 -or $offset -ge $FileLength) {
                break
            }
            return $offset
        }
    }
    throw ('PE RVA 0x{0:X8} does not map to file data' -f $Rva)
}

function Read-AsciiString {
    param([byte[]] $Bytes, [int] $Offset)

    $end = $Offset
    while ($end -lt $Bytes.Length -and $Bytes[$end] -ne 0) {
        $end++
    }
    if ($end -eq $Bytes.Length) {
        throw "Unterminated PE string at offset $Offset"
    }
    [Text.Encoding]::ASCII.GetString($Bytes, $Offset, $end - $Offset)
}

function Get-PeExports {
    param([string] $Path, [UInt16] $Machine)

    [byte[]] $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw "Not a PE file: $Path"
    }

    $peOffset = [int](Read-UInt32 $bytes 0x3C)
    if ((Read-UInt32 $bytes $peOffset) -ne 0x00004550) {
        throw "Invalid PE signature: $Path"
    }

    $fileHeader = $peOffset + 4
    $actualMachine = Read-UInt16 $bytes $fileHeader
    if ($actualMachine -ne $Machine) {
        throw ('Unexpected PE machine for {0}: 0x{1:X4}' -f $Path, $actualMachine)
    }

    $sectionCount = Read-UInt16 $bytes ($fileHeader + 2)
    $optionalHeaderSize = Read-UInt16 $bytes ($fileHeader + 16)
    $optionalHeader = $fileHeader + 20
    $optionalMagic = Read-UInt16 $bytes $optionalHeader
    $dataDirectoryOffset = switch ($optionalMagic) {
        0x010B { 96 }
        0x020B { 112 }
        default { throw ('Unexpected optional-header magic: 0x{0:X4}' -f $optionalMagic) }
    }
    $exportRva = Read-UInt32 $bytes ($optionalHeader + $dataDirectoryOffset)
    if ($exportRva -eq 0) {
        throw "PE file has no export table: $Path"
    }

    $sections = for ($index = 0; $index -lt $sectionCount; $index++) {
        $sectionOffset = $optionalHeader + $optionalHeaderSize + 40 * $index
        [pscustomobject]@{
            VirtualSize = Read-UInt32 $bytes ($sectionOffset + 8)
            VirtualAddress = Read-UInt32 $bytes ($sectionOffset + 12)
            RawSize = Read-UInt32 $bytes ($sectionOffset + 16)
            RawOffset = Read-UInt32 $bytes ($sectionOffset + 20)
        }
    }

    $exportOffset = Convert-RvaToOffset $exportRva $sections $bytes.Length
    $ordinalBase = Read-UInt32 $bytes ($exportOffset + 16)
    $functionCount = Read-UInt32 $bytes ($exportOffset + 20)
    $nameCount = Read-UInt32 $bytes ($exportOffset + 24)
    $functionTable = Convert-RvaToOffset (
        Read-UInt32 $bytes ($exportOffset + 28)
    ) $sections $bytes.Length
    $nameTable = Convert-RvaToOffset (
        Read-UInt32 $bytes ($exportOffset + 32)
    ) $sections $bytes.Length
    $nameOrdinalTable = Convert-RvaToOffset (
        Read-UInt32 $bytes ($exportOffset + 36)
    ) $sections $bytes.Length

    $names = @{}
    for ($index = 0; $index -lt $nameCount; $index++) {
        $nameRva = Read-UInt32 $bytes ($nameTable + 4 * $index)
        $nameOffset = Convert-RvaToOffset $nameRva $sections $bytes.Length
        $functionIndex = Read-UInt16 $bytes ($nameOrdinalTable + 2 * $index)
        if ($functionIndex -ge $functionCount) {
            throw "Invalid export name ordinal in $Path"
        }
        $ordinal = [UInt32]($ordinalBase + $functionIndex)
        if ($names.ContainsKey($ordinal)) {
            throw "Multiple export names for ordinal $ordinal in $Path"
        }
        $names[$ordinal] = Read-AsciiString $bytes $nameOffset
    }

    $exports = @{}
    for ($index = 0; $index -lt $functionCount; $index++) {
        Read-UInt32 $bytes ($functionTable + 4 * $index) | Out-Null
        $ordinal = [UInt32]($ordinalBase + $index)
        $exports[$ordinal] = if ($names.ContainsKey($ordinal)) { $names[$ordinal] } else { $null }
    }
    $exports
}
