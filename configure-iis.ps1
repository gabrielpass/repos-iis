# -----------------------------
# Configuração IIS - TechSpeedUP
# -----------------------------

# Variáveis
$siteName      = "TsuSite"
$appPoolName   = "TsuPool"
$sitePath      = "C:\inetpub\wwwroot\techspeedup"
$virtualDir    = "TsuDir"
$virtualPath   = "C:\inetpub\wwwroot\techspeedup\tsudir"
$hostHeader    = "tsusite.local"
$vmIp          = "172.191.49.108"  # Troque pelo IP da VM

# Instalar IIS
Install-WindowsFeature -Name Web-Server -IncludeManagementTools -Verbose

# Criar pastas se não existirem
if (!(Test-Path $sitePath)) { New-Item -Path $sitePath -ItemType Directory -Force | Out-Null }
if (!(Test-Path $virtualPath)) { New-Item -Path $virtualPath -ItemType Directory -Force | Out-Null }

# Importar módulo WebAdministration
Import-Module WebAdministration

# Criar App Pool (remove se já existir)
if (Get-ChildItem IIS:\AppPools | Where-Object { $_.Name -eq $appPoolName }) {
    Remove-WebAppPool -Name $appPoolName -Confirm:$false
}
New-WebAppPool -Name $appPoolName
Set-ItemProperty IIS:\AppPools\$appPoolName -Name managedRuntimeVersion -Value "v4.0"
Set-ItemProperty IIS:\AppPools\$appPoolName -Name processModel.identityType -Value ApplicationPoolIdentity

# Criar Website (remove se já existir)
if (Get-Website | Where-Object { $_.Name -eq $siteName }) {
    Remove-Website -Name $siteName
}
New-Website -Name $siteName -PhysicalPath $sitePath -ApplicationPool $appPoolName -Port 80 -HostHeader $hostHeader

# Criar Virtual Directory (remove se já existir)
if (Get-WebVirtualDirectory -Site $siteName -Name $virtualDir -ErrorAction SilentlyContinue) {
    Remove-WebVirtualDirectory -Site $siteName -Name $virtualDir -Confirm:$false
}
New-WebVirtualDirectory -Site $siteName -Name $virtualDir -PhysicalPath $virtualPath -ApplicationPool $appPoolName

# Criar página HTML principal
@"
<!DOCTYPE html>
<html>
<head>
    <title>TechSpeedUP IIS</title>
    <style>
        body { font-family: Arial; background-color: #f0f0f0; text-align: center; padding-top: 50px; }
        h1 { color: #0078D7; }
        p { font-size: 18px; }
    </style>
</head>
<body>
    <h1>Bem Vindos ao TechSpeedUP de IIS!</h1>
    <p>Website provisionado com Terraform + Custom Script Extension</p>
</body>
</html>
"@ | Out-File "$sitePath\index.html" -Encoding utf8 -Force

# Criar página HTML no Virtual Directory
@"
<!DOCTYPE html>
<html>
<head>
    <title>Virtual Directory</title>
</head>
<body>
    <h1>Diretório Virtual Funcionando!</h1>
    <p>Diretório Virtual provisionado com Terraform</p>
</body>
</html>
"@ | Out-File "$virtualPath\index.html" -Encoding utf8 -Force

# Adicionar entrada no hosts local (apenas para testes)
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$entry = "$vmIp`t$hostHeader"

if (-not (Select-String -Path $hostsPath -Pattern $hostHeader -Quiet)) {
    Add-Content -Path $hostsPath -Value $entry
    Write-Output "Entrada adicionada no hosts: $entry"
} else {
    Write-Output "Entrada hosts já existe para $hostHeader"
}

# Reiniciar IIS para aplicar alterações
Restart-Service W3SVC -Force

Write-Output "IIS configurado com sucesso. Site: http://$hostHeader/"
