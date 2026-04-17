# holdspeak

在 Ghostty 里一键切 pane + 启动微信语音输入。短按数字键（`1`–`0`）正常输入该数字；**长按同一个键** → 跳转到对应的 Ghostty pane 并在该 pane 触发微信 `Fn` 按住说话，整个动作一气呵成。基于 Karabiner-Elements 和 Hammerspoon 实现。

## 工作原理

- **Karabiner-Elements** 负责键盘事件转换：
  - 短按直接输出数字。
  - `to_delayed_action` 在 200 ms 时异步调用 Hammerspoon 切换 pane。
  - 550 ms 时 `to_if_held_down` 通过 virtual HID 驱动触发 `fn`。此时 pane focus 在 accessibility 层面已经生效，微信按住说话就能在正确的 pane 里开始监听。
- **Hammerspoon** 后台缓存当前 Ghostty tab 的 pane 顺序，暴露 `hammerspoon://auto-speak-focus?index=N` 这个 URL 事件入口。触发它的 shell 命令用 `open -g`，保证 Hammerspoon 不会从 Ghostty 抢焦点。
- 数字 `0` 映射到第 10 号 pane。

## 依赖

- macOS
- [Ghostty](https://ghostty.org)
- [Karabiner-Elements](https://karabiner-elements.pqrs.org)
- [Hammerspoon](https://www.hammerspoon.org)
- 微信 macOS 版，开启 `Fn` 按住说话
- Lua 5.4+（仅用于本地跑 spec 测试）

## 安装

### 1. 装基础 app

```sh
brew install --cask ghostty karabiner-elements hammerspoon
```

微信从 App Store 装，进设置开启**按住 Fn 说话**。

### 2. clone 项目

```sh
git clone https://github.com/JiaoTangXQ/holdspeak.git ~/holdspeak
```

放哪儿都行，下面以 `~/holdspeak` 为例。

### 3. 接入 Hammerspoon

在 `~/.hammerspoon/init.lua` 末尾追加一行：

```lua
dofile(os.getenv("HOME") .. "/holdspeak/hammerspoon/init.lua")
```

菜单栏 Hammerspoon 图标 → **Reload Config**。

### 4. 导入 Karabiner 规则

**方案 A — 新装机器，Karabiner 里还没别的规则**

```sh
cp ~/holdspeak/karabiner/karabiner.json ~/.config/karabiner/karabiner.json
```

Karabiner-Elements 会自动热加载。注意这会覆盖你的 default profile，只适合 Karabiner 全新的情况。

**方案 B — Karabiner 里已经有别的规则**

1. 打开 `~/holdspeak/karabiner/karabiner.json`，复制 `profiles[0].complex_modifications.rules` 里的 10 个 `Auto Speak Digit N` 规则对象。
2. 粘到自己 `~/.config/karabiner/karabiner.json` 的 `profiles[<你用的 profile>].complex_modifications.rules` 数组里。
3. 保存。Karabiner-Elements 会自动热加载。

### 5. 授予系统权限

- **Hammerspoon** — 系统设置 → 隐私与安全性 → 以下两项都要打勾：
  - 辅助功能（Accessibility）
  - 输入监控（Input Monitoring）
- **Karabiner-Elements** — 首次启动按提示批准它的 Virtual HID 驱动。

### 6. 验证

打开 Ghostty，至少分两个 pane。把焦点放到任意非 1 号 pane 上。长按 `1` 大概 1 秒。目标 pane 应该拿到焦点，微信语音气泡应该弹出。说话后松开 `1`，转写内容会落到目标 pane。

## 用法

| 操作 | 行为 |
| --- | --- |
| 短按数字键（< 200 ms） | 正常输入该数字 |
| 长按数字键（≥ 550 ms） | 切到对应 Ghostty pane + 启动微信 `Fn` 语音输入 |
| 松手 | 结束语音输入并提交转写 |

数字 `1`–`9` 对应 pane 1–9，`0` 对应 pane 10。

## 参数调优

想改时序，编辑 `~/.config/karabiner/karabiner.json` 里每条规则的 `parameters` 块：

- `basic.to_if_alone_timeout_milliseconds`（默认 `200`）— 这个时间内松开算 tap，会输出数字。
- `basic.to_delayed_action_delay_milliseconds`（默认 `200`）— 切 pane 的 URL 事件在这个时刻派发，必须小于或等于 alone timeout。
- `basic.to_if_held_down_threshold_milliseconds`（默认 `550`）— `fn` 在这个时刻触发。它与 delay 之间的差值就是留给 pane focus 在 AX 层面生效的时间预算；调小能让语音响应更快，但系统负载高时失败率会上升。

## 关闭/停用

- **临时关** — Karabiner-Elements → Complex Modifications → 把每条 `Auto Speak Digit N` 的开关关掉。
- **本次会话关** — 从菜单栏退出 Hammerspoon 或 Karabiner-Elements。
- **彻底卸载** — 删掉 `~/.hammerspoon/init.lua` 里那行 `dofile(...)`，并从 `~/.config/karabiner/karabiner.json` 删掉 10 条规则。

## 文件清单

- `hammerspoon/init.lua` — 加载器和运行时配置
- `hammerspoon/ghostty_remote.lua` — pane 缓存运行时 + URL 事件入口
- `hammerspoon/lib/ghostty.lua` — Ghostty 的 AppleScript bridge
- `hammerspoon/lib/karabiner_rules.lua` — Karabiner 规则生成器
- `hammerspoon/lib/pane_cache.lua` — pane 缓存签名和查找
- `hammerspoon/lib/pane_discovery.lua` — 当前焦点 pane 的 frame 探测和排序
- `karabiner/karabiner.json` — 包含 10 条规则的 Karabiner-Elements 参考配置

## 开发

```sh
lua scripts/run_lua_specs.lua                                                # 跑 Lua spec
find hammerspoon spec scripts -name '*.lua' -print0 | xargs -0 -n1 luac -p   # Lua 语法校验
```

## 已知限制

- Pane discovery 依赖 Ghostty 的 accessibility 暴露方式，如果 Ghostty 改了 AX 布局，可能需要重新调整。
- pane 布局刚变完（新开/关掉 pane）的瞬间，第一次长按可能会落空，需要等后台缓存刷新完成。
- Karabiner-Elements 的 `shell_command` 是异步派发，不会等它返回再触发同一 `to_*` 数组里的后续事件。这正是本项目把 pane 切换放进 `to_delayed_action` 并且**早于 hold 阈值**的原因，而不是和 `fn` 一起塞进 `to_if_held_down`。
- 通过 `hs.eventtap` 合成的 `fn` 事件不会被微信按住说话识别，只有经 Karabiner Virtual HID 驱动发出的 `fn` 才有效。因此这个项目绕不开 Karabiner-Elements。

## 致谢

感谢 [linux.do](https://linux.do/) 社区。这个项目的很多想法、思路以及踩坑后的一次次坚持，都源于在社区里看到的讨论、分享和鼓励。没有这个社区的氛围，我大概不会把一个"顺手写写"的小脚本打磨到能公开发布的程度。向每一位在 linux.do 慷慨分享经验的朋友致意。
