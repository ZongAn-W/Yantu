# 中文字体

Noto Sans SC variable font，来自 Google Fonts 的开源字体仓库：

- 原始文件：https://github.com/google/fonts/blob/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf
- 许可证：同目录 `OFL.txt`（SIL Open Font License 1.1）
- SHA-256：`a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da`

字体随 Flutter 客户端发布，保证中文界面不依赖远程字体服务。不要替换成操作系统专有字体后再分发。

`PlannerSansSC-UI.ttf` 是原字体的 400 字重子集，包含客户端源码中的文字、ASCII 和 GB2312 一级常用汉字。它是 `FontManifest.json` 中唯一的中文启动字体，约 1.1 MB；完整的 17.8 MB 可变字体以普通资源保留，不会阻塞 Web 首帧。Web 首帧后在后台加载完整字体，并通过 `fontFamilyFallback` 和 Flutter 的字体变更通知补全生僻字；下载失败会重试。Windows/Android 在启动时直接从本地资源加载完整字体，保留离线字符覆盖。

界面增加文字后，使用 Python 和 `fonttools` 重新生成并检查子集：

```text
python -m pip install fonttools
python tool/subset-font.py
python tool/subset-font.py --check
```

子集沿用同目录 `OFL.txt`，派生字体名称为 Planner Sans SC UI。完整字体始终保留原始文件与校验值。
