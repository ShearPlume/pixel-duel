# 格斗角色帧带流水线

把「一句角色描述」变成 Godot 能用的像素精灵图集。改编自 `hatch-pet-claude`，改动点：

- 状态表换成格斗用的 9 个状态（待机/走/后退/蹲/跳/轻拳/重拳/踢/受击）
- **按脚底 + 身体中轴锚点对齐**，出拳时身体不会再横向漂移（原版按整体质心居中）
- 每状态独立 `fps`，和图集一起输出 `atlas.json`，方便 Godot 直接建 `SpriteFrames`
- HTTP 支持走企业代理

## 0. 环境（已就绪）

```powershell
py -3 --version                       # Python 3.12
py -3 -m pip list | Select-String "Pillow|numpy|httpx"
```

依赖已经装好。装新依赖请用国内镜像（企业代理在 pip 里解析不了 DNS）：

```powershell
py -3 -m pip install -i https://pypi.tuna.tsinghua.edu.cn/simple <包名>
```

## 1. 配置 API

在工程根目录（或角色目录）建 `.env`：

```ini
FIGHTER_API_KEY=sk-xxxx
FIGHTER_BASE_URL=https://api.openai.com
FIGHTER_MODEL=gpt-image-2
FIGHTER_QUALITY=medium
# 需要代理时打开（可选）
# FIGHTER_PROXY=http://proxysg-blz.huawei.com:8080
```

只有 `gpt-image-2` 能在一张图里排对多帧，Flux/Stable Diffusion 之类的不要用。

## 2. 建角色目录

```powershell
mkdir art-src\my-fighter
copy tools\frames\template.char.json art-src\my-fighter\char.json
notepad art-src\my-fighter\char.json
```

`char.json` 里只有 `description` 需要认真写——它决定角色长什么样，写得越具体越好（发型、服装、配色、武器、体型）。想基于现成图生成，就把参考图放成 `art-src\my-fighter\reference.png`。

## 3. 三步出图

```powershell
# ① 准备布局图和提示词（免费，不调 API）
py -3 tools\frames\prepare.py art-src\my-fighter

# ② 先花最少的钱确认角色形象
py -3 tools\frames\generate.py art-src\my-fighter --preview
#    看一眼 art-src\my-fighter\.frames\generated\base.png，满意再继续

# ③ 生成全部帧带 + 切图
py -3 tools\frames\generate.py art-src\my-fighter
py -3 tools\frames\extract.py art-src\my-fighter
```

不想花钱也能验证后半段：把 9 张条带 PNG 手动丢进
`art-src\my-fighter\.frames\generated\<状态名>.png`，直接跑第 ③ 步的 `extract.py`。

## 4. 产物

```
art-src/my-fighter/
├── char.json
├── spritesheet.png        1536x1872，8 列 x 9 行，单格 192x208，透明底
├── spritesheet.webp
├── atlas.json             每状态的 row / frames / fps + 锚点
├── frames/<状态>/NN.png   单帧，已按脚底对齐
├── previews/<状态>.gif    快速看动画
└── .frames/               中间文件（提示词、布局图、原始条带，可删）
```

`atlas.json` 长这样：

```json
{
  "cell": [192, 208],
  "columns": 8,
  "anchor": [96, 196],
  "image": "spritesheet.png",
  "states": [
    {"name": "idle", "row": 0, "frames": 6, "fps": 10},
    {"name": "attack-light", "row": 5, "frames": 4, "fps": 30}
  ]
}
```

`anchor` 是格子里的「脚底中心点」，Godot 里给 `Sprite2D.offset` 或
`AnimatedSprite2D.offset` 用（`offset = anchor - cell/2`），角色根部就落在脚上。

## 5. 费用

1 张基准图 + 8 条帧带（走/后退共用一条，镜像生成）：

| 质量 | 总价 |
| --- | --- |
| low | 约 $0.12 |
| medium（默认） | 约 $0.44（≈¥3） |
| high | 约 $1.77 |

## 6. 常见问题

| 现象 | 处理 |
| --- | --- |
| 角色帧间左右晃 | 提高 `extract.py` 的 `LEG_BAND`（默认 0.35）让锚点更靠下，或删掉该条带重生成 |
| 抠图残留紫边 | `remove_chroma` 的 `threshold` 从 140 调大 |
| 帧太少/多 | 该条带两侧角色粘连了，加宽布局图（`prepare.py` 的 `STRIP_SIZES`）或重生成该状态 |
| 某一状态失败 | 删掉 `.frames\generated\<状态>.png` 重跑 `generate.py`，其余会跳过 |
| 想让攻击更快 | 只改 `states.json` 里该状态的 `fps`，再跑一次 `extract.py`（不用重新调 API） |

## 7. 各状态对应的帧数据

`states.json` 里的 `fps` 要和 Godot 侧的帧数据对齐，例如：

- `attack-light` 4 帧 @30fps ≈ 0.13s，接近「4 帧出拳、2 帧判定」的手感
- `attack-heavy` / `kick` 4 帧 @24fps ≈ 0.17s
- `idle` 6 帧 @10fps ≈ 0.6s 的呼吸循环

出拳判定窗口不要用动画时间，用逻辑帧计数器（`atlas.json` 只负责表现）。
