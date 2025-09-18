# =========================
# Variáveis do site
# =========================
$siteName      = "TsuSite"
$appPoolName   = "TsuPool"
$sitePath      = "C:\inetpub\wwwroot\techspeedup"
$virtualDir    = "TsuDir"
$virtualPath   = "C:\inetpub\wwwroot\techspeedup\tsudir"
$hostname      = "tsusite.local"
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
# Criar Site HTTP (80) se não existir
# =========================
if (Get-Website | Where-Object { $_.Name -eq $siteName }) {
    Remove-Website -Name $siteName
}
New-Website -Name $siteName -PhysicalPath $sitePath -ApplicationPool $appPoolName -Port 80 -HostHeader $hostname

# =========================
# Criar Virtual Directory
# =========================
if (Get-WebVirtualDirectory -Site $siteName -Name $virtualDir -ErrorAction SilentlyContinue) {
    Remove-WebVirtualDirectory -Site $siteName -Name $virtualDir -Confirm:$false
}
New-WebVirtualDirectory -Site $siteName -Name $virtualDir -PhysicalPath $virtualPath -ApplicationPool $appPoolName

# =========================
# Criar páginas HTML
# =========================
@"
<!DOCTYPE html>
<html>
<head>
    <title>TechSpeedUP IIS</title>
</head>
<body>
    <h1>Bem Vindos ao TechSpeedUP IIS!</h1>
    <p>Site provisionado via Terraform + PowerShell</p>
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
    <h1>Diretório Virtual Funcionando!</h1>
    <p>Conteúdo: $virtualPath</p>
</body>
</html>
"@ | Out-File "$virtualPath\index.html" -Encoding utf8 -Force

# =========================
# Certificado SSL (Self-Signed)
# =========================
# Remover certificado antigo
$oldCerts = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq $certFriendly }
if ($oldCerts) { $oldCerts | ForEach-Object { Remove-Item "Cert:\LocalMachine\My\$($_.Thumbprint)" -Force } }

# Criar novo certificado self-signed
$cert = New-SelfSignedCertificate -DnsName $hostname -CertStoreLocation "Cert:\LocalMachine\My" -FriendlyName $certFriendly

# Adicionar ao Trusted Root
$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
$rootStore.Open("ReadWrite")
$rootStore.Add($cert)
$rootStore.Close()

# =========================
# Binding HTTPS (443)
# =========================
$bindingExists = Get-WebBinding -Name $siteName -Protocol "https" -ErrorAction SilentlyContinue
if ($bindingExists) { Remove-WebBinding -Name $siteName -Protocol "https" }
New-WebBinding -Name $siteName -Protocol "https" -Port 443 -IPAddress "*" -HostHeader $hostname

# Associar certificado
$certThumb = $cert.Thumbprint
$sslPath = "IIS:\SslBindings\0.0.0.0!443!$hostname"
if (Test-Path $sslPath) { Remove-Item $sslPath -Force }
New-Item -Path $sslPath -Thumbprint $certThumb -SSLFlags 1

# =========================
# Redirecionamento HTTP -> HTTPS via rewrite
# =========================
$rewriteModule = "C:\Windows\System32\inetsrv\rewrite\rewrite.dll"
if (Test-Path $rewriteModule) {
    $rulesPath = "IIS:\Sites\$siteName\system.webServer/rewrite/rules"
    Remove-Item "$rulesPath/*" -Recurse -Force -ErrorAction SilentlyContinue
    Add-WebConfiguration -PSPath "IIS:\Sites\$siteName" -Filter "system.webServer/rewrite/rules/rule[@name='RedirectToHttps']" -Value @{
        name = "RedirectToHttps";
        stopProcessing = "true";
        match = @{url="(.*)"};
        conditions = @{add = @{input="{HTTPS}"; pattern="off"}};
        action = @{type="Redirect"; url="https://{HTTP_HOST}/{R:1}"; redirectType="Permanent"}
    }
} else {
    Write-Warning "Url Rewrite module não encontrado. HTTP -> HTTPS não será configurado."
}

# =========================
# Reiniciar IIS
# =========================
Restart-Service W3SVC -Force

Write-Output "IIS configurado com sucesso. Site HTTP/HTTPS pronto com certificado '$certFriendly'"
