# QLPhoto：Agent 工作指南

QLPhoto 是 macOS 照片预览工具，使用 Swift、AppKit、SwiftUI 和系统 Image I/O。主应用通过辅助功能权限接管 Finder 中选中照片时的空格预览；Quick Look 扩展是实验性功能。

## 下载、构建和安装

用户要求安装时，按 [Agent 安装指南](docs/AGENT_INSTALL.md) 执行环境检查、获取源码、构建、安装和启动。普通构建无需 XcodeGen，也无需第三方包管理器。

- 最低部署目标为 macOS 13；构建需要完整 Xcode 和 macOS SDK，只有 Command Line Tools 不够。
- 在仓库根目录运行 `bash scripts/build.sh`，默认产物为 `build/DerivedData/Build/Products/Release/QLPhoto.app`，使用本地临时签名。
- `bash scripts/build.sh --unsigned` 仅用于无需签名的构建检查，不用于本地安装。
- 辅助功能授权由用户在系统设置中完成，不绕过系统安全机制。
- 用户只要求审查或修改代码时，不自行安装、启动、发布或推送。

## 代码入口

| 路径 | 内容 |
| --- | --- |
| `QLPhoto/App/App.swift` | 生命周期、设置、预览窗口和后台加载 |
| `QLPhoto/App/FinderSpace.swift` | Finder 按键、辅助功能读取、导航和窗口定位 |
| `QLPhoto/Sources/Photo.swift` | 图片解码、元数据、直方图和图片交互 |
| `QLPhoto/Sources/HTMLPreview.swift` | 实验性扩展的 HTML 输出 |
| `QLPhoto/Extension/` | Quick Look 扩展 |
| `QLPhoto/Checks/` | 独立 Swift 检查入口 |
| `scripts/` | 构建、检查和打包脚本 |

## 修改约定

- 保持 macOS 13 部署兼容性；更高版本 API 需要可用性判断。
- 修改 target、源文件列表或类型声明时，同步 `QLPhoto/project.yml` 与已提交的 Xcode 工程。
- 图片处理保持在本机；不上传照片、GPS、元数据或键盘事件。不要提交个人照片、证书、密钥和构建产物。
- 实况照片功能目前停用，不因重构顺手启用。
- 不执行发布、签名身份变更或远端推送，除非用户明确要求。

## 验证和反馈

按改动范围验证，具体命令与人工回归见 [CONTRIBUTING.md](CONTRIBUTING.md)。基础检查为 `bash scripts/check.sh`；传入照片才会验证正常照片解码，`--ui` 会显示测试窗口。普通安装不强制运行开发检查；用户明确跳过测试时尊重该要求。汇报时区分构建通过、启动成功和实际 Finder 预览已验证，不把跳过的检查写成通过。

发布流程见 [RELEASING.md](RELEASING.md)，隐私说明见 [SECURITY.md](SECURITY.md)。
