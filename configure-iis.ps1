# configure-iis.ps1
# ========================================
# Script para configurar IIS + site + app pool + virtual directory
# Provisionado via Terraform CustomScriptExtension
# ========================================

# Instala IIS
Install-WindowsFeature -Name Web-Server -IncludeManagementTools -Verbose

# Caminho do site
$sitePath = 'C:\inetpub\wwwroot\techspeedup'
New-Item -Path $sitePath -ItemType Directory -Force | Out-Null

# Importa módulo de administração IIS
Import-Module WebAdministration

# Cria App Pool
if (-not (Get-WebAppPoolState -Name 'TsuAppPool' -ErrorAction SilentlyContinue)) {
    New-WebAppPool -Name 'TsuAppPool'
}

# Cria Website (remove se existir)
if (Test-Path IIS:\Sites\TsuSite) { 
    Remove-Item IIS:\Sites\TsuSite -Recurse -Force 
}
New-Website -Name 'TsuSite' -Port 80 -PhysicalPath $sitePath -ApplicationPool 'TsuAppPool'

# Cria Virtual Directory
$vdirPhysical = Join-Path $sitePath 'vdir'
New-Item -Path $vdirPhysical -ItemType Directory -Force | Out-Null
New-WebVirtualDirectory -Site 'TsuSite' -Name 'tsuiis' -PhysicalPath $vdirPhysical -Force

# Cria index.html
$indexContent = @'
<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Visual IIS Demo</title>
  <style>
    body{font-family:Inter,Segoe UI,Arial;background:linear-gradient(135deg,#1f4037,#99f2c8);margin:0;color:#fff}
    .card{max-width:900px;margin:6vh auto;background:rgba(0,0,0,0.18);padding:32px;border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,0.2)}
    h1{margin:0 0 12px;font-size:2.4rem}
    p{opacity:0.95}
    .buttons{margin-top:20px}
    .btn{display:inline-block;padding:10px 18px;border-radius:8px;background:rgba(255,255,255,0.12);color:#fff;text-decoration:none;margin-right:10px}
    footer{margin-top:24px;font-size:0.9rem;opacity:0.9}
  </style>
</head>
<body>
  <div class="card">
    <h1>Bem Vindos ao TechSpeedUP de IIS</h1>
    <p>Este é um exemplo de site estático provisionado via Terraform + VM Extension.</p>
    <div class="buttons">
      <a class="btn" href="/">Home</a>
      <a class="btn" href="/tsuiis/info.txt">Info (virtual dir)</a>
    </div>
    <footer>Provisionado via Terraform • Visual demo</footer>
  </div>
</body>
</html>
'@

$indexPath = Join-Path $sitePath 'index.html'
$indexContent | Out-File -FilePath $indexPath -Encoding utf8 -Force

# Arquivo no virtual directory
'Este é o conteúdo do virtual directory (tsuiis).' | Out-File -FilePath (Join-Path $vdirPhysical 'info.txt') -Encoding utf8 -Force

# Reinicia o IIS
Restart-Service W3SVC -Force

Write-Output 'IIS site e virtual directory criados com sucesso.'
