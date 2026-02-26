<#[
.SYNOPSIS
  Export a single leader board together with its linked events and results into a SQL file.
.DESCRIPTION
  Uses mysql / mysqldump (either locally installed or via docker exec into the DB container)
  to pull the selected leader board (by id or name/year), the
  joining entries in leader_board_results, and all referenced events / results / teams rows.
  The output is an INSERT-only SQL file that can be replayed against another database.
.EXAMPLE
  ./deploy/dump-leader-board.ps1 -LeaderBoardId 3 -OutputPath ./leader-board-3.sql
.EXAMPLE
  ./deploy/dump-leader-board.ps1 -LeaderBoardName "2024 Sprint" -LeaderBoardYear 2024
.PARAMETER LeaderBoardId
  The numeric id of the leader board to export.
.PARAMETER LeaderBoardName
  The display name of the leader board to export. Combine with -LeaderBoardYear to
  disambiguate duplicates.
.PARAMETER LeaderBoardYear
  Optional year filter when searching by name.
.PARAMETER OutputPath
  Destination .sql file. Defaults to ./leader-board-dump.sql relative to the current directory.
.PARAMETER DbHost
  MySQL host. Defaults to the ROGAINIZER_DB_HOST environment variable or 127.0.0.1.
.PARAMETER DbPort
  MySQL port. Defaults to ROGAINIZER_DB_PORT or 3306.
.PARAMETER DbUser
  MySQL username. Defaults to ROGAINIZER_DB_USER or root.
.PARAMETER DbPassword
  MySQL password. Defaults to ROGAINIZER_DB_PASSWORD. If empty, mysqldump/mysql will prompt.
.PARAMETER Database
  Schema name to target. Defaults to ROGAINIZER_DB_NAME or rogainizer.
.PARAMETER Overwrite
  Allow overwriting an existing OutputPath.
.PARAMETER UseDockerDb
  When true (default) run mysql/mysqldump inside the running db container via docker exec.
.PARAMETER DockerContainerName
  Name of the MySQL container to exec into when UseDockerDb is true. Defaults to rogainizer-db.
#>
[CmdletBinding(DefaultParameterSetName = 'ById')]
param(
  [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
  [int]$LeaderBoardId,

  [Parameter(Mandatory = $true, ParameterSetName = 'ByName')]
  [string]$LeaderBoardName,

  [Parameter(ParameterSetName = 'ByName')]
  [int]$LeaderBoardYear,

  [string]$OutputPath = './leader-board-dump.sql',
  [string]$DbHost = $(if ($env:ROGAINIZER_DB_HOST) { $env:ROGAINIZER_DB_HOST } else { '127.0.0.1' }),
  [int]$DbPort = $(if ($env:ROGAINIZER_DB_PORT) { [int]$env:ROGAINIZER_DB_PORT } else { 3306 }),
  [string]$DbUser = $(if ($env:ROGAINIZER_DB_USER) { $env:ROGAINIZER_DB_USER } else { 'root' }),
  [string]$DbPassword = $(if ($env:ROGAINIZER_DB_PASSWORD) { $env:ROGAINIZER_DB_PASSWORD } else { 'root' }),
  [string]$Database = $(if ($env:ROGAINIZER_DB_NAME) { $env:ROGAINIZER_DB_NAME } else { 'rogainizer' }),
  [switch]$Overwrite,
  [bool]$UseDockerDb = $true,
  [string]$DockerContainerName = 'rogainizer-db'
)

$ErrorActionPreference = 'Stop'

function Resolve-Executable {
  param(
    [Parameter(Mandatory = $true)][string]$Name
  )
  $exe = Get-Command -Name $Name -ErrorAction SilentlyContinue
  if (-not $exe) {
    throw "Required executable '$Name' was not found on PATH. Install it and retry."
  }
  return $exe.Path
}

function Assert-DockerContainerRunning {
  param(
    [Parameter(Mandatory = $true)][string]$DockerCliPath,
    [Parameter(Mandatory = $true)][string]$ContainerName
  )

  $args = @('ps', '--filter', "name=$ContainerName", '--format', '{{.Names}}')
  $result = & $DockerCliPath @args
  if ($LASTEXITCODE -ne 0) {
    throw 'Failed to query docker for running containers.'
  }

  $names = $result -split [Environment]::NewLine | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  if (-not ($names | Where-Object { $_ -eq $ContainerName })) {
    throw "Docker container '$ContainerName' is not running. Start it (e.g. docker compose up db) and retry."
  }
}

$dockerCli = $null
$mysqlCli = $null
$mysqldumpCli = $null

if ($UseDockerDb) {
  $dockerCli = Resolve-Executable -Name 'docker'
  Assert-DockerContainerRunning -DockerCliPath $dockerCli -ContainerName $DockerContainerName
} else {
  $mysqlCli = Resolve-Executable -Name 'mysql'
  $mysqldumpCli = Resolve-Executable -Name 'mysqldump'
}

function Invoke-MySqlQuery {
  param([
    Parameter(Mandatory = $true)
    ][string]$Query)

  $args = @('-N', '-B', '-h', $DbHost, '-P', $DbPort, '-u', $DbUser, '-D', $Database, '-e', $Query)
  if ($DbPassword) {
    $args += "--password=$DbPassword"
  }

  if ($UseDockerDb) {
    $fullArgs = @('exec', '-i', $DockerContainerName, 'mysql') + $args
    $raw = & $dockerCli @fullArgs
  } else {
    $raw = & $mysqlCli @args
  }
  if ($LASTEXITCODE -ne 0) {
    throw "mysql query failed: $raw"
  }

  $lines = $raw -split [Environment]::NewLine
  $lines = $lines | Where-Object { $_ -and $_.Trim().Length -gt 0 }
  return @($lines)
}

function Dump-TableData {
  param(
    [Parameter(Mandatory = $true)][string]$Table,
    [Parameter()][string]$WhereClause
  )

  $args = @(
    '--single-transaction',
    '--skip-lock-tables',
    '--skip-comments',
    '--skip-add-locks',
    '--skip-disable-keys',
    '--skip-set-charset',
    '--no-create-info',
    '--complete-insert',
    '--compact',
    '--set-gtid-purged=OFF',
    '-h', $DbHost,
    '-P', $DbPort,
    '-u', $DbUser
  )
  if ($DbPassword) {
    $args += "--password=$DbPassword"
  }
  if ($WhereClause) {
    $args += '--where'
    $args += $WhereClause
  }
  $args += @($Database, $Table)

  if ($UseDockerDb) {
    $fullArgs = @('exec', '-i', $DockerContainerName, 'mysqldump') + $args
    $dump = & $dockerCli @fullArgs
  } else {
    $dump = & $mysqldumpCli @args
  }
  if ($LASTEXITCODE -ne 0) {
    throw "mysqldump failed for table '$Table'"
  }

  Add-Content -Path $OutputPath -Value $dump -Encoding UTF8
  Add-Content -Path $OutputPath -Value "`n" -Encoding UTF8
}

function Escape-SqlLiteral {
  param([string]$Value)
  return $Value.Replace("'", "''")
}

if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath = Join-Path -Path (Get-Location) -ChildPath $OutputPath
}

