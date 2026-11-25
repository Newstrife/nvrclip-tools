# nvrclip 使用说明

> 从 NVR（大华/海康）录像中导出精确的 MP4 视频片段，无需厂商客户端（iVMS / SmartPSS 等）。
> 本机已部署：修补版 `nvrclip.exe` + ffmpeg 9.1（均已就绪）。

---

## 一、基本用法（你的环境）

打开 PowerShell，进入目录：

```powershell
cd C:\Users\xubin\Desktop
```

你的配置里有 2 个通道别名（在 `nvrclip.toml` 中定义）：

| 通道号 | 别名 |
|---|---|
| 1 | 工地监控特写 |
| 2 | 工地监控全景 |

### 1. 按起止时间导出

```powershell
.\nvrclip.exe grab 工地监控特写 --from "2026-11-11 11:00" --to "2026-11-11 11:05"
```

输出：`clip_2026-11-11_1100-1105.mp4`

### 2. 以某时刻为中心，取前后各 N 分钟

```powershell
.\nvrclip.exe grab 工地监控特写 --around "2026-11-11 11:05" --minutes 30
```

= 导出 10:50 ~ 11:20，共 30 分钟。

### 3. 用「NVR名 + 通道」的完整写法（grab 的等价形式）

```powershell
.\nvrclip.exe download hik-nvr --channel 工地监控全景 --from "2026-11-11 14:00" --to "2026-11-11 14:10"
.\nvrclip.exe download hik-nvr --channel 1 --from "2026-11-11 14:00" --to "2026-11-11 14:10"
```

> `grab` 适合通道别名在所有 NVR 中不重名的情况（你只有一个 NVR，用 grab 即可）。
> 两个别名重名或想用通道号时，用 `download`。

---

## 二、常用参数

| 参数 | 说明 | 示例 |
|---|---|---|
| `--from` / `--to` | 起止时间（与 `--around` 二选一） | `--from "2026-11-11 11:00" --to "2026-11-11 11:05"` |
| `--around` + `--minutes` | 中心时刻 + 总时长（分钟） | `--around "2026-11-11 11:05" --minutes 30` |
| `--mode copy\|exact` | **copy**（默认）：流复制，速度快，切点对齐关键帧<br>**exact**：H.264 重编码，切点精确到帧 | `--mode exact` |
| `--out dir` | 输出目录（默认当前目录） | `--out D:\export` |
| `--keep-temp` | 保留下载的临时文件（调试用） | |
| `--download-only` | 只下载 NVR 原始段，不生成 MP4（配合 `--keep-temp`） | |
| `--no-time-offset` | 不做 NVR 时钟校准，按原始时间请求 | |
| `--config path` | 指定其他配置文件（默认 `nvrclip.toml`） | `--config D:\other.toml` |
| `--work-dir dir` | 指定临时工作目录 | |

**copy 和 exact 怎么选？**
- 日常导出用默认 `copy`：速度快、无画质损失，5 分钟片段秒级~分钟级完成。
- 切点必须精确到帧、或片段跨多个录像文件拼接有花屏时，用 `--mode exact`（会重编码，慢）。

---

## 三、批量导出 + 自动合并（推荐：桌面一键脚本）

**`batch-export-merge.ps1`**（桌面上）：按天 × 时间窗口自动分块导出，全部完成后用 ffmpeg **无损拼接成一个视频**：

```powershell
# 例：导出 11-11 到 11-13 每天 08:00~18:00，每块 60 分钟，合并成一个视频
.\batch-export-merge.ps1 -StartDate "2026-11-11" -EndDate "2026-11-13" `
  -DailyFrom "08:00" -DailyTo "18:00" -ChunkMinutes 60
