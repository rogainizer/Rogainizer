param(
    [string]$Name = "rogainizer-prod",
    [string]$Region = "syd1",
    [string]$Size = "s-1vcpu-1gb",
    [string]$Image = "ubuntu-22-04-x64",
    [string]$Tags = "rogainizer",
    [string]$SshKeys = "",
    [string]$ProjectId = "",
    [string]$VpcUuid = "",
    [bool]$Backups = $false,
    [bool]$Ipv6 = $false,
    [bool]$Monitoring = $true,
    [string]$CloudInit,
    [string]$PasswordUser = "",
    [string]$PasswordPass = "",
    [bool]$WaitForIp = $true,
    [int]$WaitAttempts = 30,
    [int]$WaitSeconds = 5,
    [string]$ApiToken = $env:DO_API_TOKEN
)

$ErrorActionPreference = 'Stop'

function Split-CommaList {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return $Value.Split(',') |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

if ([string]::IsNullOrWhiteSpace($ApiToken)) {
    throw "DO_API_TOKEN is required (pass -ApiToken or set env:DO_API_TOKEN)."
}

$scriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($CloudInit)) {
    $CloudInit = Join-Path $scriptDir 'digitalocean-cloud-init-autodeploy.yaml'
}

if (-not (Test-Path -Path $CloudInit -PathType Leaf)) {
    throw "Cloud-init file not found: $CloudInit"
}

$cloudInitContent = Get-Content -Path $CloudInit -Raw

if (-not [string]::IsNullOrWhiteSpace($PasswordUser) -or -not [string]::IsNullOrWhiteSpace($PasswordPass)) {
    if ([string]::IsNullOrWhiteSpace($PasswordUser) -or [string]::IsNullOrWhiteSpace($PasswordPass)) {
        throw "Both -PasswordUser and -PasswordPass must be provided together."
    }

    if ($PasswordUser -match '[:\s]') {
        throw "-PasswordUser must not contain spaces or ':'"
    }

    if ($PasswordPass -match "`r|`n") {
        throw "-PasswordPass must not contain newlines"
    }

    $strippedCloudInit = $cloudInitContent -replace '(?m)^#cloud-config\s*\r?\n', ''
    $passwordCloudInitPrefix = @"
#cloud-config
ssh_pwauth: true
chpasswd:
  expire: false
  list: |
    $PasswordUser:$PasswordPass

"@

    $cloudInitContent = $passwordCloudInitPrefix + $strippedCloudInit
}
$tagsArray = Split-CommaList -Value $Tags
$sshKeysArray = Split-CommaList -Value $SshKeys

$payload = [ordered]@{
    name       = $Name
    region     = $Region
    size       = $Size
    image      = $Image
    user_data  = $cloudInitContent
    backups    = $Backups
    ipv6       = $Ipv6
    monitoring = $Monitoring
    tags       = $tagsArray
}

if ($sshKeysArray.Count -gt 0) {
    $payload.ssh_keys = $sshKeysArray
}

if (-not [string]::IsNullOrWhiteSpace($VpcUuid)) {
    $payload.vpc_uuid = $VpcUuid
}

$headers = @{
    Authorization = "Bearer $ApiToken"
    "Content-Type" = "application/json"
}

Write-Host "Creating droplet '$Name' in region '$Region'..."

$createResponse = Invoke-RestMethod -Method Post -Uri 'https://api.digitalocean.com/v2/droplets' -Headers $headers -Body ($payload | ConvertTo-Json -Depth 20)

if (-not $createResponse.droplet -or -not $createResponse.droplet.id) {
    throw "DigitalOcean API response did not include droplet id."
}

$dropletId = [int64]$createResponse.droplet.id
Write-Host "Droplet created. ID: $dropletId"

if (-not [string]::IsNullOrWhiteSpace($ProjectId)) {
    try {
        $projectBody = @{
            resources = @("do:droplet:$dropletId")
        }

        Invoke-RestMethod -Method Post -Uri "https://api.digitalocean.com/v2/projects/$ProjectId/resources" -Headers $headers -Body ($projectBody | ConvertTo-Json -Depth 5) | Out-Null
        Write-Host "Assigned droplet to project: $ProjectId"
    } catch {
        Write-Warning "Failed to assign droplet to project '$ProjectId': $($_.Exception.Message)"
    }
}

if ($WaitForIp) {
    Write-Host "Waiting for public IPv4 assignment..."

    $publicIp = $null
    for ($i = 0; $i -lt $WaitAttempts; $i++) {
        $details = Invoke-RestMethod -Method Get -Uri "https://api.digitalocean.com/v2/droplets/$dropletId" -Headers $headers
        $publicIp = $details.droplet.networks.v4 |
            Where-Object { $_.type -eq 'public' } |
            Select-Object -ExpandProperty ip_address -First 1

        if (-not [string]::IsNullOrWhiteSpace($publicIp)) {
            break
        }

        Start-Sleep -Seconds $WaitSeconds
    }

    if (-not [string]::IsNullOrWhiteSpace($publicIp)) {
        Write-Host "Public IPv4: $publicIp"
    } else {
        Write-Warning "Public IPv4 not available yet. Check DigitalOcean control panel for droplet ID $dropletId."
    }
}

Write-Host 'Done.'
