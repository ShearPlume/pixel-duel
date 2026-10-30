# 像素横版格斗（暂名 Pixel Duel）· 初始化说明

单人优先、像素 2D、判定数据驱动的 1v1 横版格斗。本文是工程从零开始时的唯一依据，先读这里再动手。

## 1. 本机环境（不要重新下载引擎）

| 项目 | 值 |
| --- | --- |
| 引擎 | Godot **4.6.3 stable**（标准版，非 .NET） |
| GUI 可执行 | `D:\Users\y00866000\tools\godot-4.6.3\Godot_v4.6.3-stable_win64.exe` |
| 带 stdout 的版本 | `D:\Users\y00866000\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe` |
| 导出模板目录 | `%APPDATA%\Godot\export_templates\4.6.3.stable\` |
| 现有的 Web 静态服务脚本 | `D:\Users\y00866000\tools\godot-4.6.3\serve.js` |

注意：

- 已装的导出模板只有 `web_nothreads_debug.zip` / `web_nothreads_release.zip`。**导出 Windows EXE 前需要补装 Windows 模板**，否则会报缺模板。
- 本机**没有 Python**，有 Node 24（`node -v`）。本地开 HTTP 服务统一用 `serve.js`，不要写 `python -m http.server`。
## 2. 启动方式


```powershell
# 创建工程与主场景之后
& "D:\Users\y00866000\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe" --path C:\Users\y00866000.CHINA\PycharmProjects\pixel-duel

# 首次导入资源（无需开编辑器窗口）
& "D:\Users\y00866000\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe" --headless --editor --path . --import

# 导出网页版并本地试玩
& "D:\Users\y00866000\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe" --headless --path . --export-release "Web" exports/web/index.html
node "D:\Users\y00866000\tools\godot-4.6.3\serve.js" "<工程>\exports\web" 8123
# 打开 http://127.0.0.1:8123/
```

## 3. 范围（M0 只做这些）

- **单人 vs 木桩假人**：假人只 idle、不还手，用于验证手感与判定。
- 1v1，一局 60~99 秒，三局两胜。
- 招式先做 4 个：轻拳 / 重拳 / 踢 / 跳跃攻击，外加防御、蹲、跳。
- AI 后置；局域网后置（协议可参考 v1 的 `lan_network.gd` / `web_lan_network.gd` 的主机权威 + 快照思路）。
- 美术先用占位色块，后续用外部 AI 工具生成后按命名约定替换。

## 4. 技术约定

**分辨率与像素感**

- 内部分辨率 **640×360**，整数倍放大。
- Project Settings：`display/window/size/viewport_width=640`、`viewport_height=360`、`stretch/mode=canvas_items`、`stretch/aspect=keep`。
- 所有贴图 `texture_filter = nearest`；节点位置取整（`snappedf`），避免抖动。

**固定步长逻辑**

- 战斗逻辑固定 **60 Hz**，与渲染解耦。伤害、帧数据只允许在固定步里推进。
- 渲染层只读逻辑状态，绝不反向修改判定。

**判定**

- 一律 **AABB 矩形**，不用物理引擎的碰撞体做伤害判定（确定性、可回放、好联网）。
- 每个招式一份帧数据：`startup / active / recovery / damage / guard / stun / push / hitbox(offset,size) / hitstop`。
- 受击盒按姿态切换：站立 `[0.15, 1.92]`、蹲下只降顶边（给“蹲躲高招/波”留空间）、空中整体上移。
- 数据放 `data/moves/*.tres` 或一个 `moves.json`，程序里不写死数字。

**占位素材命名**（后面换成真实像素图时零改动）

```
art/placeholder/<char>/<state>_<frame>.png     例：art/placeholder/fighter_a/idle_00.png
```

角色块建议 **48×64**，脚底为原点（`offset` 对齐脚中心），这样换素材只改贴图尺寸不用改逻辑。

**状态机**

`idle / walk / crouch / jump / attack_light / attack_heavy / kick / air_attack / guard / hurt / down`，状态切换只由 combat 规则层决定。

## 5. 目录规划

```
pixel-duel/
  project.godot
  scenes/      main.tscn  fight.tscn  fighter.tscn  hud.tscn  dummy.tscn
  scripts/     main.gd  fight.gd  fighter.gd  combat_rules.gd  frames.gd  hud.gd  dummy_ai.gd
  data/        moves.json  characters.json
  art/         placeholder/<char>/*.png
  audio/       sfx/
  exports/     构建产物（git 忽略）
  docs/        设计笔记、判定表、素材来源与许可
  tests/       无头回归脚本（godot --headless --script）
```

## 6. 里程碑

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| M0 | 空工程 + 640×360 像素缩放 + 固定步循环 + 两个色块 | 窗口能开、方块能显示、逻辑 60Hz |
| M1 | 移动 / 跳 / 蹲 / 防御 + 血条与时间条 | 键盘响应即时而顺滑 |
| M2 | 4 招 + 命中/格挡/受击/击退/hitstop + 震屏 | 打击有反馈，帧数据可调 |
| M3 | 木桩假人 + 回合与胜负 + 简单 UI | 能完整打一局 |
| M4 | 替换像素素材 + 音效 | 素材替换不动逻辑 |
| M5 | AI（先规则式，后行为树/状态机） | 假人有攻防意图 |
| M6 | 局域网对战（复用 v1 经验） | 同网段可对战 |

## 7. 可以复用 v1 的经验

- 判定与表现分离、`events` 事件流驱动音效/特效/震屏的做法（v1 `combat.gd` 的 `_emit_event`）。
- 蹲/跳躲波要有**高度带**概念，否则蹲只是动画。
- 帧数据集中成常量或数据文件，别散落在各处。
- 联网走“主机权威模拟 + 快照下发”，客机只渲染。
- 踩过的坑：动画时间与判定时间绑在一起后，任何提速都会让判定和画面错位——2D 里要让帧数据成为唯一时间源。

## 8. 待定（开工前拍板）

1. 分辨率 640×360 还是 480×270？
2. 角色朝向：翻转 sprite（`flip_h`）还是左右各一套贴图？
3. 血条/时间条用 Godot Control 还是自己画（像素对齐更好）？

## 9. 素材与许可

- 占位阶段不涉及第三方素材。
- 后续引入 CC0/CC-BY 像素素材时，逐条记录到 `docs/ASSET-SOURCES.md`（来源、作者、许可、原始链接）。