```

| 参数 | 默认 | 说明 |
|---|---|---|
| -StartDate / -EndDate | 必填 | 日期范围（含当天），格式 "2026-11-11" |
| -DailyFrom / -DailyTo | 00:00 / 23:59 | 每天只导这个时段（跨夜连续时段就填宽一点） |
| -ChunkMinutes | 60 | 每块分钟数；某块失败不影响其他块 |
| -Channel | 工地监控特写 | 通道别名 |
| -Mode | copy | copy=快速无损；exact=重编码帧精确（分块拼接更顺滑） |
| -OutRoot | D:\nvrclip_export | 输出目录 |
| -KeepParts | 不保留 | 加上则合并后保留各分块文件 |

- 输出：`D:\nvrclip_export\merged_通道_起日期至止日期.mp4`
- 临时下载目录在 `D:\nvrclip_work`（每块会临时占用约 1GB，自动清理）
- **C 盘只剩少量空间**，所以默认全部走 D 盘，请勿改回 C 盘

---

## 四、NVR 时钟校准（自动，无需配置）

nvrclip 每次执行时会读取 NVR 时钟并与电脑时钟对比，算出偏差并自动修正。
例如 NVR 慢 1 小时，你请求 14:00，发给 NVR 的实际是 13:00，输出文件名仍用 14:00。

- 电脑时钟是基准（确保本机时间准确即可）
- 不想校准：加 `--no-time-offset`，或在配置里对该 NVR 设 `auto_time_offset = false`
- 读不到 NVR 时间时命令会直接报错（而不是默默导错时段）

---

## 五、配置文件 `nvrclip.toml`（当前生效内容）

```toml
[hik-nvr]
type = "hikvision"              # 品牌：hikvision / dahua
base_url = "http://192.168.1.100"  # NVR 地址；自签名证书时配 insecure_tls = true
username = "admin"
password = "******"             # 也可用 password_env = "环境变量名"
insecure_tls = true
frame_rate = 25                 # 与 NVR 实际帧率一致，影响精确剪切
timeout = "5m"

[hik-nvr.channels]
1 = "工地监控特写"
2 = "工地监控全景"
```

改配置后无需重启，下次命令直接生效。

---

## 六、工作流程 & 注意事项

**下载机制**：按请求时段搜索录像段 → 从 NVR 下载**完整的录像文件段**（可能远大于目标时长）→ 本地按时间戳精确裁剪 → 拼接成 MP4。
所以：进度条显示的下载量可能比最终文件大很多（如导 5 分钟实际下载了 1GB），属正常现象；最终文件才是裁剪后的。

**注意事项：**
1. 时间格式 `"2026-11-11 14:00"`，跨天要写全日期，如 `"2026-11-10 23:50"` → `"2026-11-11 00:10"`
2. 带空格/中文的别名加引号更稳妥：`grab "工地监控特写"`
3. 导出时段若无录像，会提示找不到片段（不是故障）
4. 临时目录 `nvrclip_temp` 正常会自动清理；异常中断后可手动删除
5. 本机 exe 为修补版（修复了海康新固件 searchID UUID 校验问题，已提 [Issue #7](https://github.com/yashau/nvrclip/issues/7)）。若日后更新官方版，先确认该 bug 已修复再替换
6. 密码明文在 `nvrclip.toml` 里，注意别把该文件外传

---

## 七、常见报错

| 报错 | 原因 | 解决 |
|---|---|---|
| `load config nvrclip.toml: ... cannot find` | 不在 exe 所在目录运行 | 先 `cd C:\Users\xubin\Desktop` |
| `ffmpeg ... not found` / 不是内部命令 | PATH 未生效 | 新开 PowerShell 窗口；或确认 `C:\Users\xubin\ffmpeg\ffmpeg-9.1-essentials_build\bin` 在 PATH |
| `search failed: 400 ... badXmlContent` | 官方原版 exe 的 UUID bug | 用桌面这份修补版（已修复） |
| `measure NVR ... clock offset: EOF` | 连不上 NVR / IP 错 / 网络不通 | 检查 `base_url`、网线/VPN，可加 `--no-time-offset` 试 |
| 认证失败 401 | 账号密码错 | 检查 `nvrclip.toml` 的 username/password |
| 找不到录像片段 | 该时段无录像 / 通道选错 | 确认时间和通道，NVR 里先回放确认有录像 |

---

*生成于 2026-11-25，基于 nvrclip v0.2.2（修补版）+ 官方 README 整理*
