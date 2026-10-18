# 发布说明

## 源码仓库

在仓库根目录初始化 Git，检查要提交的内容，再关联你自己的远端仓库。当前工作尚未创建远端、推送或发布 Release。

```sh
git init
git add .
git status --short
git diff --cached --stat
```

提交前确认没有个人照片、GPS 数据、签名材料或设备专属设置。`.gitignore` 排除成品目录、压缩包、Xcode 用户状态及 `local-fixtures/`，但不能代替人工审阅。MIT 的版权声明使用“QLPhoto contributors”，可根据实际权利归属补充作者姓名。

## 二进制

1. 在 `project.yml` 和两个 Info.plist 中同步版本号；主应用与扩展的 `CFBundleVersion` 保持一致。
2. 执行 `bash scripts/build.sh` 和 `bash scripts/check.sh`，按 CONTRIBUTING 中的清单做人工回归。
3. 执行 `bash scripts/package.sh`，产物在 `dist/QLPhoto-Release.zip`。可传入其他已签名应用路径。
4. 公开向其他用户分发前，用维护者自己的 Developer ID 签名、公证并验证。构建脚本只产生本地临时签名，不自动公证、上传或发布。
5. 在发布说明中注明测试过的 macOS、芯片架构、相机格式及已知限制，并为源码版本打 tag。

如要同时支持 Intel 与 Apple Silicon，需在 Xcode 构建配置中生成并验证相应架构；本地直接编译的开发成品可能只包含当前机器架构，不应标为通用二进制。