$directory = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -Path $directory)) {
  New-Item -Path $directory -ItemType Directory -Force | Out-Null
}

if ((Test-Path -Path $OutputPath) -and -not $Overwrite) {
  throw "Output file '$OutputPath' already exists. Use -Overwrite to replace it."
}

if (Test-Path -Path $OutputPath) {
  Remove-Item -Path $OutputPath -Force
}

if ($PSCmdlet.ParameterSetName -eq 'ByName') {
  $conditions = @("name = '$(Escape-SqlLiteral -Value $LeaderBoardName)'")
  if ($LeaderBoardYear) {
    $conditions += "year = $LeaderBoardYear"
  }
  $idQuery = "SELECT id FROM leader_boards WHERE $([string]::Join(' AND ', $conditions));"
  $matchingIds = @(Invoke-MySqlQuery -Query $idQuery)

  if ($matchingIds.Count -eq 0) {
    throw "No leader board rows matched the provided name/year criteria."
  }
  if ($matchingIds.Count -gt 1) {
    throw "Multiple leader boards matched. Please rerun with -LeaderBoardId. Matching ids: $([string]::Join(', ', $matchingIds))"
  }

  $LeaderBoardId = [int]$matchingIds[0]
}

$leaderBoardRow = @(Invoke-MySqlQuery -Query "SELECT id, name, year, event_count FROM leader_boards WHERE id = $LeaderBoardId LIMIT 1;")
if ($leaderBoardRow.Count -eq 0) {
  throw "Leader board id $LeaderBoardId was not found."
}

$lbParts = $leaderBoardRow[0] -split "`t"
if ($lbParts.Length -lt 4) {
  throw "Unexpected mysql output when reading leader board row."
}
$leaderBoardName = $lbParts[1]
$leaderBoardYear = [int]$lbParts[2]
$eventCountRecorded = [int]$lbParts[3]

$eventRows = @(Invoke-MySqlQuery -Query "SELECT event_id FROM leader_board_results WHERE leader_board_id = $LeaderBoardId ORDER BY event_id;")
$eventIds = @()
foreach ($row in $eventRows) {
  $eventIds += [int]$row.Trim()
}

$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'
$header = @()
$header += "-- Leader board export generated $timestamp"
$header += "-- Leader Board: $leaderBoardName ($leaderBoardYear) [ID $LeaderBoardId]"
$header += "-- Linked events found: $($eventIds.Count) (leader_board.event_count recorded $eventCountRecorded)"
$header += 'SET FOREIGN_KEY_CHECKS=0;'
$header += ''
Set-Content -Path $OutputPath -Value ($header -join "`n") -Encoding UTF8

$leaderBoardTableSpecs = @(
  @{ Table = 'leader_boards'; Where = "id = $LeaderBoardId" },
  @{ Table = 'leader_board_results'; Where = "leader_board_id = $LeaderBoardId" }
)

foreach ($spec in $leaderBoardTableSpecs) {
  Dump-TableData -Table $spec.Table -WhereClause $spec.Where
}

if ($eventIds.Count -gt 0) {
  $eventListLiteral = '({0})' -f ([string]::Join(', ', $eventIds))
  $eventScopedTableSpecs = @(
    @{ Table = 'events'; Column = 'id' },
    @{ Table = 'results'; Column = 'event_id' },
    @{ Table = 'teams'; Column = 'event_id' }
  )

  foreach ($spec in $eventScopedTableSpecs) {
    $where = "$($spec.Column) IN $eventListLiteral"
    Dump-TableData -Table $spec.Table -WhereClause $where
  }
} else {
  Write-Warning "No events are linked to leader board id $LeaderBoardId. Skipping event/result dumps."
}

Add-Content -Path $OutputPath -Value 'SET FOREIGN_KEY_CHECKS=1;' -Encoding UTF8

Write-Host "Export complete -> $OutputPath"
