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
$tempPath      = "C:\inetpub\temp"
$certFile      = "$tempPath\tsucert.cer"
$certSubject   = "CN=$hostname"

# Criar pastas se não existirem
foreach ($p in @($sitePath, $virtualPath, $tempPath)) {
    if (!(Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
}

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

# --- REMOVER certificados antigos (My e Root) pelo Subject ---
$stores = @("Cert:\LocalMachine\My","Cert:\LocalMachine\Root")
foreach ($store in $stores) {
    $certs = Get-ChildItem -Path $store -ErrorAction SilentlyContinue | Where-Object { $_.Subject -eq $certSubject }
    foreach ($cert in $certs) {
        Write-Host "Removendo certificado existente:" $cert.Subject "de $store" -ForegroundColor Yellow
        Remove-Item -Path $cert.PSPath -Force
    }
}

# Criar novo certificado self-signed
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
$rootImported = Import-Certificate -FilePath $certFile -CertStoreLocation "Cert:\LocalMachine\Root"
if ($rootImported) { foreach ($c in $rootImported) { $c.FriendlyName = $certFriendly } }

# Associar certificado ao binding HTTPS
$guid = [guid]::NewGuid().ToString()
netsh http delete sslcert ipport=0.0.0.0:443 2>$null
netsh http add sslcert ipport=0.0.0.0:443 certhash=$thumb appid="{$guid}"

#Baixar e instalar o modulo URL Rewrite

# Caminho para salvar o instalador
$installerPath = "C:\Temp\rewrite_x64.msi"

# URL oficial do instalador (MS Download CDN)
$url = "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi"
# Criar pasta se não existir
if (!(Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" | Out-Null
}

# Baixar o instalador
Invoke-WebRequest -Uri $url -OutFile $installerPath

# Instalar silenciosamente
Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait

# Reiniciar IIS
Write-Host "Reiniciando IIS..."
iisreset

Write-Host "✅ Instalação do URL Rewrite concluída"

# --- Criar web.config com URL Rewrite para redirecionamento HTTP -> HTTPS ---
$webConfigPath = "$sitePath\web.config"
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

# Criar regra de redirecionamento HTTP -> HTTPS (URL Rewrite)
$ruleName = "RedirectToHTTPS"
$rewriteSection = "system.webServer/rewrite/rules"

# Limpar regra anterior se existir
Clear-WebConfiguration -Filter $rewriteSection -PSPath "IIS:\Sites\$siteName" -ErrorAction SilentlyContinue

# Criar regra nova
Add-WebConfiguration -PSPath "IIS:\Sites\$siteName" -Filter $rewriteSection -Value @{
    name = $ruleName
    enabled = "true"
    stopProcessing = "true"
} -AtIndex 0

# Adicionar match e action
Set-WebConfigurationProperty -pspath "IIS:\Sites\$siteName" -filter "system.webServer/rewrite/rules/rule[@name='$ruleName']/match" -name "url" -value ".*"
Set-WebConfigurationProperty -pspath "IIS:\Sites\$siteName" -filter "system.webServer/rewrite/rules/rule[@name='$ruleName']/conditions" -name "." -value @{ input="{HTTPS}"; pattern="off" }
Set-WebConfigurationProperty -pspath "IIS:\Sites\$siteName" -filter "system.webServer/rewrite/rules/rule[@name='$ruleName']/action" -name "type" -value "Redirect"
Set-WebConfigurationProperty -pspath "IIS:\Sites\$siteName" -filter "system.webServer/rewrite/rules/rule[@name='$ruleName']/action" -name "url" -value "https://{HTTP_HOST}/{R:1}"
Set-WebConfigurationProperty -pspath "IIS:\Sites\$siteName" -filter "system.webServer/rewrite/rules/rule[@name='$ruleName']/action" -name "redirectType" -value "Permanent"

# Reiniciar IIS
Restart-Service W3SVC -Force

Write-Output "✅ IIS configurado com sucesso. Site disponível em: http://$hostname/ e https://$hostname/"
