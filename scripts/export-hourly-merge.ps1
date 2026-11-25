# ==================================================================
# 批量导出每天指定整点的 N 秒片段 + 合成一个视频
# 用法(默认=通道2, 每天8:30-16:30, 9~16点整点各5秒, 2026-03-10起):
#   .\export-hourly-merge.ps1 -StartDate "2026-03-10" -EndDate "2026-11-25"
# 可中断重跑: 已完成的片段自动跳过
# ==================================================================
param(
  [Parameter(Mandatory=$true)][string]$StartDate,
  [Parameter(Mandatory=$true)][string]$EndDate,
  [string]$Channel    = "工地监控全景",
  [string]$DailyFrom  = "08:30",
  [string]$DailyTo    = "16:30",
  [string]$Hours      = "9,10,11,12,13,14,15,16",
  [int]$ClipSeconds   = 5,
  [string]$Root       = "E:\gdmp4",
  [switch]$KeepDays                                # 保留每天的全天文件(占空间大, 默认删)
)
$ErrorActionPreference = "Stop"
Set-Location "C:\Users\xubin\Desktop"
$env:Path += ';C:\Users\xubin\ffmpeg\ffmpeg-9.1-essentials_build\bin'
$env:NVRCLIP_FFMPEG = 'C:\Users\xubin\ffmpeg\ffmpeg-9.1-essentials_build\bin\ffmpeg.exe'
$ffmpeg  = "C:\Users\xubin\ffmpeg\ffmpeg-9.1-essentials_build\bin\ffmpeg.exe"
$ffprobe = "C:\Users\xubin\ffmpeg\ffmpeg-9.1-essentials_build\bin\ffprobe.exe"
Start-Transcript -Path (Join-Path $Root "run.log") -Append | Out-Null

$daysDir  = Join-Path $Root "days"
$clipDir  = Join-Path $Root "clips"
$workDir  = Join-Path $Root "work"
New-Item -ItemType Directory -Force -Path $daysDir, $clipDir, $workDir | Out-Null
$csvPath  = Join-Path $Root "progress.csv"
if (-not (Test-Path $csvPath)) { "date,clips_ok,clips_expected,status" | Out-File $csvPath -Encoding UTF8 }

$hourList = $Hours.Split(",") | ForEach-Object { [int]$_.Trim() }
$start = [datetime]::ParseExact($StartDate, "yyyy-MM-dd", $null)
$end   = [datetime]::ParseExact($EndDate,   "yyyy-MM-dd", $null)
$totalDays = ($end - $start).Days + 1
Write-Host ("=== 任务: {0} ~ {1} 共{2}天, 每天{3}~{4} 整点{5}秒, 通道:{6} ===" -f $StartDate,$EndDate,$totalDays,$DailyFrom,$DailyTo,$ClipSeconds,$Channel) -ForegroundColor Cyan

