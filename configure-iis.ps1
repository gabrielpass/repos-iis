# Instalar IIS
Install-WindowsFeature -Name Web-Server -IncludeManagementTools

# Variáveis
$siteName      = "TsuSite"
$appPoolName   = "TsuPool"
$sitePath      = "C:\inetpub\wwwroot\techspeedup"
$virtualDir    = "TsuDir"
$virtualPath   = "C:\inetpub\wwwroot\techspeedup\tsudir"
$hostname      = "tsusite.local"
$certFriendly  = "IIS TechSpeedUp Cert"

# Criar pastas se não existirem
if (!(Test-Path $sitePath)) { New-Item -Path $sitePath -ItemType Directory -Force | Out-Null }
if (!(Test-Path $virtualPath)) { New-Item -Path $virtualPath -ItemType Directory -Force | Out-Null }

# Importar módulo WebAdministration
Import-Module WebAdministration

# Forçar criação do App Pool
if (Get-ChildItem IIS:\AppPools | Where-Object { $_.Name -eq $appPoolName }) {
    Remove-WebAppPool -Name $appPoolName -Confirm:$false
}
New-WebAppPool -Name $appPoolName
Set-ItemProperty IIS:\AppPools\$appPoolName -Name managedRuntimeVersion -Value "v4.0"
Set-ItemProperty IIS:\AppPools\$appPoolName -Name processModel.identityType -Value ApplicationPoolIdentity

# Forçar criação do Website (apenas HTTP primeiro)
if (Get-Website | Where-Object { $_.Name -eq $siteName }) {
    Remove-Website -Name $siteName
}
New-Website -Name $siteName -PhysicalPath $sitePath -ApplicationPool $appPoolName -HostHeader $hostname -Port 80

# Criar Virtual Directory
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

# ---------------------------
# Criar certificado SSL confiável
# ---------------------------
$cert = New-SelfSignedCertificate `
    -DnsName $hostname `
    -CertStoreLocation "cert:\LocalMachine\My" `
    -FriendlyName $certFriendly `
    -NotAfter (Get-Date).AddYears(2)

# Copiar para Trusted Root
$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
$rootStore.Open("ReadWrite")
$rootStore.Add($cert)
$rootStore.Close()

# ---------------------------
# Configurar binding HTTPS no IIS
# ---------------------------
if (Get-WebBinding -Name $siteName -Protocol "https" -ErrorAction SilentlyContinue) {
    Remove-WebBinding -Name $siteName -Protocol "https"
}
New-WebBinding -Name $siteName -Protocol "https" -Port 443 -HostHeader $hostname

# Associar certificado ao binding corretamente
$certHash = $cert.Thumbprint
$binding = "IIS:\SslBindings\0.0.0.0!443!$hostname"

if (Test-Path $binding) {
    Remove-Item $binding -Force
}
New-Item $binding -Thumbprint $certHash -SSLFlags 1

# Reiniciar IIS
Restart-Service W3SVC -Force

Write-Output "IIS configurado com sucesso."
Write-Output "HTTP:  http://$hostname/"
Write-Output "HTTPS: https://$hostname/"
