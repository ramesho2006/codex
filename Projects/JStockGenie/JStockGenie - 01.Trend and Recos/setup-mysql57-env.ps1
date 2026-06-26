Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$envPath = Join-Path $PSScriptRoot "MySQL57.env"

$created = [Collections.Generic.List[object]]::new()

Get-Content -LiteralPath $envPath | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }

    $parts = $line.Split("=", 2)
    if ($parts.Count -ne 2) { return }

    $name = $parts[0].Trim()
    $value = $parts[1].Trim()

    [Environment]::SetEnvironmentVariable($name, $value, "User")
    Set-Item -Path "Env:$name" -Value $value

    $displayValue = $value
    if ($name -match "PASS|PASSWORD|SECRET|TOKEN|KEY") {
        $displayValue = "SET_MASKED"
    }

    $created.Add([PSCustomObject]@{
        Name = $name
        UserValue = $displayValue
        CurrentSession = "Set"
    }) | Out-Null
}

Write-Host "Created MYSQL57_* user environment variables."
Write-Host "They are available in this PowerShell process and in newly opened terminals/apps."
Write-Host "Already-open parent terminals cannot be updated by a child .ps1 process; reopen them, or dot-source this script:"
Write-Host ". .\setup-mysql57-env.ps1"
$created | Format-Table -AutoSize
