# Instalar IIS
Install-WindowsFeature -Name Web-Server -IncludeManagementTools

# Variáveis
$siteName      = "TsuSite"
$appPoolName   = "TsuPool"
$sitePath      = "C:\inetpub\wwwroot\techspeedup"
$virtualDir    = "TsuDir"
$virtualPath   = "C:\inetpub\wwwroot\techspeedup\tsudir"
$hostname      = "tsusite.local"   # Ajuste para o host desejado (ex: tsusite.seudominio.com)
$certFriendly  = "IIS TechSpeedUp Cert"
$tempPath      = "C:\inetpub\temp"
$certFile      = "$tempPath\tsucert.cer"

# Criar pastas se não existirem
if (!(Test-Path $sitePath)) { New-Item -Path $sitePath -ItemType Directory -Force | Out-Null }
if (!(Test-Path $virtualPath)) { New-Item -Path $virtualPath -ItemType Directory -Force | Out-Null }
if (!(Test-Path $tempPath)) { New-Item -Path $tempPath -ItemType Directory -Force | Out-Null }

# Importar módulo WebAdministration
Import-Module WebAdministration

# Forçar criação do App Pool
if (Get-ChildItem IIS:\AppPools | Where-Object { $_.Name -eq $appPoolName }) {
    Remove-WebAppPool -Name $appPoolName -Confirm:$false
}
New-WebAppPool -Name $appPoolName
Set-ItemProperty IIS:\AppPools\$appPoolName -Name managedRuntimeVersion -Value "v4.0"
Set-ItemProperty IIS:\AppPools\$appPoolName -Name processModel.identityType -Value ApplicationPoolIdentity

# Forçar criação do Website
if (Get-Website | Where-Object { $_.Name -eq $siteName }) {
    Remove-Website -Name $siteName
}
New-Website -Name $siteName -PhysicalPath $sitePath -ApplicationPool $appPoolName -HostHeader $hostname -Port 80

# Criar Virtual Directory
if (Get-WebVirtualDirectory -Site $siteName -Name $virtualDir -ErrorAction SilentlyContinue) {
    Remove-WebVirtualDirectory -Site $siteName -Name $virtualDir -Confirm:$false
}
New-WebVirtualDirectory -Site $siteName -Name $virtualDir -PhysicalPath $virtualPath -ApplicationPool $appPoolName

# Criar páginas HTML
@"
<!DOCTYPE html>
<html>
<head>
    <title>TechSpeedUP de IIS</title>
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

@"
<!DOCTYPE html>
<html>
<head>
    <title>Virtual Dir</title>
</head>
<body>
    <h1>Diretorio Virtual Funcionando!</h1>
    <p>Diretorio Virtual provisionado com Terraform</p>
</body>
</html>
"@ | Out-File "$virtualPath\index.html" -Encoding utf8 -Force

# Criar certificado self-signed
$cert = New-SelfSignedCertificate -DnsName $hostname -CertStoreLocation "Cert:\LocalMachine\My" -FriendlyName $certFriendly
$thumb = $cert.Thumbprint

# Adicionar binding HTTPS na porta 443
if (!(Get-WebBinding -Name $siteName -Protocol "https" -ErrorAction SilentlyContinue)) {
    New-WebBinding -Name $siteName -Protocol https -Port 443 -HostHeader $hostname
}

# Exportar certificado para a pasta temp
$certObj = Get-Item "Cert:\LocalMachine\My\$thumb"
Export-Certificate -Cert $certObj -FilePath $certFile -Force | Out-Null

# Importar certificado para Trusted Root Certification Authorities
Import-Certificate -FilePath $certFile -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null

# Associar certificado ao binding HTTPS
$guid = [guid]::NewGuid().ToString()
netsh http delete sslcert ipport=0.0.0.0:443 2>$null
netsh http add sslcert ipport=0.0.0.0:443 certhash=$thumb appid="{$guid}"

# Reiniciar IIS
Restart-Service W3SVC -Force

Write-Output "IIS configurado com sucesso. Certificado exportado para Trusted Root. Site disponível em: http://$hostname/ e https://$hostname/"
