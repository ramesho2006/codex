param(
    [Parameter(Mandatory = $true)]
    [string]$Sql,
    [string]$MysqlEnvFolder = "D:\Codex\Projects\JStockGenie\JStockGenie - 01.Trend and Recos",
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sourcePath = Join-Path $MysqlEnvFolder "inspect-mysql57-schema.ps1"
$source = Get-Content -LiteralPath $sourcePath -Raw
$prefix = $source.Substring(0, $source.IndexOf('$envValues ='))
Invoke-Expression $prefix

function Invoke-MySqlAny($Stream, [string]$SqlText) {
    $query = [Collections.Generic.List[byte]]::new()
    $query.Add([byte]3) | Out-Null
    Add-Bytes $query ([Text.Encoding]::UTF8.GetBytes($SqlText))
    Write-Packet $Stream ([byte[]]$query.ToArray()) 0

    $first = Read-Packet $Stream
    $firstPayload = [byte[]]$first.Payload
    if ($firstPayload[0] -eq 0xff) { throw (Get-ErrorMessage $firstPayload) }

    if ($firstPayload[0] -eq 0x00 -or ($firstPayload[0] -eq 0xfe -and $firstPayload.Length -lt 9)) {
        return @([PSCustomObject]@{ status = "OK" })
    }

    $offset = [ref]0
    $columnCount = [int](Read-LenEncInt $firstPayload $offset)
    $columns = @()
    for ($i = 0; $i -lt $columnCount; $i++) {
        $packet = Read-Packet $Stream
        $payload = [byte[]]$packet.Payload
        $pos = [ref]0
        1..4 | ForEach-Object { [void](Read-LenEncString $payload $pos) }
        $columns += Read-LenEncString $payload $pos
    }

    [void](Read-Packet $Stream)

    $rows = @()
    while ($true) {
        $packet = Read-Packet $Stream
        $payload = [byte[]]$packet.Payload
        if (Test-EofPacket $payload) { break }
        if ($payload[0] -eq 0xff) { throw (Get-ErrorMessage $payload) }
        $pos = [ref]0
        $row = [ordered]@{}
        foreach ($column in $columns) { $row[$column] = Read-LenEncString $payload $pos }
        $rows += [PSCustomObject]$row
    }
    return $rows
}

$envValues = Read-DotEnv (Join-Path $MysqlEnvFolder "MYSQL57.env")
$client = [Net.Sockets.TcpClient]::new()
$client.Connect($envValues["MYSQL57_HOST"], [int]$envValues["MYSQL57_PORT"])
$stream = $client.GetStream()

try {
    $handshake = Read-Packet $stream
    $payload = [byte[]]$handshake.Payload
    if ($payload[0] -eq 0xff) { throw (Get-ErrorMessage $payload) }

    $serverVersion = Get-NullTerminatedString $payload 1
    $pos = $serverVersion.Next + 4
    $seed1 = $payload[$pos..($pos + 7)]
    $pos += 9
    $pos += 2
    $charset = $payload[$pos]
    $pos += 1 + 2
    $pos += 2
    $authPluginLength = $payload[$pos]
    $pos += 1 + 10
    $seed2Length = [Math]::Max(13, $authPluginLength - 8)
    $seed2End = [Math]::Min($payload.Length - 1, $pos + $seed2Length - 1)
    $seed2 = $payload[$pos..$seed2End] | Where-Object { $_ -ne 0 }
    $seed = @($seed1) + @($seed2)

    $clientCaps = [uint32](0x00000001 -bor 0x00000004 -bor 0x00000008 -bor 0x00000200 -bor 0x00002000 -bor 0x00008000 -bor 0x00020000 -bor 0x00080000)
    $response = [Collections.Generic.List[byte]]::new()
    Add-UInt32LE $response $clientCaps
    Add-UInt32LE $response 16777216
    $response.Add([byte]$charset) | Out-Null
    1..23 | ForEach-Object { $response.Add([byte]0) | Out-Null }
    Add-Bytes $response ([Text.Encoding]::UTF8.GetBytes($envValues["MYSQL57_DBUSER"]))
    $response.Add([byte]0) | Out-Null
    $token = Get-NativePasswordToken $envValues["MYSQL57_DBPASS"] ([byte[]]$seed)
    $response.Add([byte]$token.Length) | Out-Null
    Add-Bytes $response $token
    Add-Bytes $response ([Text.Encoding]::UTF8.GetBytes($envValues["MYSQL57_DBNAME"]))
    $response.Add([byte]0) | Out-Null
    Add-Bytes $response ([Text.Encoding]::ASCII.GetBytes("mysql_native_password"))
    $response.Add([byte]0) | Out-Null

    Write-Packet $stream ([byte[]]$response.ToArray()) 1
    $auth = Read-Packet $stream
    $authPayload = [byte[]]$auth.Payload
    if ($authPayload[0] -eq 0xff) { throw (Get-ErrorMessage $authPayload) }

    $result = Invoke-MySqlAny $stream $Sql
    if ($Json) {
        $result | ConvertTo-Json -Depth 8
    } else {
        $result | Format-Table -AutoSize
    }
}
finally {
    $stream.Dispose()
    $client.Dispose()
}
