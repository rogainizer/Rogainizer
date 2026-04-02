<#
.SYNOPSIS
  Starts the local frontend/backend dev stack and a production DB SSH tunnel together.
.DESCRIPTION
  Opens an SSH tunnel to the production droplet's MySQL port, then runs the repo's
  existing `npm run dev` command from the project root. When the dev command exits,
  the tunnel process is stopped automatically.

  This script expects backend/.env to already point at the tunneled database host
  and port, typically 127.0.0.1:3307.
.PARAMETER DropletIp
  IP or hostname of the production droplet.
.PARAMETER DropletUser
  SSH user for the droplet.
.PARAMETER LocalPort
  Local port to bind on your machine. Defaults to 3307.
.PARAMETER RemoteHost
  Host to connect to from the droplet side. Defaults to 127.0.0.1.
.PARAMETER RemotePort
  Port to connect to from the droplet side. Defaults to 3306.
.PARAMETER IdentityFile
  Optional SSH private key passed via -i.
#>
[CmdletBinding()]
param(
  [string]$DropletIp = '170.64.143.58',
  [string]$DropletUser = 'root',
  [int]$LocalPort = 3307,
  [string]$RemoteHost = '127.0.0.1',
  [int]$RemotePort = 3306,
  [string]$IdentityFile
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

function Test-LocalPortAvailable {
  param([Parameter(Mandatory = $true)][int]$Port)

  $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
  return -not $listeners
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$backendEnvPath = Join-Path $projectRoot 'backend/.env'

if (-not (Test-Path -LiteralPath $backendEnvPath)) {
  throw "Missing backend/.env. Configure it for the tunneled DB before running this script."
}

$sshCli = Resolve-Executable -Name 'ssh'
$npmCli = Resolve-Executable -Name 'npm'

$resolvedIdentity = $null
if ($IdentityFile) {
  if (-not (Test-Path -LiteralPath $IdentityFile)) {
    throw "Identity file not found at $IdentityFile"
  }

  $resolvedIdentity = (Resolve-Path -LiteralPath $IdentityFile).Path
}

if (-not (Test-LocalPortAvailable -Port $LocalPort)) {
  throw "Local port $LocalPort is already in use. Choose another port and retry."
}

$target = "$DropletUser@$DropletIp"
$forwardSpec = "$LocalPort`:${RemoteHost}`:$RemotePort"

$sshArgs = @(
  '-o', 'ExitOnForwardFailure=yes',
  '-o', 'ServerAliveInterval=30',
  '-o', 'ServerAliveCountMax=3',
  '-N',
  '-L', $forwardSpec,
  $target
)

if ($resolvedIdentity) {
  $sshArgs = @('-i', $resolvedIdentity) + $sshArgs
}

Write-Host "Starting SSH tunnel on localhost:${LocalPort} to ${RemoteHost}:${RemotePort} via $target"

$sshProcess = Start-Process -FilePath $sshCli -ArgumentList $sshArgs -PassThru

Start-Sleep -Seconds 2

if ($sshProcess.HasExited) {
  throw "SSH tunnel failed to start. ssh exited with code $($sshProcess.ExitCode)."
}

Write-Host 'SSH tunnel started.'
Write-Host 'Starting local frontend and backend with npm run dev...'

Push-Location $projectRoot
try {
  & $npmCli run dev
  if ($LASTEXITCODE -ne 0) {
    throw "npm run dev exited with code $LASTEXITCODE"
  }
}
finally {
  Pop-Location

  if ($sshProcess -and -not $sshProcess.HasExited) {
    Write-Host 'Stopping SSH tunnel...'
    Stop-Process -Id $sshProcess.Id -Force
  }
}