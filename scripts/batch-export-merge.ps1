# ============================================================
# nvrclip 批量导出 + 自动合并脚本
# 用法示例:
#   .\batch-export-merge.ps1 -StartDate "2026-11-11" -EndDate "2026-11-11" `
#     -DailyFrom "08:00" -DailyTo "18:00" -ChunkMinutes 60 -Channel 工地监控特写
# ============================================================
param(
  [string]$Nvr = "hik-nvr",
  [string]$Channel = "工地监控特写",
  [Parameter(Mandatory=$true)][string]$StartDate,     # 起始日期 "2026-11-11"
  [Parameter(Mandatory=$true)][string]$EndDate,       # 结束日期 "2026-11-13"（含当天）
  [string]$DailyFrom = "00:00",                       # 每天窗口开始
  [string]$DailyTo   = "23:59",                       # 每天窗口结束
  [int]$ChunkMinutes = 60,                            # 每块时长(分钟)
  [string]$OutRoot   = "D:\nvrclip_export",              # 输出根目录（默认 D 盘）
  [string]$WorkRoot  = "D:\nvrclip_work",                # 临时下载目录（每个分块会临时占用约1GB）
  [ValidateSet("copy","exact")][string]$Mode = "copy",
  [switch]$KeepParts                                 # 合并后保留分块文件
)
$ErrorActionPreference = "Stop"
Set-Location "C:\Users\xubin\Desktop"
# 确保 ffmpeg 可用（不依赖系统 PATH 状态）
$env:Path += ';C:\Users\xubin\ffmpeg\ffmpeg-9.1-essentials_build\bin'
$env:NVRCLIP_FFMPEG = 'C:\Users\xubin\ffmpeg\ffmpeg-9.1-essentials_build\bin\ffmpeg.exe'
$ffmpeg = "C:\Users\xubin\ffmpeg\ffmpeg-9.1-essentials_build\bin\ffmpeg.exe"
$partsDir = Join-Path $OutRoot "parts"
New-Item -ItemType Directory -Force -Path $partsDir, $WorkRoot | Out-Null

# ---- 生成分块计划 ----
$start = [datetime]::ParseExact($StartDate, "yyyy-MM-dd", $null)
$end   = [datetime]::ParseExact($EndDate,   "yyyy-MM-dd", $null)
$jobs = New-Object System.Collections.Generic.List[object]
for ($d = $start; $d -le $end; $d = $d.AddDays(1)) {
  $day  = $d.ToString("yyyy-MM-dd")
  $from = [datetime]::ParseExact("$day $DailyFrom", "yyyy-MM-dd HH:mm", $null)
  $to   = [datetime]::ParseExact("$day $DailyTo",   "yyyy-MM-dd HH:mm", $null)
  for ($t = $from; $t -lt $to; $t = $t.AddMinutes($ChunkMinutes)) {
    $cEnd = $t.AddMinutes($ChunkMinutes); if ($cEnd -gt $to) { $cEnd = $to }
    $jobs.Add([pscustomobject]@{ From = $t; To = $cEnd })
  }
}
Write-Host "计划分块数: $($jobs.Count)  (每块 $ChunkMinutes 分钟, 模式 $Mode)" -ForegroundColor Cyan

# ---- 逐块导出 ----
$files = New-Object System.Collections.Generic.List[string]
$i = 0
foreach ($j in $jobs) {
  $i++
  Write-Host "[$i/$($jobs.Count)] 导出 $($j.From.ToString('MM-dd HH:mm')) -> $($j.To.ToString('HH:mm')) ..." -ForegroundColor Cyan
  try {
    $ErrorActionPreference = "Continue"
    $out = & .\nvrclip.exe grab $Channel --from ($j.From.ToString("yyyy-MM-dd HH:mm")) --to ($j.To.ToString("yyyy-MM-dd HH:mm")) --out $partsDir --work-dir $WorkRoot --mode $Mode 2>&1
    $ErrorActionPreference = "Stop"
    $m = [regex]::Match(($out -join "`n"), "wrote (.+\.mp4)")
    if ($LASTEXITCODE -eq 0 -and $m.Success) {
      $name = Split-Path ($m.Groups[1].Value.Trim()) -Leaf
      $f = Join-Path $partsDir $name
      if (-not (Test-Path $f)) { throw "输出文件未找到: $f" }
      $files.Add($f)
      Write-Host "  OK -> $name" -ForegroundColor Green
    } else {
      Write-Host "  跳过(失败或该时段无录像)" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "  出错跳过: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}
if ($files.Count -eq 0) { Write-Host "没有任何分块成功导出, 结束。" -ForegroundColor Red; exit 1 }

# ---- 合并为一个视频 (无损拼接) ----
$list   = Join-Path $partsDir "concat_list.txt"
$lines = foreach ($f in $files) { "file '" + $f.Replace("'", "''") + "'" }
[System.IO.File]::WriteAllLines($list, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
$merged = Join-Path $OutRoot ("merged_{0}_{1}至{2}.mp4" -f $Channel, $StartDate, $EndDate)
Write-Host "合并 $($files.Count) 个分块 -> $merged" -ForegroundColor Cyan
& $ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i $list -c copy $merged
if ($LASTEXITCODE -ne 0) { Write-Host "ffmpeg 合并失败(各分块编码参数不一致?), 可改用 -Mode exact 重试" -ForegroundColor Red; exit 1 }

if (-not $KeepParts) { Remove-Item $partsDir -Recurse -Force }
$sz = "{0:N1} MB" -f ((Get-Item $merged).Length / 1MB)
Write-Host "完成! $merged  ($sz)" -ForegroundColor Green
