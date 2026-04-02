<#
.SYNOPSIS
  Opens an SSH tunnel from a local port to the production droplet MySQL port.
.DESCRIPTION
  For local frontend/backend development, this forwards a local TCP port to the
  MySQL service reachable from the production droplet. This avoids connecting to
  the database over a public MySQL port directly.

  Keep this script running while using the local backend. Stop it with Ctrl+C.
.PARAMETER DropletIp
  IP or hostname of the production droplet.
.PARAMETER DropletUser
  SSH user for the droplet.
.PARAMETER LocalPort
  Local port to bind on your machine. Defaults to 3307 to avoid clashing with a
  local MySQL instance.
.PARAMETER RemoteHost
  Host to connect to from the droplet side. Defaults to 127.0.0.1.
.PARAMETER RemotePort
  Port to connect to from the droplet side. Defaults to 3306.
.PARAMETER IdentityFile
  Optional SSH private key passed via -i.
.EXAMPLE
  ./deploy/open-prod-db-tunnel.ps1
.EXAMPLE
  ./deploy/open-prod-db-tunnel.ps1 -DropletUser ubuntu -IdentityFile ~/.ssh/id_ed25519
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

$sshCli = Resolve-Executable -Name 'ssh'

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

$sshArgs = @('-N', '-L', $forwardSpec, $target)
if ($resolvedIdentity) {
  $sshArgs = @('-i', $resolvedIdentity) + $sshArgs
}

Write-Host "Opening SSH tunnel on localhost:${LocalPort} to ${RemoteHost}:${RemotePort} via $target"
Write-Host 'Keep this terminal open while the local backend is running. Press Ctrl+C to stop the tunnel.'

& $sshCli @sshArgs

if ($LASTEXITCODE -ne 0) {
  throw "ssh exited with code $LASTEXITCODE"
}