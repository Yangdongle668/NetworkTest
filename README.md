# NetworkTest

VPS 大陆线路检测与测速脚本（Linux / Bash）。一个脚本回答一个问题：**这台 VPS 是通过什么线路接入中国大陆的，质量如何？**

## 功能

- **回程线路检测** — 自动判定到三网回程线路：CN2 GIA / CN2 GT / 电信 163 / 联通 9929 / 联通 4837 / 移动 CMI / CMIN2，并识别 NTT、Cogent 等第三方绕行
- **全国延迟测试** — 全国 12 城 × 三网共 36 节点并发 ping，按运营商汇总
- **全国测速** — 大陆三网 Speedtest 节点上传/下载测速
- **全球测速** — 亚太/欧洲/北美主要城市测速

四个功能集成在一个脚本，交互式菜单选择，也支持命令行参数免交互运行。

## 快速开始

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Yangdongle668/NetworkTest/main/networktest.sh)
```

或下载后运行：

```bash
curl -fsSL -O https://raw.githubusercontent.com/Yangdongle668/NetworkTest/main/networktest.sh
sudo bash networktest.sh
```

常用参数：

```bash
bash networktest.sh --route                      # 只做回程线路检测 (~2 分钟)
bash networktest.sh --ping                       # 全国延迟测试
bash networktest.sh -a --fast --yes --output report.txt   # 全面测试(精简)并保存报告
```

## 文档

- [使用文档](docs/使用文档.md) — 安装、参数、结果解读、常见问题
- [需求文档](docs/需求文档-VPS大陆线路检测与测速脚本.md) — 设计与需求分析

## 环境要求

- Linux（Debian / Ubuntu / CentOS / Alma / Rocky 等），amd64 或 arm64
- 建议 root 运行（自动安装 curl / jq / ping / traceroute 依赖）
- 测速功能会消耗真实流量，计费流量的机器建议使用 `--fast`
