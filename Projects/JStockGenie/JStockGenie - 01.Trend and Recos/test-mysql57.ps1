Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-DotEnv($Path) {
    $values = @{}
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $parts = $line.Split("=", 2)
        if ($parts.Count -eq 2) {
            $values[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
    return $values
}

function Get-NullTerminatedString([byte[]]$Bytes, [int]$Offset) {
    $end = $Offset
    while ($end -lt $Bytes.Length -and $Bytes[$end] -ne 0) { $end++ }
    return @{
        Value = [Text.Encoding]::ASCII.GetString($Bytes, $Offset, $end - $Offset)
        Next = $end + 1
    }
}

function Read-Exact($Stream, [int]$Length) {
    $buffer = New-Object byte[] $Length
    $offset = 0
    while ($offset -lt $Length) {
        $read = $Stream.Read($buffer, $offset, $Length - $offset)
        if ($read -le 0) { throw "Connection closed while reading from MySQL server." }
        $offset += $read
    }
    return $buffer
}

function Read-Packet($Stream) {
    $header = Read-Exact $Stream 4
    $length = [int]$header[0] -bor ([int]$header[1] -shl 8) -bor ([int]$header[2] -shl 16)
    return @{
        Sequence = $header[3]
        Payload = Read-Exact $Stream $length
    }
}

function Write-Packet($Stream, [byte[]]$Payload, [int]$Sequence) {
    $length = $Payload.Length
    $packet = New-Object byte[] ($length + 4)
    $packet[0] = [byte]($length -band 0xff)
    $packet[1] = [byte](($length -shr 8) -band 0xff)
    $packet[2] = [byte](($length -shr 16) -band 0xff)
    $packet[3] = [byte]$Sequence
    [Array]::Copy($Payload, 0, $packet, 4, $length)
    $Stream.Write($packet, 0, $packet.Length)
}

function Add-UInt32LE($List, [uint32]$Value) {
    $List.Add([byte]($Value -band 0xff)) | Out-Null
    $List.Add([byte](($Value -shr 8) -band 0xff)) | Out-Null
    $List.Add([byte](($Value -shr 16) -band 0xff)) | Out-Null
    $List.Add([byte](($Value -shr 24) -band 0xff)) | Out-Null
}

function Add-Bytes($List, [byte[]]$Bytes) {
    foreach ($byte in $Bytes) { $List.Add($byte) | Out-Null }
}

function Get-Sha1([byte[]]$Bytes) {
    $sha1 = [Security.Cryptography.SHA1]::Create()
    try {
        return $sha1.ComputeHash($Bytes)
    }
    finally {
        $sha1.Dispose()
    }
}

function Get-NativePasswordToken([string]$Password, [byte[]]$Seed) {
    $passwordBytes = [Text.Encoding]::UTF8.GetBytes($Password)
    $stage1 = Get-Sha1 $passwordBytes
    $stage2 = Get-Sha1 $stage1
    $combined = New-Object byte[] ($Seed.Length + $stage2.Length)
    [Array]::Copy($Seed, 0, $combined, 0, $Seed.Length)
    [Array]::Copy($stage2, 0, $combined, $Seed.Length, $stage2.Length)
    $stage3 = Get-Sha1 $combined
    $token = New-Object byte[] $stage3.Length
    for ($i = 0; $i -lt $stage3.Length; $i++) {
        $token[$i] = [byte]($stage1[$i] -bxor $stage3[$i])
    }
    return $token
}

function Get-ErrorMessage([byte[]]$Payload) {
    if ($Payload.Length -lt 3) { return "Unknown MySQL error." }
    $code = [int]$Payload[1] -bor ([int]$Payload[2] -shl 8)
    $messageStart = 3
    if ($Payload.Length -gt 9 -and $Payload[3] -eq [byte][char]"#") { $messageStart = 9 }
    $message = [Text.Encoding]::UTF8.GetString($Payload, $messageStart, $Payload.Length - $messageStart)
    return "MySQL error ${code}: $message"
}

$envPath = Join-Path $PSScriptRoot "MYSQL57.env"
$envValues = Read-DotEnv $envPath

$hostName = $envValues["MYSQL57_HOST"]
$port = [int]$envValues["MYSQL57_PORT"]
$database = $envValues["MYSQL57_DBNAME"]
$user = $envValues["MYSQL57_DBUSER"]
$password = $envValues["MYSQL57_DBPASS"]

$client = [Net.Sockets.TcpClient]::new()
$client.Connect($hostName, $port)
$stream = $client.GetStream()

try {
    $handshake = Read-Packet $stream
    $payload = [byte[]]$handshake.Payload
    if ($payload[0] -eq 0xff) { throw (Get-ErrorMessage $payload) }

    $serverVersion = Get-NullTerminatedString $payload 1
    $pos = $serverVersion.Next + 4
    $seed1 = $payload[$pos..($pos + 7)]
    $pos += 9
    $lowerCaps = [uint32]$payload[$pos] -bor ([uint32]$payload[$pos + 1] -shl 8)
    $pos += 2
    $charset = $payload[$pos]
    $pos += 1 + 2
    $upperCaps = [uint32]$payload[$pos] -bor ([uint32]$payload[$pos + 1] -shl 8)
    $capabilities = $lowerCaps -bor ($upperCaps -shl 16)
    $pos += 2
    $authPluginLength = $payload[$pos]
    $pos += 1 + 10
    $seed2Length = [Math]::Max(13, $authPluginLength - 8)
    $seed2End = [Math]::Min($payload.Length - 1, $pos + $seed2Length - 1)
    $seed2 = $payload[$pos..$seed2End] | Where-Object { $_ -ne 0 }
    $seed = @($seed1) + @($seed2)

    $nullString = Get-NullTerminatedString $payload ($seed2End + 1)
    $plugin = $nullString.Value
    if ($plugin -eq "") { $plugin = "mysql_native_password" }
    if ($plugin -ne "mysql_native_password") {
        throw "Server requested unsupported auth plugin: $plugin"
    }

    $clientLongPassword = 0x00000001
    $clientLongFlag = 0x00000004
    $clientConnectWithDb = 0x00000008
    $clientProtocol41 = 0x00000200
    $clientTransactions = 0x00002000
    $clientSecureConnection = 0x00008000
    $clientMultiResults = 0x00020000
    $clientPluginAuth = 0x00080000
    $clientCaps = [uint32]($clientLongPassword -bor $clientLongFlag -bor $clientConnectWithDb -bor $clientProtocol41 -bor $clientTransactions -bor $clientSecureConnection -bor $clientMultiResults -bor $clientPluginAuth)

    $response = [Collections.Generic.List[byte]]::new()
    Add-UInt32LE $response $clientCaps
    Add-UInt32LE $response 16777216
    $response.Add([byte]$charset) | Out-Null
    1..23 | ForEach-Object { $response.Add([byte]0) | Out-Null }
    Add-Bytes $response ([Text.Encoding]::UTF8.GetBytes($user))
    $response.Add([byte]0) | Out-Null
    $token = Get-NativePasswordToken $password ([byte[]]$seed)
    $response.Add([byte]$token.Length) | Out-Null
    Add-Bytes $response $token
    Add-Bytes $response ([Text.Encoding]::UTF8.GetBytes($database))
    $response.Add([byte]0) | Out-Null
    Add-Bytes $response ([Text.Encoding]::ASCII.GetBytes("mysql_native_password"))
    $response.Add([byte]0) | Out-Null

    Write-Packet $stream ([byte[]]$response.ToArray()) 1
    $auth = Read-Packet $stream
    $authPayload = [byte[]]$auth.Payload
    if ($authPayload[0] -eq 0xff) { throw (Get-ErrorMessage $authPayload) }
    if ($authPayload[0] -ne 0x00) { throw "Unexpected authentication response packet: 0x$($authPayload[0].ToString('x2'))" }

    $query = [Collections.Generic.List[byte]]::new()
    $query.Add([byte]3) | Out-Null
    Add-Bytes $query ([Text.Encoding]::UTF8.GetBytes("SELECT DATABASE(), VERSION()"))
    Write-Packet $stream ([byte[]]$query.ToArray()) 0
    $first = Read-Packet $stream
    $firstPayload = [byte[]]$first.Payload
    if ($firstPayload[0] -eq 0xff) { throw (Get-ErrorMessage $firstPayload) }

    [PSCustomObject]@{
        TcpConnected = $true
        Authenticated = $true
        ServerVersion = $serverVersion.Value
        Database = $database
        QueryAccepted = $true
    } | Format-List
}
finally {
    $stream.Dispose()
    $client.Dispose()
}
