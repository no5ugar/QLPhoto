# 使用 AI Agent 安装 QLPhoto

本指南供能执行本地命令的 AI Agent 使用。用户授权安装后，可完成下载、编译、复制应用及启动；辅助功能授权需要用户手动完成。只要求阅读或审查仓库不代表授权安装。

## 1. 检查环境

确认当前是 macOS 13 或更高版本，并检查 Git、完整 Xcode 和 macOS SDK：

```sh
sw_vers -productVersion
git --version
```

构建脚本在未设置 `DEVELOPER_DIR` 时会优先使用 `/Applications/Xcode.app/Contents/Developer`。在同一个 shell 中使用与构建脚本一致的规则检查工具链：

```sh
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcodebuild -version
xcrun --sdk macosx --show-sdk-path
```

Xcode 安装在其他位置时，将 `DEVELOPER_DIR` 指向该 Xcode 的 `Contents/Developer`，在后续构建命令中沿用。无需修改全局 `xcode-select` 设置。

缺少完整 Xcode、尚未接受许可或未完成首次运行设置时，说明具体缺项，请用户安装并打开 Xcode 完成系统提示后继续。不要自行执行 `sudo`、安装大型开发环境或接受许可。

## 2. 获取源码

已经处于 QLPhoto 源码目录时直接使用当前目录，不重复克隆，不重置或覆盖本地修改。

尚无源码时，使用用户提供或当前托管页面确认的仓库克隆地址，在用户指定目录或一个新的工作目录克隆。不要猜测仓库所有者、地址、版本或 Release 下载链接。下面的 `repo_url` 应由 Agent 先赋值为已确认的真实地址，`checkout_dir` 应为尚不存在的目标路径：

```sh
git clone -- "$repo_url" "$checkout_dir"
cd "$checkout_dir"
```

用户指定 tag 或 commit 时使用该版本；否则使用仓库默认分支，并在结果中报告实际构建的 commit（`git rev-parse HEAD`）。源码压缩包没有 Git 信息时，报告来源与版本信息，不虚构 commit。

## 3. 构建并验证产物

在仓库根目录执行默认 Release 构建：

```sh
bash scripts/build.sh
```

默认产物为 `build/DerivedData/Build/Products/Release/QLPhoto.app`。如果环境设置了 `CONFIGURATION` 或 `DERIVED_DATA_PATH`，以后续脚本输出的真实路径为准。

将 `built_app` 赋值为实际产物的绝对路径，再检查结构、签名和架构：

```sh
test -f "$built_app/Contents/Info.plist"
test -x "$built_app/Contents/MacOS/QLPhoto"
codesign --verify --deep --strict "$built_app"
lipo -archs "$built_app/Contents/MacOS/QLPhoto"
```

任一步失败就先处理错误，不继续安装。默认是本地临时签名，不是 Developer ID 签名或 Apple 公证；不要使用 `--unsigned` 安装，也不要声称本机产物必然同时支持 Intel 和 Apple Silicon。普通安装不要求额外运行开发测试；需要时参考 [贡献指南](../CONTRIBUTING.md)。

## 4. 安装

默认目标是 `/Applications/QLPhoto.app`。目标不可写时，可使用 `~/Applications/QLPhoto.app`，并告知用户实际路径；不要自行提升权限。

从旧名称版本迁移时，先正常退出旧应用，避免两个程序同时处理 Finder 空格。新标识符不自动继承旧偏好和辅助功能授权，需要重新设置；提醒用户更新已有登录项，不自动删除旧应用或其数据。

安装前检查目标是否已存在，以及 QLPhoto 是否正在运行。已有安装时确认它确实是 QLPhoto；遇到名称冲突或归属不明的目录，先向用户确认。需要更新时正常退出旧应用，不强制终止；将旧应用移动到唯一的备份路径，保留到新版本验证完成。复制失败时恢复备份，不留下半安装状态。

将 `installed_app` 赋值为确定的安装绝对路径。仅在旧版本已妥善备份、目标不存在时执行：

```sh
ditto "$built_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
open "$installed_app"
```

验证复制后的签名通过，再启动应用。失败时停止并报告，不覆盖备份。不要自动执行 `sudo`、删除隔离属性、关闭 Gatekeeper 或重置系统隐私权限。

## 5. 引导用户完成授权

请用户执行：

1. 打开“系统设置 → 隐私与安全 → 辅助功能”，允许刚安装的 QLPhoto。
2. 回到 QLPhoto，点击“启用空格预览”。
3. 在 Finder 列表视图选中自己的 JPG、HEIC 或 DNG，按空格确认预览，按 ↑ / ↓ 切换，按空格或 Esc 关闭。

Agent 不能代替用户授予系统权限。用户尚未确认实际预览前，报告“已构建并安装，等待辅助功能授权／Finder 验证”，不要报告完整安装验证通过。不要扫描用户照片目录或上传照片来验证。

## 常见问题

- **提示需要完整 Xcode**：只有 Command Line Tools 不够，检查 `DEVELOPER_DIR` 是否指向完整 Xcode。
- **Swift 编译插件被 Agent 沙箱阻止**：使用 Agent 平台正规的执行审批机制重试；无法取得所需执行权限时报告阻碍，不修改项目来绕过沙箱。
- **更新后空格不生效**：本地临时签名更新可能导致授权失效。请用户在辅助功能设置中移除旧 QLPhoto 条目，重新添加安装后的应用，再启动并启用。
- **macOS 阻止启动**：先记录具体提示，确认来源和签名；如需用户允许，在系统设置的“隐私与安全”中由用户操作，不全局关闭安全保护。
- **特定 DNG 无法预览**：系统 RAW 解码兼容性取决于 macOS 和相机型号，不能仅据此认定安装失败。
- **两个图标都隐藏了**：重新打开安装路径中的 QLPhoto，可恢复设置窗口。

## 卸载或回退

仅在用户要求时执行。先正常退出 QLPhoto，将已确认的安装应用移入废纸篓；如设置过登录项，提醒用户移除。辅助功能条目由用户在系统设置中移除。默认保留偏好设置和备份，不清理无关目录。回退时将先前备份恢复到原安装路径，再启动并检查授权。

## 完成时报告

说明源码来源／版本、构建结果、实际安装路径、签名类型、产物架构、是否已启动，以及尚需用户完成的授权或验证。保留备份时给出其路径。下载、编译或启动任何阶段失败，都如实报告当前完成到哪一步。
