> **Fork 说明** —— 本仓库 fork 自 [mgxv/SwiftType](https://github.com/mgxv/SwiftType)，
> 改动见下方三节。上游未指定许可证，因此本仓库不授予任何使用或再分发权利。
> 英文说明见 [README.md](README.md)。

# SwiftType（fork）

一个 macOS 英语输入法：打字时在光标下方浮出候选栏，提供输入建议、联想输入和拼写纠正，
按数字键选词上屏。全部本地运行，不联网。上游用 Swift 6 + InputMethodKit 编写，
联想输入（下一词预测）基于 KenLM n-gram 模型。

## 本 fork 的改动

### 1. 尾随空格可关，按键分别配置

上屏候选词时默认会补一个尾随空格。本 fork 让它可选 —— `With Trailing Space`（默认）
或 `Without Trailing Space` —— 并且三个提交键各自独立配置：

| 设置项 | 作用于 |
|---|---|
| Return Key | Return |
| Number Keys | 数字键 1–7 选词，含第一格原文 |
| Space Key | 空格键 |

快捷键：**⌥+`**（同时切换空格键和数字键的提交行为），可在
*Settings → General → Toggle Shortcut* 重绑。

为什么：在 IDE 里，尾随空格会让自动补全菜单失效。

### 2. 菜单挪进输入源菜单

设置入口移到 macOS 输入源菜单里，不再单独占一个菜单栏图标。

### 3. `i` 自动大写（尚未打包进 release）

英语下 `i` 上屏为 `I`，缩写 `i'm`、`i'll`、`i've`、`i'd` 同理。

## 安装

**从源码构建**（推荐）：用 Xcode 打开项目构建即可，构建脚本会自动装到
`~/Library/Input Methods/`。然后在 *系统设置 → 键盘 → 输入法* 里添加 SwiftType。

**下载安装包**：见 [Releases](https://github.com/yswnqc/SwiftType/releases)。安装包未签名，
macOS 首次会拦截，需要到 *系统设置 → 隐私与安全性* 点「仍要打开」。
两种方式不要混用 —— 装两份会在键盘设置里出现重复条目。

## 其余文档

用法、主题定制、架构说明等仍以上游英文 README 为准，见 [README.md](README.md) 分割线以下部分。
