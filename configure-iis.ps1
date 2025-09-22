# --- Instalar IIS ---
Install-WindowsFeature -Name Web-Server -IncludeManagementTools

# --- Variáveis ---
$siteName      = "TsuSite"
$appPoolName   = "TsuPool"
$sitePath      = "C:\inetpub\wwwroot\techspeedup"
$virtualDir    = "TsuDir"
$virtualPath   = "C:\inetpub\wwwroot\techspeedup\tsudir"
$hostname      = "tsusite.local"
$certFriendly  = "IIS TechSpeedUp Cert"
$tempPath      = "C:\inetpub\temp"
$certFile      = "$tempPath\tsucert.cer"
$certSubject   = "CN=$hostname"
$webConfigPath = "$sitePath\web.config"

# --- Criar pastas se não existirem ---
foreach ($p in @($sitePath, $virtualPath, $tempPath)) {
    if (!(Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
}

# --- Importar módulo WebAdministration ---
Import-Module WebAdministration

# --- Criar App Pool ---
if (Get-ChildItem IIS:\AppPools | Where-Object { $_.Name -eq $appPoolName }) {
    Remove-WebAppPool -Name $appPoolName -Confirm:$false
}
New-WebAppPool -Name $appPoolName
Set-ItemProperty IIS:\AppPools\$appPoolName -Name managedRuntimeVersion -Value "v4.0"
Set-ItemProperty IIS:\AppPools\$appPoolName -Name processModel.identityType -Value ApplicationPoolIdentity

# --- Criar Website ---
if (Get-Website | Where-Object { $_.Name -eq $siteName }) {
    Remove-Website -Name $siteName
}
New-Website -Name $siteName -PhysicalPath $sitePath -ApplicationPool $appPoolName -HostHeader $hostname -Port 80

# --- Criar Virtual Directory ---
if (Get-WebVirtualDirectory -Site $siteName -Name $virtualDir -ErrorAction SilentlyContinue) {
    Remove-WebVirtualDirectory -Site $siteName -Name $virtualDir -Confirm:$false
}
New-WebVirtualDirectory -Site $siteName -Name $virtualDir -PhysicalPath $virtualPath -ApplicationPool $appPoolName

# --- Criar páginas HTML ---
@"
<!DOCTYPE html>
<html>
<head>
    <title>TechSpeedUP de IIS</title>
    <style>body { font-family: Arial; background-color: #f0f0f0; text-align: center; padding-top: 50px; } h1 { color: #0078D7; } p { font-size: 18px; }</style>
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

# --- Remover certificados antigos ---
$stores = @("Cert:\LocalMachine\My","Cert:\LocalMachine\Root")
foreach ($store in $stores) {
    $certs = Get-ChildItem -Path $store -ErrorAction SilentlyContinue | Where-Object { $_.Subject -eq $certSubject }
    foreach ($cert in $certs) {
        Write-Host "Removendo certificado existente:" $cert.Subject "de $store" -ForegroundColor Yellow
        Remove-Item -Path $cert.PSPath -Force
    }
}

# --- Criar novo certificado self-signed ---
$cert = New-SelfSignedCertificate -DnsName $hostname -CertStoreLocation "Cert:\LocalMachine\My" -FriendlyName $certFriendly
$thumb = $cert.Thumbprint

# --- Adicionar binding HTTPS ---
if (!(Get-WebBinding -Name $siteName -Protocol "https" -ErrorAction SilentlyContinue)) {
    New-WebBinding -Name $siteName -Protocol https -Port 443 -HostHeader $hostname
}

# --- Exportar certificado para temp ---
$certObj = Get-Item "Cert:\LocalMachine\My\$thumb"
Export-Certificate -Cert $certObj -FilePath $certFile -Force | Out-Null

# --- Importar certificado para Trusted Root ---
$rootImported = Import-Certificate -FilePath $certFile -CertStoreLocation "Cert:\LocalMachine\Root"
if ($rootImported) { foreach ($c in $rootImported) { $c.FriendlyName = $certFriendly } }

# --- Associar certificado ao binding HTTPS ---
$guid = [guid]::NewGuid().ToString()
netsh http delete sslcert ipport=0.0.0.0:443 2>$null
netsh http add sslcert ipport=0.0.0.0:443 certhash=$thumb appid="{$guid}"

# --- Verificar se o módulo URL Rewrite está instalado ---
$rewriteInstalled = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\IIS Extensions\URL Rewrite" -ErrorAction SilentlyContinue
if (-not $rewriteInstalled) {
    Write-Host "Módulo URL Rewrite não encontrado. Instalando..."
    $installerPath = "C:\Temp\rewrite_x64.msi"
    $url = "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi"
    Invoke-WebRequest -Uri $url -OutFile $installerPath
    Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait
    Write-Host "✅ URL Rewrite instalado."
    iisreset
} else {
    Write-Host "✅ URL Rewrite já está instalado."
}

# --- Criar web.config com redirect HTTP -> HTTPS ---
@"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="RedirectToHTTPS" stopProcessing="true">
          <match url="(.*)" />
          <conditions>
            <add input="{HTTPS}" pattern="off" ignoreCase="true" />
          </conditions>
          <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />
        </rule>
      </rules>
    </rewrite>
  </system.webServer>
</configuration>
"@ | Out-File $webConfigPath -Encoding UTF8 -Force

# --- Reiniciar IIS ---
Restart-Service W3SVC -Force

Write-Output "✅ IIS configurado com sucesso. Site disponível em: http://$hostname/ e https://$hostname/"
