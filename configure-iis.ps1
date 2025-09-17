# Instalar IIS
Install-WindowsFeature -name Web-Server -IncludeManagementTools

# Variáveis
$siteName      = "TsuSite"
$appPoolName   = "TsuPool"
$sitePath      = "C:\inetpub\wwwroot\techspeedup"
$virtualDir    = "TsuDir"
$virtualPath   = "C:\inetpub\wwwroot\techspeedup\tsudir"

# Criar pastas se não existirem
if (!(Test-Path $sitePath)) {
    New-Item -Path $sitePath -ItemType Directory -Force
}

if (!(Test-Path $virtualPath)) {
    New-Item -Path $virtualPath -ItemType Directory -Force
}

# Criar App Pool
Import-Module WebAdministration
if (!(Get-WebAppPoolState -Name $appPoolName -ErrorAction SilentlyContinue)) {
    New-WebAppPool -Name $appPoolName
}
Set-ItemProperty IIS:\AppPools\$appPoolName -Name managedRuntimeVersion -Value "v4.0"
Set-ItemProperty IIS:\AppPools\$appPoolName -Name processModel.identityType -Value ApplicationPoolIdentity

# Criar Website
if (!(Get-Website | Where-Object { $_.Name -eq $siteName })) {
    New-Website -Name $siteName -Port 80 -PhysicalPath $sitePath -ApplicationPool $appPoolName -Force
} else {
    Set-ItemProperty IIS:\Sites\$siteName -Name applicationPool -Value $appPoolName
    Set-ItemProperty IIS:\Sites\$siteName -Name physicalPath -Value $sitePath
}

# Criar Virtual Directory
if (!(Get-WebVirtualDirectory -Site $siteName -Name $virtualDir -ErrorAction SilentlyContinue)) {
    New-WebVirtualDirectory -Site $siteName -Name $virtualDir -PhysicalPath $virtualPath -ApplicationPool $appPoolName
}

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
    <h1>Bem Vindos ao TechSpeedUP de IIS-v2!</h1>
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
    <h1>Virtual Directory Funcionando!</h1>
    <p>Conteúdo servido a partir de: $virtualPath</p>
</body>
</html>
"@ | Out-File "$virtualPath\index.html" -Encoding utf8 -Force

Write-Output "IIS configurado com sucesso. Site: http://localhost/"

