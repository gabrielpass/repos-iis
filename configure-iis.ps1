# Instalar IIS
Install-WindowsFeature -Name Web-Server -IncludeManagementTools

# Variáveis
$siteName      = "TsuSite"
$appPoolName   = "TsuPool"
$sitePath      = "C:\inetpub\wwwroot\techspeedup"
$virtualDir    = "TsuDir"
$virtualPath   = "C:\inetpub\wwwroot\techspeedup\tsudir"
$hostname      = "tsusite.local"   # Ajuste conforme necessário
$certFriendly  = "IIS TechSpeedUp Cert"

# Criar pastas se não existirem
if (!(Test-Path $sitePath)) {
    New-Item -Path $sitePath -ItemType Directory -Force | Out-Null
}
if (!(Test-Path $virtualPath)) {
    New-Item -Path $virtualPath -ItemType Directory -Force | Out-Null
}

# Importar módulo WebAdministration
Import-Module WebAdministration

# App Pool
if (Get-WebAppPoolState -Name $appPoolName -ErrorAction SilentlyContinue) {
    Remove-WebAppPool -Name $appPoolName -Confirm:$false
}
New-WebAppPool -Name $appPoolName
Set-ItemProperty IIS:\AppPools\$appPoolName -Name managedRuntimeVersion -Value "v4.0"
Set-ItemProperty IIS:\AppPools\$appPoolName -Name processModel.identityType -Value ApplicationPoolIdentity

# Website
if (Get-Website | Where-Object { $_.Name -eq $siteName }) {
    Remove-Website -Name $siteName
}
New-Website -Name $siteName -PhysicalPath $sitePath -ApplicationPool $appPoolName -HostHeader $hostname -Port 80

# Virtual Directory
if (Get-WebVirtualDirectory -Site $siteName -Name $virtualDir -ErrorAction SilentlyContinue) {
    Remove-WebVirtualDirectory -Site $siteName -Name $virtualDir -Confirm:$false
}
New-WebVirtualDirectory -Site $siteName -Name $virtualDir -PhysicalPath $virtualPath -ApplicationPool $appPoolName

# Criar página HTML principal
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

# Criar página HTML no Virtual Directory
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

# --- CERTIFICADO ---
# Remover certificado antigo com mesmo FriendlyName
$oldCerts = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq $certFriendly }
if ($oldCerts) {
    foreach ($c in $oldCerts) {
        Write-Output "Removendo certificado antigo: $($c.Thumbprint)"
        Remove-Item -Path "Cert:\LocalMachine\My\$($c.Thumbprint)" -Force
    }
}

# Criar novo certificado self-signed
$cert = New-SelfSignedCertificate -DnsName $hostname -CertStoreLocation "Cert:\LocalMachine\My" -FriendlyName $certFriendly

# Adicionar certificado no Trusted Root (para evitar erro de confiança local)
$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
$rootStore.Open("ReadWrite")
$rootStore.Add($cert)
$rootStore.Close()

# --- BINDINGS ---
# Garantir que binding HTTP existe
if (-not (Get-WebBinding -Name $siteName -Protocol "http" -ErrorAction SilentlyContinue)) {
    New-WebBinding -Name $siteName -Protocol "http" -Port 80 -HostHeader $hostname
}

# Garantir que binding HTTPS existe (remove antes para recriar)
if (Get-WebBinding -Name $siteName -Protocol "https" -ErrorAction SilentlyContinue) {
    Remove-WebBinding -Name $siteName -Protocol "https"
}
New-WebBinding -Name $siteName -Protocol "https" -Port 443 -HostHeader $hostname

# Associar certificado ao binding HTTPS
$binding = "IIS:\SslBindings\0.0.0.0!443!$hostname"
if (Test-Path $binding) {
    Remove-Item $binding -Force
}
New-Item $binding -Thumbprint $cert.Thumbprint -SSLFlags 1

# Reiniciar IIS
Restart-Service W3SVC -Force

Write-Output "IIS configurado com sucesso. Site disponível em: http://$hostname/ e https://$hostname/"
