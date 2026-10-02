# Run on Windows with PowerShell 7 and a WinDivert 2.2 x64 DLL, for example:
# pwsh -File tests/quic_filter.ps1 -WinDivertDll path/to/x86_64/WinDivert.dll
param(
    [Parameter(Mandatory = $true)]
    [string] $WinDivertDll,
    [string] $SourcePath = (Join-Path $PSScriptRoot '..\src\goodbyedpi.c')
)

$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $SourcePath -Raw
$macro = [regex]::Match($source, '(?ms)^#define FILTER_PASSIVE_BLOCK_QUIC\s+(.+?)(?=^#define )').Groups[1].Value
if (-not $macro) { throw 'QUIC filter macro was not found' }
$filter = ([regex]::Matches($macro, '"([^"\r\n]*)"') | ForEach-Object { $_.Groups[1].Value }) -join ''
$dllPath = (Resolve-Path -LiteralPath $WinDivertDll).Path
$nativeCode = @'
using System;
using System.Runtime.InteropServices;
public static class WinDivertFilterTest {
    [DllImport(@"__DLL__", CharSet = CharSet.Ansi, CallingConvention = CallingConvention.Winapi)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool WinDivertHelperCompileFilter(string filter, int layer, IntPtr obj, uint objLen, out IntPtr errorStr, out uint errorPos);

    [DllImport(@"__DLL__", CharSet = CharSet.Ansi, CallingConvention = CallingConvention.Winapi, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool WinDivertHelperEvalFilter(string filter, byte[] packet, uint packetLen, byte[] addr);
}
'@.Replace('__DLL__', $dllPath)
Add-Type -TypeDefinition $nativeCode

$errorStr = [IntPtr]::Zero
$errorPos = [uint32]0
if (-not [WinDivertFilterTest]::WinDivertHelperCompileFilter($filter, 0, [IntPtr]::Zero, 0, [ref]$errorStr, [ref]$errorPos)) {
    $message = [Runtime.InteropServices.Marshal]::PtrToStringAnsi($errorStr)
    throw "Invalid WinDivert filter at offset ${errorPos}: $message"
}

function New-UdpPacket([byte] $firstByte, [uint32] $version, [int] $payloadLength = 1200, [int] $dstPort = 443) {
    $packet = [byte[]]::new(20 + 8 + $payloadLength)
    $packet[0] = 0x45
    $packet[2] = [byte]($packet.Length -shr 8)
    $packet[3] = [byte]($packet.Length -band 0xff)
    $packet[8] = 64
    $packet[9] = 17
    [Array]::Copy([byte[]](198, 51, 100, 2), 0, $packet, 12, 4)
    [Array]::Copy([byte[]](203, 0, 113, 1), 0, $packet, 16, 4)
    [Array]::Copy([byte[]](0xd9, 0x03), 0, $packet, 20, 2)
    $packet[22] = [byte]($dstPort -shr 8)
    $packet[23] = [byte]($dstPort -band 0xff)
    $udpLength = 8 + $payloadLength
    $packet[24] = [byte]($udpLength -shr 8)
    $packet[25] = [byte]($udpLength -band 0xff)
    $packet[28] = $firstByte
    $packet[29] = [byte]($version -shr 24)
    $packet[30] = [byte](($version -shr 16) -band 0xff)
    $packet[31] = [byte](($version -shr 8) -band 0xff)
    $packet[32] = [byte]($version -band 0xff)
    return ,$packet
}

$outbound = [byte[]]::new(80)
[BitConverter]::GetBytes([uint64](1 -shl 17)).CopyTo($outbound, 8)
$inbound = [byte[]]::new(80)

$cases = @(
    @{ Name = 'QUIC v1 Initial'; Packet = (New-UdpPacket 0xc0 0x00000001); Address = $outbound; Expected = $true },
    @{ Name = 'QUIC v2 Initial'; Packet = (New-UdpPacket 0xd7 0x6b3343cf); Address = $outbound; Expected = $true },
    @{ Name = 'QUIC v1 Handshake'; Packet = (New-UdpPacket 0xe0 0x00000001); Address = $outbound; Expected = $false },
    @{ Name = 'QUIC v2 Handshake'; Packet = (New-UdpPacket 0xf0 0x6b3343cf); Address = $outbound; Expected = $false },
    @{ Name = 'Other UDP on port 443'; Packet = (New-UdpPacket 0xd7 0x00000002); Address = $outbound; Expected = $false },
    @{ Name = 'QUIC v2 on another port'; Packet = (New-UdpPacket 0xd7 0x6b3343cf 1200 8443); Address = $outbound; Expected = $false },
    @{ Name = 'Short UDP datagram'; Packet = (New-UdpPacket 0xd7 0x6b3343cf 1199); Address = $outbound; Expected = $false },
    @{ Name = 'Inbound QUIC v2'; Packet = (New-UdpPacket 0xd7 0x6b3343cf); Address = $inbound; Expected = $false }
)

foreach ($case in $cases) {
    $actual = [WinDivertFilterTest]::WinDivertHelperEvalFilter($filter, $case.Packet, $case.Packet.Length, $case.Address)
    if ($actual -ne $case.Expected) {
        throw "$($case.Name): expected $($case.Expected), got $actual (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    }
    Write-Output "PASS $($case.Name)"
}
