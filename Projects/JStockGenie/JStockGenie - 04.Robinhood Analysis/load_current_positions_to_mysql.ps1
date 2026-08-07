param(
    [string]$SourceCsv = "O:\DB001A-MYFILES\01.Personal\India Investments\My Investment Positions.csv",
    [string]$AnalysisCsv = "O:\DB001A-MYFILES\01.Personal\India Investments\My Investment Positions Analysis 2026_07_19.csv",
    [string]$MysqlEnvFolder = "D:\Codex\Projects\JStockGenie\JStockGenie - 01.Trend and Recos"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sourcePath = Join-Path $MysqlEnvFolder "inspect-mysql57-schema.ps1"
$source = Get-Content -LiteralPath $sourcePath -Raw
$prefix = $source.Substring(0, $source.IndexOf('$envValues ='))
Invoke-Expression $prefix

function Invoke-MySqlAny($Stream, [string]$Sql) {
    $query = [Collections.Generic.List[byte]]::new()
    $query.Add([byte]3) | Out-Null
    Add-Bytes $query ([Text.Encoding]::UTF8.GetBytes($Sql))
    Write-Packet $Stream ([byte[]]$query.ToArray()) 0

    $first = Read-Packet $Stream
    $firstPayload = [byte[]]$first.Payload
    if ($firstPayload[0] -eq 0xff) { throw (Get-ErrorMessage $firstPayload) }

    # OK packet for CREATE/DELETE/INSERT/UPDATE.
    if ($firstPayload[0] -eq 0x00 -or ($firstPayload[0] -eq 0xfe -and $firstPayload.Length -lt 9)) {
        return @()
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

function New-JStockMySqlConnection {
    $envValues = Read-DotEnv (Join-Path $MysqlEnvFolder "MYSQL57.env")
    $client = [Net.Sockets.TcpClient]::new()
    $client.Connect($envValues["MYSQL57_HOST"], [int]$envValues["MYSQL57_PORT"])
    $stream = $client.GetStream()

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

    return @{ Client = $client; Stream = $stream }
}

function Escape-SqlString {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "NULL" }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text) -or $text.Trim().ToUpperInvariant() -eq "NA") { return "NULL" }
    return "'" + ($text.Replace("\", "\\").Replace("'", "''")) + "'"
}

function Convert-MoneyText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "NULL" }
    $text = ([string]$Value).Trim().Replace("$", "").Replace(",", "")
    if ([string]::IsNullOrWhiteSpace($text) -or $text.ToUpperInvariant() -eq "NA") { return "NULL" }
    return [string]([decimal]$text)
}

function Convert-DateText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "NULL" }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text) -or $text.ToUpperInvariant() -eq "NA") { return "NULL" }
    $dt = [datetime]::Parse($text, [Globalization.CultureInfo]::InvariantCulture)
    return "'" + $dt.ToString("yyyy-MM-dd") + "'"
}

function Convert-DecimalText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "NULL" }
    $text = ([string]$Value).Trim().Replace(",", "")
    if ([string]::IsNullOrWhiteSpace($text) -or $text.ToUpperInvariant() -eq "NA") { return "NULL" }
    return [string]([decimal]$text)
}

$sourceRows = Import-Csv -LiteralPath $SourceCsv
$analysisRows = Import-Csv -LiteralPath $AnalysisCsv

$analysisByKey = @{}
foreach ($row in $analysisRows) {
    $key = "$($row.Broker)|$($row.Segment)|$($row.Scrip)"
    $analysisByKey[$key] = $row
}

$lastPriceColumn = ($sourceRows[0].PSObject.Properties.Name | Where-Object { $_.Trim() -eq "Last Price" } | Select-Object -First 1)
$avgCostColumn = ($sourceRows[0].PSObject.Properties.Name | Where-Object { $_.Trim() -eq "Ag Cost" } | Select-Object -First 1)
$strikeColumn = ($sourceRows[0].PSObject.Properties.Name | Where-Object { $_.Trim() -eq "Strike" } | Select-Object -First 1)
$expColumn = ($sourceRows[0].PSObject.Properties.Name | Where-Object { $_.Trim() -eq "Exp" } | Select-Object -First 1)

$createSql = @"
CREATE TABLE IF NOT EXISTS jstockdata_current_positions (
  broker VARCHAR(50) NOT NULL,
  account_name VARCHAR(120) NOT NULL,
  scrip VARCHAR(20) NOT NULL,
  segment VARCHAR(20) NOT NULL,
  trade_action VARCHAR(40) NULL,
  qty DECIMAL(18,6) NULL,
  last_price DECIMAL(18,4) NULL,
  avg_cost DECIMAL(18,4) NULL,
  strike DECIMAL(18,4) NULL,
  exp_date DATE NULL,
  reco_action VARCHAR(80) NULL,
  quant_score DECIMAL(10,4) NULL,
  loaded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  analysis_date DATE NULL,
  KEY ix_current_positions_broker_segment_scrip (broker, segment, scrip),
  KEY ix_current_positions_analysis_date (analysis_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8
"@

$values = foreach ($row in $sourceRows) {
    $broker = $row.Broker
    $segment = $row.Segment
    $scrip = $row.Scrip
    $key = "$broker|$segment|$scrip"
    $analysis = $analysisByKey[$key]
    $analysisDate = if ($analysis) { Convert-DateText $analysis.'Analysis Date' } else { "NULL" }
    $recoAction = if ($analysis) { Escape-SqlString $analysis.'Buy/Sell/Hold' } else { "NULL" }

    "(" + (@(
        (Escape-SqlString $broker),
        (Escape-SqlString $row.Account),
        (Escape-SqlString $scrip),
        (Escape-SqlString $segment),
        (Escape-SqlString $row.Trade),
        (Convert-DecimalText $row.Qty),
        (Convert-MoneyText $row.$lastPriceColumn),
        (Convert-MoneyText $row.$avgCostColumn),
        (Convert-MoneyText $row.$strikeColumn),
        (Convert-DateText $row.$expColumn),
        $recoAction,
        "NULL",
        $analysisDate
    ) -join ", ") + ")"
}

$conn = New-JStockMySqlConnection
try {
    Invoke-MySqlAny $conn.Stream $createSql | Out-Null
    Invoke-MySqlAny $conn.Stream "DELETE FROM jstockdata_current_positions" | Out-Null

    if ($values.Count -gt 0) {
        $insertSql = @"
INSERT INTO jstockdata_current_positions
  (broker, account_name, scrip, segment, trade_action, qty, last_price, avg_cost, strike, exp_date, reco_action, quant_score, analysis_date)
VALUES
$($values -join ",`n")
"@
        Invoke-MySqlAny $conn.Stream $insertSql | Out-Null
    }

    Invoke-MySqlAny $conn.Stream "SELECT COUNT(*) AS loaded_rows, MIN(analysis_date) AS min_analysis_date, MAX(analysis_date) AS max_analysis_date FROM jstockdata_current_positions" | Format-Table -AutoSize
    Invoke-MySqlAny $conn.Stream "SELECT broker, segment, reco_action, COUNT(*) AS position_count FROM jstockdata_current_positions GROUP BY broker, segment, reco_action ORDER BY broker, segment, reco_action" | Format-Table -AutoSize
}
finally {
    $conn.Stream.Dispose()
    $conn.Client.Dispose()
}
