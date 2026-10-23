# Unraid Nvidia 驱动插件（简体中文版）

基于 [Unraid 官方 Nvidia Driver 插件](https://github.com/unraid/unraid-nvidia-driver)的中文分支，提供默认简体中文的设置界面、GPU 兼容性说明、安装和下载提示，以及驱动更新通知。驱动分支保留英文名称对照，GPU 型号、驱动版本和命令保持原样。

本分支直接提供简体中文文案，不随 Unraid 的界面语言切换。Unraid 自身和 NVIDIA 工具输出的文字由各自组件决定。

## 安装与更新

将本次修改合并到本仓库的 `master` 分支，并确认对应的 `.txz` 和 `.txz.md5` 发布包已一同提交后，在 Unraid 的“插件 → 安装插件”中粘贴：

```text
https://raw.githubusercontent.com/EEEEgoose/unraid-nvidia-driver-zh/master/nvidia-driver.plg
```

要求：Unraid 6.9.0-beta31 或更新版本，且上游提供与当前内核和 GPU 匹配的驱动。

本分支沿用上游插件名称 `nvidia-driver`、设置路径和驱动缓存，与英文版使用同一个插件位置；请勿将它们当成两个独立插件并行安装。插件页面显示版本 `2026.10.23` 或更新版本后，可在“设置”中打开“Nvidia 驱动”。首次安装驱动后，按安装提示先停用再启用 Docker；更新驱动后，需要重启服务器才能生效。

插件界面包和插件更新来自本仓库。NVIDIA 驱动二进制包和 `versions.json` 仍从 Unraid 上游获取，驱动支持范围由上游和 NVIDIA 决定。切回英文版时，可使用上游的安装地址。

## 中文化范围

- 设置入口、驱动版本选择、分支说明和更新通知设置。
- GPU 兼容性筛选、内核模块支持、推荐来源和加载失败原因。
- 安装、下载、校验、重启提示及自动更新通知。

GPU 兼容性接口保留原有状态码，翻译仅作用于显示文字。

## 从源码构建

在装有 Python 3（包含标准库 `lzma`）的 macOS 或 Linux 上运行：

```bash
bash source/makepkg-unraid.sh
```

脚本读取 `nvidia-driver.plg` 中的版本号，从 `source/usr/local/emhttp/plugins/nvidia-driver/` 打包，并包含仓库中的 `architecture-mapping.json`；不需要先安装插件，也不会编译或安装 NVIDIA 驱动。输出为 `packages/nvidia-driver-<版本>.txz` 和现有安装机制要求的 `.txz.md5`，同时更新 `.plg` 内的 MD5。

发布新版本时，先修改 `.plg` 的版本号和更新说明，再构建，并将源码、`.plg` 及对应的两个发布包文件一起提交。

## 反馈与来源

- 中文版反馈：[Issues](https://github.com/EEEEgoose/unraid-nvidia-driver-zh/issues)
- 上游支持：[Unraid 论坛](https://forums.unraid.net/topic/98978-plugin-nvidia-driver/)
- 保留上游 [GPL-2.0 许可证](LICENSE)。

## 验证状态

本地检查覆盖 Shell、JavaScript、GPU 筛选交互、插件 XML 和发布包内容；GitHub Actions 检查 PHP、Shell、JavaScript 语法及源码构建。实际驱动安装、重启加载和 Unraid 页面显示仍需在 Unraid 服务器上验证。
