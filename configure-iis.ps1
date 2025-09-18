# =========================
# Variáveis do site
# =========================
$siteName      = "TsuSite"
$appPoolName   = "TsuPool"
$sitePath      = "C:\inetpub\wwwroot\techspeedup"
$virtualDir    = "TsuDir"
$virtualPath   = "C:\inetpub\wwwroot\techspeedup\tsudir"
$hostname      = "tsusite.local"      # Nome do host
$certFriendly  = "IIS TechSpeedUp Cert"

# =========================
# Instalar IIS
# =========================
Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null

# Criar pastas se não existirem
if (!(Test-Path $sitePath)) { New-Item -Path $sitePath -ItemType Directory -Force | Out-Null }
if (!(Test-Path $virtualPath)) { New-Item -Path $virtualPath -ItemType Directory -Force | Out-Null }

# Importar módulo WebAdministration
Import-Module WebAdministration

# =========================
# App Pool
# =========================
if (Get-ChildItem IIS:\AppPools | Where-Object { $_.Name -eq $appPoolName }) {
    Remove-WebAppPool -Name $appPoolName -Confirm:$false
}
New-WebAppPool -Name $appPoolName
Set-ItemProperty IIS:\AppPools\$appPoolName -Name managedRuntimeVersion -Value "v4.0"
Set-ItemProperty IIS:\AppPools\$appPoolName -Name processModel.identityType -Value ApplicationPoolIdentity

# =========================
# Website HTTP
# =========================
if (Get-Website | Where-Object { $_.Name -eq $siteName }) {
    Remove-Website -Name $siteName
}
New-Website -Name $siteName -PhysicalPath $sitePath -ApplicationPool $appPoolName -Port 80 -HostHeader $hostname

# =========================
# Virtual Directory
# =========================
if (Get-WebVirtualDirectory -Site $siteName -Name $virtualDir -ErrorAction SilentlyContinue) {
    Remove-WebVirtualDirectory -Site $siteName -Name $virtualDir -Confirm:$false
}
New-WebVirtualDirectory -Site $siteName -Name $virtualDir -PhysicalPath $virtualPath -ApplicationPool $appPoolName

# =========================
# Criar páginas HTML
# =========================
# Site principal
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
    <h1>Bem Vindos ao TechSpeedUP IIS!</h1>
    <p>Website provisionado via Terraform + Custom Script Extension</p>
</body>
</html>
"@ | Out-File "$sitePath\index.html" -Encoding utf8 -Force

# Virtual Directory
@"
<!DOCTYPE html>
<html>
<head>
    <title>Virtual Dir</title>
</head>
<body>
    <h1>Diretório Virtual Funcionando!</h1>
    <p>Conteúdo servido a partir de: $virtualPath</p>
</body>
</html>
"@ | Out-File "$virtualPath\index.html" -Encoding utf8 -Force

# =========================
# Certificado SSL
# =========================
# Remover certificado antigo
$oldCerts = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq $certFriendly }
if ($oldCerts) { $oldCerts | ForEach-Object { Remove-Item "Cert:\LocalMachine\My\$($_.Thumbprint)" -Force } }

# Criar self-signed
$cert = New-SelfSignedCertificate -DnsName $hostname -CertStoreLocation "Cert:\LocalMachine\My" -FriendlyName $certFriendly

# Adicionar ao Trusted Root
$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
$rootStore.Open("ReadWrite")
$rootStore.Add($cert)
$rootStore.Close()

# =========================
# Website HTTPS
# =========================
# Remover binding HTTPS se existir
$existingBinding = Get-WebBinding -Name $siteName -Protocol "https" -ErrorAction SilentlyContinue
if ($existingBinding) { Remove-WebBinding -Name $siteName -Protocol "https" }

# Criar binding HTTPS
New-WebBinding -Name $siteName -Protocol "https" -Port 443 -IPAddress "*" -HostHeader $hostname

# Associar certificado
$certThumb = $cert.Thumbprint
$bindingPath = "IIS:\SslBindings\0.0.0.0!443"
if (Test-Path $bindingPath) { Remove-Item $bindingPath -Force }
New-Item $bindingPath -Thumbprint $certThumb -SSLFlags 1

# =========================
# Redirecionar HTTP para HTTPS
# =========================
Set-WebConfigurationProperty -Filter "system.webServer/rewrite/rules" -PSPath "IIS:\Sites\$siteName" -Name "." -Value @() -ErrorAction SilentlyContinue
Add-WebConfiguration -Filter "system.webServer/httpRedirect" -PSPath "IIS:\Sites\$siteName" -Value @{enabled="true"; destination="https://$hostname/"; httpResponseStatus="Permanent"}

# =========================
# Reiniciar IIS
# =========================
Restart-Service W3SVC -Force

Write-Output "IIS configurado com sucesso. Site HTTP/HTTPS pronto com certificado '$certFriendly'"
