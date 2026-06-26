param(
    [Parameter(Mandatory=$true)]
    [string]$Sql
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = "D:\CodexNew\JStockGenie\JStockGenie - 01.ETL, Trend, Backtest, Recos"
$sourcePath = Join-Path $repoRoot "inspect-mysql57-schema.ps1"
$source = Get-Content -LiteralPath $sourcePath -Raw
$prefix = $source.Substring(0, $source.IndexOf('$envValues ='))
Invoke-Expression $prefix

$envValues = Read-DotEnv (Join-Path $repoRoot "MYSQL57.env")
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

    Invoke-MySqlQuery $stream $Sql | ConvertTo-Json -Depth 6
}
finally {
    $stream.Dispose()
    $client.Dispose()
}
