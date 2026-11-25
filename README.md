# nvrclip-tools

针对 [yashau/nvrclip](https://github.com/yashau/nvrclip) 的海康威视兼容性修复补丁 + 本人在用的批量导出脚本集合。

## 背景

nvrclip v0.2.2 在较新的海康固件（实测 DS-8608N-K8-V3 / V4.84.017 build 250729）上搜索录像必失败，报错：

```
nvrclip: hikvision search failed: 400 Bad Request
<statusCode>6</statusCode>
<statusString>Invalid XML Content</statusString>
<subStatusCode>badXmlContent</subStatusCode>
```

**根因**：`internal/hikvision/client.go` 的 `searchRequest()` 用 `%08x` 格式化 `time.Now().UnixNano()` 生成 searchID。纳秒时间戳的十六进制约 16 位，而 `%08x` 只保证最少宽度不截断，导致 UUID 第一段有 16 个字符（规范要求 8 个）。新固件会校验 UUID 格式，直接拒绝请求。

**抓包重放验证**：同一请求，畸形 UUID → HTTP 400；仅将 searchID 改回 8 位 → HTTP 200。

详见上游 Issue: [#7](https://github.com/yashau/nvrclip/issues/7)

## 目录结构

```
├── patch/
│   └── 0001-fix-hikvision-searchid-uuid.patch   # 一行修复补丁
├── scripts/
│   ├── batch-export-merge.ps1     # 按日期范围分块导出 + 自动无损拼接成一个视频
│   └── export-hourly-merge.ps1    # 每天指定整点各切 N 秒片段 + 合成一个视频（长任务可断点续跑）
└── docs/
    └── nvrclip-usage.md           # 中文使用说明（含配置文件格式、常见报错对照）
```

## 使用补丁

```bash
git clone https://github.com/yashau/nvrclip
cd nvrclip
git am / git apply /path/to/0001-fix-hikvision-searchid-uuid.patch
go run ./tools/build --version 0.2.2   # 需要 Go 1.26+
```

## 脚本用法速览

批量导出并合并（分块导出，失败只损失一块）：

```powershell
.\batch-export-merge.ps1 -StartDate "2026-11-11" -EndDate "2026-11-13" `
  -DailyFrom "08:00" -DailyTo "18:00" -ChunkMinutes 60
```

每天整点切片合并（适合制作"每日一分钟"式延时记录；支持随时中断重跑续传）：

```powershell
.\export-hourly-merge.ps1 -StartDate "2026-03-10" -EndDate "2026-11-25" `
  -DailyFrom "08:30" -DailyTo "16:30" -Hours "9,10,11,12,13,14,15,16" -ClipSeconds 5
```

详细参数见 [docs/nvrclip-usage.md](docs/nvrclip-usage.md)。

## 依赖

- [nvrclip](https://github.com/yashau/nvrclip)（需应用本补丁才能在新固件海康 NVR 上使用）
- ffmpeg / ffprobe 在 PATH 上
- nvrclip.toml 配置文件（含 NVR 地址与凭据，**请勿提交到任何仓库**）

## 安全提示

- `nvrclip.toml` 含 NVR 登录密码，已在 .gitignore 中排除，请务必不要提交或外传
- 也可用 `password_env` 从环境变量读密码，避免明文落盘
