<#[
.SYNOPSIS
  Creates a production database backup on the droplet and downloads it locally.
.DESCRIPTION
  This script connects to the production droplet over SSH, runs the existing
  deploy/backup-db.sh script there, captures the remote backup path that script
  prints, and downloads the resulting .sql.gz file to the local machine via SCP.

  It relies on the production server already having a working .env.production
  and docker-compose.prod.yml setup.
.PARAMETER DropletIp
  IP or hostname of the production droplet.
.PARAMETER DropletUser
  SSH user for the droplet.
.PARAMETER IdentityFile
  Optional SSH private key passed to ssh/scp via -i.
.PARAMETER RemoteAppDir
  Absolute path to the app directory on the droplet.
.PARAMETER LocalDirectory
  Local directory where the downloaded backup will be stored.
.PARAMETER KeepRemoteFile
  If set, leave the generated backup file on the droplet after downloading.
#>
[CmdletBinding()]
param(
  [string]$DropletIp = '170.64.143.58',
  [string]$DropletUser = 'root',
  [string]$IdentityFile,
  [string]$RemoteAppDir = '/opt/rogainizer',
  [string]$LocalDirectory = './deploy/backups',
  [switch]$KeepRemoteFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Executable {
  param([Parameter(Mandatory = $true)][string]$Name)

  $cmd = Get-Command -Name $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required executable '$Name' was not found on PATH. Install it and retry."
  }

  return $cmd.Path
}

function Invoke-RemoteCommand {
  param(
    [Parameter(Mandatory = $true)][string]$SshCli,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$IdentityPath
  )

  $args = @()
  if ($IdentityPath) {
    $args += '-i'
    $args += $IdentityPath
  }
  $args += @($Target, $Command)

  $output = & $SshCli @args
  if ($LASTEXITCODE -ne 0) {
    throw "Remote command failed with exit code $LASTEXITCODE."
  }

  return $output
}

$sshCli = Resolve-Executable -Name 'ssh'
$scpCli = Resolve-Executable -Name 'scp'

$resolvedIdentity = $null
if ($IdentityFile) {
  if (-not (Test-Path -LiteralPath $IdentityFile)) {
    throw "Identity file not found at $IdentityFile"
  }

  $resolvedIdentity = (Resolve-Path -LiteralPath $IdentityFile).Path
}

$target = "$DropletUser@$DropletIp"

if (-not [System.IO.Path]::IsPathRooted($LocalDirectory)) {
  $LocalDirectory = Join-Path (Get-Location) $LocalDirectory
}

New-Item -Path $LocalDirectory -ItemType Directory -Force | Out-Null

$remoteCommand = "cd '$RemoteAppDir' ; bash ./deploy/backup-db.sh"
Write-Host "Creating production backup on $target..."
$remoteOutput = Invoke-RemoteCommand -SshCli $sshCli -Target $target -Command $remoteCommand -IdentityPath $resolvedIdentity

$outputLines = @($remoteOutput -split [Environment]::NewLine | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$backupLine = $outputLines | Where-Object { $_ -like 'Backup written:*' } | Select-Object -Last 1

if (-not $backupLine) {
  throw "Remote backup completed without reporting an output path. Output: $($outputLines -join ' | ')"
}

$remoteBackupPath = $backupLine.Substring('Backup written:'.Length).Trim()
if (-not $remoteBackupPath) {
  throw 'Remote backup path was empty.'
}

$localFilePath = Join-Path $LocalDirectory ([System.IO.Path]::GetFileName($remoteBackupPath))

$scpArgs = @()
if ($resolvedIdentity) {
  $scpArgs += '-i'
  $scpArgs += $resolvedIdentity
}
$scpArgs += @("${target}:$remoteBackupPath", $localFilePath)

Write-Host "Downloading $remoteBackupPath to $localFilePath..."
& $scpCli @scpArgs
if ($LASTEXITCODE -ne 0) {
  throw "scp failed with exit code $LASTEXITCODE"
}

if (-not $KeepRemoteFile) {
  $cleanupCommand = "rm -f '$remoteBackupPath'"
  Write-Host 'Removing temporary remote backup file...'
  $null = Invoke-RemoteCommand -SshCli $sshCli -Target $target -Command $cleanupCommand -IdentityPath $resolvedIdentity
}

Write-Host "Local backup written: $localFilePath"