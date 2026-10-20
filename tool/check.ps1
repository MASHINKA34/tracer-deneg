<#
.SYNOPSIS
  Проверка всего проекта «Милиончик»: анализ и тесты shared, server и app.

.DESCRIPTION
  По очереди:
    shared - dart pub get, dart analyze --fatal-infos, dart test
    server - dart pub get, dart analyze --fatal-infos,
             тестовый Postgres (deploy/docker-compose.test.yml), dart test,
             тестовый Postgres убирается всегда (down -v)
    app    - flutter pub get, проверка tokens.g.dart (gen_tokens --check),
             flutter analyze --fatal-infos, flutter test (с эталонными скриншотами)
  Упавший шаг не останавливает остальные: в конце - сводка по всем шагам.
  Код выхода 0 - всё зелёное, 1 - хотя бы один шаг упал.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool/check.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testCompose = Join-Path $root 'deploy\docker-compose.test.yml'
$results = New-Object System.Collections.Generic.List[object]
$total = [Diagnostics.Stopwatch]::StartNew()

function Write-Log([string]$Level, [string]$Message) {
  $time = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
  Write-Host ('{0} {1,-5} [check] {2}' -f $time, $Level, $Message)
}

# Запускает внешнюю команду в папке $Dir, пишет в лог старт, итог и время.
# Возвращает $true, если код выхода 0.
# Процесс запускается напрямую (Process.Start): его вывод идёт прямо в консоль
# (или в файл, куда перенаправлен вывод скрипта) без перекодировки PowerShell
# и не смешивается с возвращаемым значением функции.
function Invoke-Step([string]$Name, [string]$Dir, [string]$Exe, [string[]]$Arguments) {
  Write-Log 'INFO' "step '$Name' started: $Exe $($Arguments -join ' ') (in $Dir)"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $code = -1
  try {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command $Exe).Source
    $psi.Arguments = ($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
      }) -join ' '
    $psi.WorkingDirectory = $Dir
    $psi.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($psi)
    $process.WaitForExit()
    $code = $process.ExitCode
  } catch {
    Write-Log 'ERROR' "step '$Name' could not start: $($_.Exception.GetType().FullName): $($_.Exception.Message)"
  }
  $sw.Stop()
  $seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  $ok = ($code -eq 0)
  if ($ok) {
    Write-Log 'INFO' "step '$Name' passed in ${seconds}s"
  } else {
    Write-Log 'ERROR' "step '$Name' FAILED with exit code $code in ${seconds}s"
  }
  $results.Add([pscustomobject]@{ Step = $Name; Result = $(if ($ok) { 'OK' } else { "FAIL (exit $code)" }); Seconds = $seconds })
  return $ok
}

function Add-Skipped([string]$Name, [string]$Reason) {
  Write-Log 'WARN' "step '$Name' skipped: $Reason"
  $results.Add([pscustomobject]@{ Step = $Name; Result = "SKIPPED ($Reason)"; Seconds = 0 })
}

Write-Log 'INFO' "check started root=$root powershell=$($PSVersionTable.PSVersion)"

# Нужные программы - сразу понятная ошибка, если чего-то нет в PATH.
$missing = @()
foreach ($tool in 'dart', 'flutter', 'docker') {
  $cmd = Get-Command $tool -ErrorAction SilentlyContinue
  if ($cmd) { Write-Log 'INFO' "found $tool at $($cmd.Source)" } else { $missing += $tool }
}
if ($missing.Count -gt 0) {
  Write-Log 'ERROR' "not found in PATH: $($missing -join ', '). Flutter: add D:\SDK\flutter\bin to PATH; Docker: start Docker Desktop."
  exit 1
}

# shared
$shared = Join-Path $root 'shared'
[void](Invoke-Step 'shared: pub get' $shared 'dart' @('pub', 'get'))
[void](Invoke-Step 'shared: analyze' $shared 'dart' @('analyze', '--fatal-infos'))
[void](Invoke-Step 'shared: test' $shared 'dart' @('test'))

# server (тесты - против тестового Postgres)
$server = Join-Path $root 'server'
[void](Invoke-Step 'server: pub get' $server 'dart' @('pub', 'get'))
[void](Invoke-Step 'server: analyze' $server 'dart' @('analyze', '--fatal-infos'))
$dbUp = Invoke-Step 'server: test db up' $root 'docker' @('compose', '-f', $testCompose, 'up', '-d', '--wait')
try {
  if ($dbUp) {
    [void](Invoke-Step 'server: test' $server 'dart' @('test'))
  } else {
    Add-Skipped 'server: test' 'test Postgres did not start'
  }
} finally {
  [void](Invoke-Step 'server: test db down' $root 'docker' @('compose', '-f', $testCompose, 'down', '-v'))
}

# app
$app = Join-Path $root 'app'
[void](Invoke-Step 'app: pub get' $app 'flutter' @('pub', 'get'))
# tokens.g.dart должен совпадать с tool/design-tokens.json (руками не правится)
[void](Invoke-Step 'app: tokens up to date' $app 'dart' @('run', 'tool/gen_tokens.dart', '--check'))
[void](Invoke-Step 'app: analyze' $app 'flutter' @('analyze', '--fatal-infos'))
[void](Invoke-Step 'app: test' $app 'flutter' @('test'))

# Сводка
$total.Stop()
$failed = @($results | Where-Object { $_.Result -ne 'OK' })
Write-Host ''
Write-Host ($results | Format-Table -AutoSize | Out-String).TrimEnd()
Write-Host ''
if ($failed.Count -eq 0) {
  Write-Log 'INFO' "ALL GREEN: $($results.Count) steps passed in $([math]::Round($total.Elapsed.TotalSeconds, 1))s"
  exit 0
}
Write-Log 'ERROR' "FAILED: $($failed.Count) of $($results.Count) steps: $(($failed | ForEach-Object { $_.Step }) -join '; ')"
exit 1
