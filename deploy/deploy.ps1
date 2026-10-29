# Выкладка портфолио на сервер. Запуск: двойной клик по deploy.bat
# Нужны встроенные в Windows 10/11 ssh, scp и tar.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$site = Split-Path -Parent $here
$cfgFile = Join-Path $here "deploy-settings.json"

$cfg = @{ Domain = ""; Server = "" }
if (Test-Path $cfgFile) { $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json }

$d = Read-Host "Домен (сейчас: $($cfg.Domain))"; if ($d) { $cfg.Domain = $d.Trim() }
$s = Read-Host "Сервер в виде root@IP (сейчас: $($cfg.Server))"; if ($s) { $cfg.Server = $s.Trim() }
if (-not $cfg.Domain -or -not $cfg.Server) { throw "Нужно указать домен и сервер" }
$cfg | ConvertTo-Json | Set-Content $cfgFile -Encoding UTF8

# Сборка: копия сайта с подставленным доменом
$tmp = Join-Path $env:TEMP "portfolio-build"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $tmp | Out-Null
foreach ($item in "index.html","favicon.svg","og.jpg","robots.txt","img","fonts") {
  Copy-Item (Join-Path $site $item) $tmp -Recurse
}
$index = Join-Path $tmp "index.html"
$html = [IO.File]::ReadAllText($index, [Text.Encoding]::UTF8).Replace("__DOMAIN__", $cfg.Domain)
[IO.File]::WriteAllText($index, $html, (New-Object Text.UTF8Encoding $false))

$archive = Join-Path $env:TEMP "portfolio.tar.gz"
Remove-Item $archive -ErrorAction SilentlyContinue
tar -czf $archive -C $tmp .

Write-Host "Загружаю на $($cfg.Server)..."
ssh $cfg.Server "mkdir -p /opt/portfolio-deploy"
scp $archive "$($cfg.Server):/tmp/portfolio.tar.gz"
scp (Join-Path $here "setup-server.sh") (Join-Path $here "nginx-portfolio.conf") "$($cfg.Server):/opt/portfolio-deploy/"
ssh $cfg.Server "bash /opt/portfolio-deploy/setup-server.sh $($cfg.Domain) /tmp/portfolio.tar.gz"

Remove-Item $tmp -Recurse -Force; Remove-Item $archive
Write-Host "Готово. Откройте https://$($cfg.Domain)"
Read-Host "Нажмите Enter, чтобы закрыть"