$specs = @{}   # clip -> "WxH|fps"
$dayIdx = 0; $failDays = New-Object System.Collections.Generic.List[string]
for ($d = $start; $d -le $end; $d = $d.AddDays(1)) {
  $dayIdx++
  $date = $d.ToString("yyyy-MM-dd")
  # 已全部完成的日期直接跳过
  $expected = $hourList.Count
  $have = @($hourList | Where-Object { Test-Path (Join-Path $clipDir ("{0}_{1:D2}00.mp4" -f $date, $_)) })
  if ($have.Count -eq $expected) { Write-Host "[$dayIdx/$totalDays] $date 已完成, 跳过"; continue }

  Write-Host "[$dayIdx/$totalDays] $date 导出全天 $DailyFrom~$DailyTo ..." -ForegroundColor Cyan
  # 若上次中断留下了当天文件则复用
  $dayFile = Get-ChildItem $daysDir -Filter "*_$date`_*.mp4" -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $dayFile) {
    $out = & .\nvrclip.exe grab $Channel --from "$date $DailyFrom" --to "$date $DailyTo" --out $daysDir --work-dir $workDir --mode copy 2>&1
    $m = [regex]::Match(($out -join "`n"), "wrote (.+\.mp4)")
    if ($LASTEXITCODE -eq 0 -and $m.Success) {
      $name = Split-Path ($m.Groups[1].Value.Trim()) -Leaf
      $dayFile = Get-Item (Join-Path $daysDir $name)
    }
  }
  if (-not $dayFile) {
    Write-Host "  当天无录像或导出失败, 记录并继续" -ForegroundColor Yellow
    $failDays.Add($date); "$date,0,$expected,day_missing" | Out-File $csvPath -Append -Encoding UTF8; continue
  }

  $ok = 0
  foreach ($h in $hourList) {
    $clipName = "{0}_{1:D2}00.mp4" -f $date, $h
    $clipPath = Join-Path $clipDir $clipName
    if (Test-Path $clipPath) { $ok++; continue }
    $ss = ([datetime]::ParseExact("$date $h`:00", "yyyy-MM-dd H:mm", $null) - [datetime]::ParseExact("$date $DailyFrom", "yyyy-MM-dd H:mm", $null)).TotalSeconds
    try {
      & $ffmpeg -y -hide_banner -loglevel error -ss $ss -t $ClipSeconds -i $dayFile.FullName -an -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p $clipPath 2>$null
      if (-not (Test-Path $clipPath) -or (Get-Item $clipPath).Length -lt 20000) { throw "片段为空(该时刻可能无录像)" }
      $probe = & $ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 $clipPath
      $specs[$clipName] = ($probe -join ",").Trim()
      $ok++
    } catch {
      Write-Host "  $clipName 切片失败: $($_.Exception.Message)" -ForegroundColor Yellow
      if (Test-Path $clipPath) { Remove-Item $clipPath -Force }
    }
  }
  if (-not $KeepDays) { Remove-Item $dayFile.FullName -Force }
  $status = if ($ok -eq $expected) { "ok" } else { "partial" }
  Write-Host "  完成: $ok/$expected 个整点片段" -ForegroundColor Green
  "$date,$ok,$expected,$status" | Out-File $csvPath -Append -Encoding UTF8
}

# ================= 合并 =================
Write-Host "=== 合并所有片段 ===" -ForegroundColor Cyan
$allClips = Get-ChildItem $clipDir -Filter *.mp4 | Sort-Object Name
if ($allClips.Count -eq 0) { Write-Host "没有任何片段, 结束" -ForegroundColor Red; Stop-Transcript; exit 1 }
# 探测各片段参数是否一致(相机中途改过分辨率/帧率则需重编码拼接)
foreach ($c in $allClips) {
  if (-not $specs.ContainsKey($c.Name)) {
    $probe = & $ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 $c.FullName
    $specs[$c.Name] = ($probe -join ",").Trim()
  }
}
$uniform = (($specs.Values | Select-Object -Unique).Count -eq 1)
$list = Join-Path $Root "concat_list.txt"
$lines = foreach ($c in $allClips) { "file '" + $c.FullName.Replace("'","''") + "'" }
[System.IO.File]::WriteAllLines($list, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
$merged = Join-Path $Root ("merged_{0}_整点{1}s_{2}至{3}.mp4" -f $Channel,$ClipSeconds,$StartDate,$EndDate)
Write-Host ("合并 {0} 个片段 -> {1} (参数一致:{2})" -f $allClips.Count, $merged, $uniform)
if ($uniform) {
  & $ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i $list -c copy $merged
} else {
  Write-Host "片段参数不一致, 拼接时重编码(较慢)..." -ForegroundColor Yellow
  & $ffmpeg -y -hide_banner -f concat -safe 0 -i $list -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p $merged 2>$null
}
if ($LASTEXITCODE -eq 0 -and (Test-Path $merged)) {
  $sz = "{0:N2} GB" -f ((Get-Item $merged).Length / 1GB)
  Write-Host "全部完成! $merged ($sz)" -ForegroundColor Green
  Write-Host ("统计: 片段{0}个, 缺录像日期{1}天: {2}" -f $allClips.Count, $failDays.Count, ($failDays -join ",")) -ForegroundColor Green
} else {
  Write-Host "合并失败, 请检查 run.log" -ForegroundColor Red
}
Remove-Item $list -Force -ErrorAction SilentlyContinue
Stop-Transcript | Out-Null
