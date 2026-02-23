param(
    [Parameter(Mandatory = $true)]
    [string]$DropletIp,

    [string]$DropletUser = "root",
    [string]$KeyName = "gh-actions-rogainizer",
    [string]$OutputDirectory = (Join-Path -Path $PSScriptRoot -ChildPath "../.deploy-keys")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$keyPath = Join-Path -Path $OutputDirectory -ChildPath $KeyName
$pubKeyPath = "$keyPath.pub"

if (-not (Test-Path -Path $keyPath)) {
    Write-Host "Generating new SSH key pair at $keyPath"
    $resolvedKeyPath = [System.IO.Path]::GetFullPath($keyPath)
    $sshArgs = @('-t', 'ed25519', '-f', $resolvedKeyPath, '-N', '""', '-C', 'github-actions-deploy')
    $process = Start-Process -FilePath 'ssh-keygen' -ArgumentList $sshArgs -NoNewWindow -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        throw "ssh-keygen failed with exit code $($process.ExitCode)"
    }
} else {
    Write-Host "SSH key already exists at $keyPath; skipping generation."
}

if (-not (Test-Path -Path $pubKeyPath)) {
    throw "Public key not found at $pubKeyPath"
}

$remoteTmpPath = "/tmp/$KeyName.pub"

Write-Host "Copying public key to $DropletUser@${DropletIp}:$remoteTmpPath"
scp $pubKeyPath "$DropletUser@${DropletIp}:$remoteTmpPath"

$appendCommand = @"
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat $remoteTmpPath >> ~/.ssh/authorized_keys
rm -f $remoteTmpPath
chmod 600 ~/.ssh/authorized_keys
"@

Write-Host "Appending public key to ~/.ssh/authorized_keys on droplet"
ssh "$DropletUser@$DropletIp" "$appendCommand"

Write-Host "Deployment key ready. Upload the private key at $keyPath to the GitHub secret DROPLET_SSH_KEY."
