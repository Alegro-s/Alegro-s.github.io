# Публикация портфолио на GitHub и GitHub Pages.
# Запускается ярлыком «Портфолио на GitHub.bat» с рабочего стола.
# Первый запуск: ставит git и GitHub CLI (если их нет), входит в GitHub, создаёт репозиторий и включает Pages.
# Следующие запуски: сохраняют изменения и обновляют сайт.
param([string]$Site = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:GH_PROMPT_DISABLED = ""

function Step($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function Fail($t) { Write-Host ""; Write-Host "Ошибка: $t" -ForegroundColor Red; exit 1 }
function Need($cmd, $id, $name) {
  if (Get-Command $cmd -ErrorAction SilentlyContinue) { return }
  Write-Host "$name не найден, устанавливаю..."
  winget install --id $id -e --accept-source-agreements --accept-package-agreements
  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Fail "$name установлен, но пока не виден. Закройте окно и запустите скрипт ещё раз." }
}

Set-Location $Site

# Ярлык на настоящем рабочем столе (Windows может хранить его не в C:\Users\...\Desktop)
try {
  $desk = [Environment]::GetFolderPath("Desktop")
  $lnk = Join-Path $desk "Портфолио на GitHub.lnk"
  if (-not (Test-Path $lnk)) {
    $sh = New-Object -ComObject WScript.Shell
    $sc = $sh.CreateShortcut($lnk)
    $sc.TargetPath = Join-Path $Site "Опубликовать на GitHub.bat"
    $sc.WorkingDirectory = $Site
    $sc.IconLocation = "shell32.dll,13"
    $sc.Save()
    Write-Host "Ярлык создан на рабочем столе: $desk"
  }
} catch { }
Write-Host "Папка сайта: $Site"

Step "Проверяю git и GitHub CLI"
Need git "Git.Git" "Git"
Need gh "GitHub.cli" "GitHub CLI"

Step "Вход в GitHub"
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Сейчас откроется браузер. Скопируйте код из этого окна и подтвердите вход."
  gh auth login --web --git-protocol https --hostname github.com
  if ($LASTEXITCODE -ne 0) { Fail "не удалось войти в GitHub" }
}
gh auth setup-git 2>&1 | Out-Null
$login = (gh api user --jq .login).Trim()
$uid = (gh api user --jq .id).Trim()
Write-Host "Аккаунт: $login"

# Название репозитория запоминается в github-settings.json
$cfgFile = Join-Path $Site "deploy\github-settings.json"
$repo = ""
if (Test-Path $cfgFile) { $repo = (Get-Content $cfgFile -Raw | ConvertFrom-Json).Repo }
if (-not $repo) {
  $default = "$login.github.io"
  Write-Host ""
  Write-Host "Если назвать репозиторий $default, сайт будет по адресу https://$($default.ToLower())/"
  $ans = Read-Host "Название репозитория (Enter = $default)"
  $repo = if ($ans) { $ans.Trim() } else { $default }
  @{ Repo = $repo } | ConvertTo-Json | Set-Content $cfgFile -Encoding UTF8
}
$full = "$login/$repo"

Step "Готовлю репозиторий $full"
if (-not (Test-Path ".git")) { git init -b main | Out-Null }
if (-not (git config user.name)) { git config user.name $login }
if (-not (git config user.email)) { git config user.email "$uid+$login@users.noreply.github.com" }

gh repo view $full 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  gh repo create $full --public --description "Портфолио: сайты, боты, мобильные приложения" 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { Fail "не удалось создать репозиторий $full" }
}
$url = "https://github.com/$full.git"
if ((git remote) -contains "origin") { git remote set-url origin $url } else { git remote add origin $url }

# Pages из GitHub Actions
gh api -X POST "repos/$full/pages" -f build_type=workflow 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { gh api -X PUT "repos/$full/pages" -f build_type=workflow 2>&1 | Out-Null }

Step "Сохраняю изменения"
git add -A
if (git status --porcelain) {
  git commit -m ("Обновление сайта " + (Get-Date -Format "yyyy-MM-dd HH:mm")) | Out-Null
  Write-Host "Изменения сохранены."
} else {
  Write-Host "Новых изменений нет, просто обновлю сайт."
}
git branch -M main

Step "Отправляю на GitHub"
git push -u origin main 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) {
  Write-Host "В репозитории уже есть чужие коммиты, объединяю..."
  git pull origin main --allow-unrelated-histories --no-edit -X ours 2>&1 | Out-Host
  git push -u origin main 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { Fail "не удалось отправить изменения" }
}

gh api -X POST "repos/$full/pages" -f build_type=workflow 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { gh api -X PUT "repos/$full/pages" -f build_type=workflow 2>&1 | Out-Null }

Step "Публикую сайт"
function LastRun { (gh run list --repo $full --workflow pages.yml --limit 1 --json databaseId --jq ".[0].databaseId" 2>$null) }
Start-Sleep -Seconds 6
$run = LastRun
if (-not $run) { gh workflow run pages.yml --repo $full | Out-Null; Start-Sleep -Seconds 6; $run = LastRun }
gh run watch $run --repo $full --exit-status
if ($LASTEXITCODE -ne 0) {
  Write-Host "Первая сборка не прошла, запускаю ещё раз (так бывает, пока Pages включается)..."
  gh workflow run pages.yml --repo $full | Out-Null
  Start-Sleep -Seconds 8
  $run = LastRun
  gh run watch $run --repo $full --exit-status
  if ($LASTEXITCODE -ne 0) { Fail "сборка не прошла. Подробности: https://github.com/$full/actions" }
}

$pageUrl = (gh api "repos/$full/pages" --jq .html_url 2>$null)
if (-not $pageUrl) { $pageUrl = "https://$($login.ToLower()).github.io/" }
Write-Host ""
Write-Host "Готово! Сайт: $pageUrl" -ForegroundColor Green
Write-Host "Код: https://github.com/$full"
Start-Process $pageUrl
