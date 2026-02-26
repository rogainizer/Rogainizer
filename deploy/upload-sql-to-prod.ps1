<#[
.SYNOPSIS
  Copies a local SQL file to the production droplet via SCP.
.DESCRIPTION
  Ensures the remote destination directory exists, optionally prevents overwriting existing
  files, and supports specifying a custom SSH identity file. Useful for pushing leader-board
  exports created with dump-leader-board.ps1 to the prod host prior to running imports.
.PARAMETER SqlFilePath
  Local path to the .sql (or .gz) file to upload.
.PARAMETER DropletIp
  IP or hostname of the production droplet.
.PARAMETER DropletUser
  SSH user for the droplet. Defaults to root.
.PARAMETER RemoteDirectory
  Remote directory to place the uploaded file. Created if missing.
.PARAMETER RemoteFileName
  Optional override for the remote file name.Defaults to the local file name.
.PARAMETER IdentityFile
  Optional path to the SSH private key to use (passed to ssh/scp via -i).
.PARAMETER NormalizeLineEndings
  Convert CRLF sequences to LF in a temporary copy before uploading (enabled by default).
.PARAMETER ForceOverwrite
  Overwrite the remote file if it already exists.
#>
[CmdletBinding()]
param(
  [string]$SqlFilePath,

  [string]$DropletIp = '170.64.143.58',
  [string]$DropletUser = 'root',
  [string]$RemoteDirectory = '/opt/rogainizer/sql-drops',
  [string]$RemoteFileName,
  [string]$IdentityFile,
  [bool]$NormalizeLineEndings = $true,
  [switch]$ForceOverwrite
)

$ErrorActionPreference = 'Stop'

function Resolve-Cli {
  param([Parameter(Mandatory = $true)][string]$Name)
  $cmd = Get-Command -Name $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required executable '$Name' was not found on PATH. Install it and retry."
  }
  return $cmd.Path
}

function ConvertTo-RemoteLiteral {
  param([Parameter(Mandatory = $true)][string]$Value)
  $escaped = $Value.Replace('"', '\"')
  return '"' + $escaped + '"'
}

function Invoke-RemoteCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [int[]]$AcceptExitCodes = @(0)
  )

  $args = @()
  if ($script:ResolvedIdentity) {
    $args += '-i'
    $args += $script:ResolvedIdentity
  }
  $args += @($script:RemoteTarget, $Command)

  $result = & $script:SshCli @args
  $exitCode = $LASTEXITCODE

  if (-not ($AcceptExitCodes -contains $exitCode)) {
    throw "Remote command failed (exit $exitCode): $result"
  }

  return [pscustomobject]@{
    Output = $result
    ExitCode = $exitCode
  }
}

if (-not (Test-Path -LiteralPath $SqlFilePath)) {
  throw "SQL file not found at $SqlFilePath"
}

$ResolvedLocalFile = (Resolve-Path -LiteralPath $SqlFilePath).Path

if ($IdentityFile) {
  if (-not (Test-Path -LiteralPath $IdentityFile)) {
    throw "Identity file not found at $IdentityFile"
  }
  $script:ResolvedIdentity = (Resolve-Path -LiteralPath $IdentityFile).Path
} else {
  $script:ResolvedIdentity = $null
}

if (-not $RemoteFileName) {
  $RemoteFileName = Split-Path -Path $ResolvedLocalFile -Leaf
}

if (-not $RemoteFileName.Trim()) {
  throw 'Remote file name cannot be empty.'
}

$uploadFilePath = $ResolvedLocalFile
$tempFilePath = $null
$binaryExtensions = @('.gz', '.zip', '.bz2', '.7z')
$fileExtension = [System.IO.Path]::GetExtension($ResolvedLocalFile)
if (-not $fileExtension) {
  $fileExtension = ''
}
$fileExtension = $fileExtension.ToLowerInvariant()
$shouldNormalize = $NormalizeLineEndings -and -not ($binaryExtensions -contains $fileExtension)

if ($shouldNormalize) {
  $tempFilePath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())
  try {
    $content = Get-Content -LiteralPath $ResolvedLocalFile -Raw
    $normalized = $content -replace "`r`n", "`n"
    Set-Content -LiteralPath $tempFilePath -Value $normalized -Encoding UTF8
    $uploadFilePath = $tempFilePath
  } catch {
    if ($tempFilePath -and (Test-Path -LiteralPath $tempFilePath)) {
      Remove-Item -LiteralPath $tempFilePath -Force
    }
    throw
  }
}

$script:SshCli = Resolve-Cli -Name 'ssh'
$script:ScpCli = Resolve-Cli -Name 'scp'
$script:RemoteTarget = "$DropletUser@$DropletIp"

$RemoteDirectory = $RemoteDirectory.TrimEnd('/')
if (-not $RemoteDirectory) {
  throw 'RemoteDirectory cannot be empty.'
}
$RemoteFilePath = "$RemoteDirectory/$RemoteFileName"

$remoteDirLiteral = ConvertTo-RemoteLiteral -Value $RemoteDirectory
$remoteFileLiteral = ConvertTo-RemoteLiteral -Value $RemoteFilePath

Invoke-RemoteCommand -Command "mkdir -p $remoteDirLiteral"

$existsResult = Invoke-RemoteCommand -Command "test -f $remoteFileLiteral" -AcceptExitCodes @(0,1)
if ($existsResult.ExitCode -eq 0 -and -not $ForceOverwrite) {
  throw "Remote file $RemoteFilePath already exists. Re-run with -ForceOverwrite to replace it."
}

$scpArgs = @()
if ($script:ResolvedIdentity) {
  $scpArgs += '-i'
  $scpArgs += $script:ResolvedIdentity
}
$scpArgs += @($uploadFilePath, "$($script:RemoteTarget):$RemoteFilePath")

try {
  $null = & $script:ScpCli @scpArgs
  if ($LASTEXITCODE -ne 0) {
    throw "scp failed with exit code $LASTEXITCODE"
  }
} finally {
  if ($tempFilePath -and (Test-Path -LiteralPath $tempFilePath)) {
    Remove-Item -LiteralPath $tempFilePath -Force
  }
}

Write-Host "Uploaded $ResolvedLocalFile to $($script:RemoteTarget):$RemoteFilePath"
