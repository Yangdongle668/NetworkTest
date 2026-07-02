#!/usr/bin/env bash
#=======================================================================
# NetworkTest - VPS 大陆线路检测与测速脚本
# 功能: 回程线路检测 / 全国延迟测试 / 全国测速 / 全球测速
# 项目: https://github.com/Yangdongle668/NetworkTest
# 用法: bash networktest.sh            # 交互式菜单
#       bash networktest.sh --route   # 直接执行回程线路检测
#       bash networktest.sh --help    # 查看全部参数
#=======================================================================

VERSION="1.1.0"

#-----------------------------------------------------------------------
# 颜色与输出
#-----------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;36m'; BOLD='\033[1m'; PLAIN='\033[0m'

say()  { echo -e "$@"; }
ok()   { echo -e "${GREEN}[OK]${PLAIN} $*"; }
warn() { echo -e "${YELLOW}[!!]${PLAIN} $*"; }
err()  { echo -e "${RED}[XX]${PLAIN} $*"; }
hr()   { echo -e "${BLUE}------------------------------------------------------------------${PLAIN}"; }
title(){ echo -e "\n${BLUE}==================== $* ====================${PLAIN}"; }

#-----------------------------------------------------------------------
# 全局变量
#-----------------------------------------------------------------------
WORKDIR="$(mktemp -d /tmp/networktest.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT
OUTPUT_FILE=""
FAST_MODE=0
AUTO_YES=0
VERBOSE=0
TEST_IPV6=0
TRACE_CMD=""          # nexttrace / traceroute
SPEEDTEST_BIN=""      # speedtest 可执行文件路径
PING_CONCURRENCY=10   # 延迟测试并发数

#-----------------------------------------------------------------------
# 配置区: 全国延迟测试节点  格式: 地区|运营商|IP
# 节点为各地运营商公共 DNS / 网关地址, 如失效请自行替换
#-----------------------------------------------------------------------
PING_NODES=(
  "北京|电信|219.141.136.12"
  "北京|联通|202.106.50.1"
  "北京|移动|221.179.155.161"
  "上海|电信|202.96.209.133"
  "上海|联通|210.22.97.1"
  "上海|移动|211.136.112.200"
  "广州|电信|58.60.188.222"
  "广州|联通|210.21.196.6"
  "广州|移动|120.196.165.24"
  "成都|电信|61.139.2.69"
  "成都|联通|119.6.6.6"
  "成都|移动|211.137.96.205"
  "杭州|电信|202.101.172.35"
  "杭州|联通|221.12.1.227"
  "杭州|移动|211.140.13.188"
  "南京|电信|218.2.2.2"
  "南京|联通|221.6.4.66"
  "南京|移动|221.131.143.69"
  "武汉|电信|202.103.24.68"
  "武汉|联通|218.104.111.114"
  "武汉|移动|211.137.58.20"
  "郑州|电信|222.88.88.88"
  "郑州|联通|202.102.224.68"
  "郑州|移动|211.138.24.66"
  "西安|电信|218.30.19.40"
  "西安|联通|221.11.1.67"
  "西安|移动|211.137.130.19"
  "重庆|电信|61.128.128.68"
  "重庆|联通|221.5.203.98"
  "重庆|移动|218.201.4.3"
  "沈阳|电信|219.148.204.66"
  "沈阳|联通|202.96.69.38"
  "沈阳|移动|211.137.32.178"
  "长沙|电信|222.246.129.80"
  "长沙|联通|58.20.127.170"
  "长沙|移动|211.142.210.98"
)

#-----------------------------------------------------------------------
# 配置区: 回程线路检测目标  格式: 地区|运营商|IP
#-----------------------------------------------------------------------
ROUTE_NODES=(
  "北京|电信|219.141.136.12"
  "北京|联通|202.106.50.1"
  "北京|移动|221.179.155.161"
  "上海|电信|202.96.209.133"
  "上海|联通|210.22.97.1"
  "上海|移动|211.136.112.200"
  "广州|电信|58.60.188.222"
  "广州|联通|210.21.196.6"
  "广州|移动|120.196.165.24"
)

#-----------------------------------------------------------------------
# 配置区: 测速节点  格式: 来源|标签|后备ID(逗号分隔,可空)|测试数量(可空,默认1)
# 来源三种写法:
#   nearest                          就近节点
#   12345                            固定 server id
#   search:关键词[@国家];关键词2...   运行时查询官方接口取最新节点(推荐)
#     - 多个关键词用 ; 分隔, 依次尝试直到搜到结果
#     - @国家 表示只保留该国家的节点 (避免匹配到 China Telecom Americas 之类的海外节点)
# 搜索结果与后备 ID 组成候选池, 失败自动换下一个候选, 直到凑满"测试数量"
# 标签末尾带 * 的为 --fast 精简模式保留节点 (fast 下每条目只测 1 个)
#-----------------------------------------------------------------------
SPEED_CN_NODES=(
  "search:China Telecom@China;CT5G@China;Telecom@China|电信 *|3633,5396,27594|2"
  "search:China Unicom@China;Unicom@China|联通 *|24447,13704|2"
  "search:China Mobile@China;CMCC@China;Mobile@China|移动 *|25858,4575|2"
)

SPEED_GLOBAL_NODES=(
  "nearest|就近节点 *"
  "search:Hong Kong@Hong Kong|亚太-香港 *"
  "search:Taipei;Taiwan|亚太-台北"
  "search:Tokyo@Japan|亚太-东京 *"
  "search:Singapore@Singapore|亚太-新加坡"
  "search:Seoul@South Korea;Seoul|亚太-首尔"
  "search:Frankfurt@Germany|欧洲-法兰克福 *"
  "search:London@United Kingdom|欧洲-伦敦"
  "search:Amsterdam@Netherlands|欧洲-阿姆斯特丹"
  "search:Los Angeles@United States|北美-洛杉矶 *"
  "search:San Jose@United States|北美-圣何塞"
  "search:New York@United States|北美-纽约"
)

#-----------------------------------------------------------------------
# 环境自检与依赖
#-----------------------------------------------------------------------
get_arch() {
  case "$(uname -m)" in
    x86_64|amd64)   echo "amd64" ;;
    aarch64|arm64)  echo "arm64" ;;
    *) echo "" ;;
  esac
}

detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"
  elif command -v dnf >/dev/null 2>&1; then echo "dnf"
  elif command -v yum >/dev/null 2>&1; then echo "yum"
  else echo ""; fi
}

install_pkg() {
  local pkg="$1" mgr; mgr=$(detect_pkg_mgr)
  [[ $EUID -ne 0 ]] && { warn "非 root, 无法自动安装 $pkg"; return 1; }
  case "$mgr" in
    apt) apt-get install -y -qq "$pkg" >/dev/null 2>&1 ;;
    dnf) dnf install -y -q "$pkg" >/dev/null 2>&1 ;;
    yum) yum install -y -q "$pkg" >/dev/null 2>&1 ;;
    *)   warn "未识别的包管理器, 请手动安装 $pkg"; return 1 ;;
  esac
}

check_deps() {
  title "环境自检"
  [[ $EUID -ne 0 ]] && warn "建议以 root 运行以获得完整功能 (安装依赖/ICMP 追踪)"
  local mgr; mgr=$(detect_pkg_mgr)
  [[ "$mgr" == "apt" && $EUID -eq 0 ]] && apt-get update -qq >/dev/null 2>&1
  # 依赖命令 -> 包名 (apt 与 yum/dnf 包名不同的单独处理)
  local dep pkg
  for dep in curl jq ping traceroute; do
    command -v "$dep" >/dev/null 2>&1 && continue
    case "$dep" in
      ping) [[ "$mgr" == "apt" ]] && pkg="iputils-ping" || pkg="iputils" ;;
      *)    pkg="$dep" ;;
    esac
    say "安装依赖: $pkg ..."
    install_pkg "$pkg" || warn "$pkg 安装失败, 部分功能可能受限"
  done
  ok "基础依赖检查完成"
}

# NextTrace: 带 ASN/地理标注的路由追踪, 优先使用
install_nexttrace() {
  if command -v nexttrace >/dev/null 2>&1; then
    TRACE_CMD="nexttrace"; return 0
  fi
  local arch url dst
  arch=$(get_arch)
  if [[ -z "$arch" ]]; then
    warn "未知架构 $(uname -m), 跳过 NextTrace"; TRACE_CMD="traceroute"; return 1
  fi
  dst="$WORKDIR/nexttrace"
  url="https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${arch}"
  say "下载 NextTrace (${arch}) ..."
  if curl -fsSL --retry 2 --max-time 120 -o "$dst" "$url" && chmod +x "$dst"; then
    TRACE_CMD="$dst"
    ok "NextTrace 就绪"
  else
    warn "NextTrace 下载失败, 降级使用 traceroute (无 ASN 标注, 判定精度降低)"
    TRACE_CMD="traceroute"
  fi
}

# Ookla Speedtest CLI
install_speedtest() {
  if command -v speedtest >/dev/null 2>&1; then
    SPEEDTEST_BIN="speedtest"; return 0
  fi
  [[ -x "$WORKDIR/speedtest" ]] && { SPEEDTEST_BIN="$WORKDIR/speedtest"; return 0; }
  local arch pkgarch url
  arch=$(get_arch)
  case "$arch" in
    amd64) pkgarch="x86_64" ;;
    arm64) pkgarch="aarch64" ;;
    *) err "未知架构, 无法安装 speedtest"; return 1 ;;
  esac
  url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${pkgarch}.tgz"
  say "下载 Speedtest CLI ..."
  if curl -fsSL --retry 2 --max-time 120 -o "$WORKDIR/st.tgz" "$url" \
     && tar -xzf "$WORKDIR/st.tgz" -C "$WORKDIR" speedtest 2>/dev/null; then
    chmod +x "$WORKDIR/speedtest"
    SPEEDTEST_BIN="$WORKDIR/speedtest"
    ok "Speedtest CLI 就绪"
  else
    err "Speedtest CLI 下载失败, 无法测速"
    return 1
  fi
}

confirm_traffic() {
  local hint="$1"
  [[ $AUTO_YES -eq 1 ]] && return 0
  echo -ne "${YELLOW}$hint 是否继续? [y/N]: ${PLAIN}"
  local ans; read -r ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

#-----------------------------------------------------------------------
# 模块: VPS 基本信息
#-----------------------------------------------------------------------
module_info() {
  title "VPS 基本信息"
  local geo ip asn loc isp
  geo=$(curl -fsSL --max-time 10 "http://ip-api.com/json/?fields=query,as,isp,country,regionName,city&lang=zh-CN" 2>/dev/null)
  if [[ -n "$geo" ]] && command -v jq >/dev/null 2>&1; then
    ip=$(echo "$geo"  | jq -r '.query // "未知"')
    asn=$(echo "$geo" | jq -r '.as // "未知"')
    isp=$(echo "$geo" | jq -r '.isp // "未知"')
    loc="$(echo "$geo" | jq -r '.country // ""') $(echo "$geo" | jq -r '.regionName // ""') $(echo "$geo" | jq -r '.city // ""')"
  else
    ip=$(curl -fsSL --max-time 10 https://ifconfig.me 2>/dev/null || echo "未知")
    asn="未知"; isp="未知"; loc="未知"
  fi
  local cc virt
  cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
  virt=$(systemd-detect-virt 2>/dev/null || echo "未知")
  say " 公网 IP   : ${BOLD}${ip}${PLAIN}"
  say " ASN       : ${asn}"
  say " 运营商    : ${isp}"
  say " 位置      : ${loc}"
  say " 虚拟化    : ${virt}"
  say " 拥塞控制  : ${cc}$( [[ "$cc" == "bbr" ]] && echo " (BBR 已启用)" )"
  say " 内核      : $(uname -r)"
}

#-----------------------------------------------------------------------
# 模块: 全国延迟测试 (并发 ping)
#-----------------------------------------------------------------------
ping_one() {
  # $1=索引 $2=地区 $3=运营商 $4=IP  -> 结果写入 $WORKDIR/ping.$1
  local out stats loss avg min max
  out=$(ping -c 10 -i 0.2 -W 1 "$4" 2>/dev/null)
  loss=$(echo "$out" | grep -oE '[0-9.]+% packet loss' | grep -oE '^[0-9.]+')
  stats=$(echo "$out" | grep -oE '= [0-9./]+ ms' | grep -oE '[0-9./]+' | head -1)
  if [[ -n "$stats" ]]; then
    min=$(echo "$stats" | cut -d/ -f1)
    avg=$(echo "$stats" | cut -d/ -f2)
    max=$(echo "$stats" | cut -d/ -f3)
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$2" "$3" "$4" "$avg" "$min" "$max" "${loss:-0}" > "$WORKDIR/ping.$1"
  else
    printf '%s|%s|%s|-|-|-|100\n' "$2" "$3" "$4" > "$WORKDIR/ping.$1"
  fi
}

module_ping() {
  title "全国延迟测试 (三网 ${#PING_NODES[@]} 个节点, 并发执行)"
  rm -f "$WORKDIR"/ping.* 2>/dev/null
  local i=0 node
  for node in "${PING_NODES[@]}"; do
    IFS='|' read -r region isp ip <<< "$node"
    ping_one "$i" "$region" "$isp" "$ip" &
    i=$((i+1))
    # 控制并发
    while [[ $(jobs -rp | wc -l) -ge $PING_CONCURRENCY ]]; do sleep 0.2; done
  done
  wait
  # 汇总输出
  printf "${BOLD} %-8s %-6s %-18s %9s %9s %9s %8s${PLAIN}\n" "地区" "运营商" "IP" "平均(ms)" "最小(ms)" "最大(ms)" "丢包"
  hr
  local isp_filter
  for isp_filter in 电信 联通 移动; do
    local sum=0 cnt=0 j=0 best="" worst="" bestv=999999 worstv=0
    while [[ $j -lt $i ]]; do
      [[ -f "$WORKDIR/ping.$j" ]] || { j=$((j+1)); continue; }
      IFS='|' read -r region isp ip avg min max loss < "$WORKDIR/ping.$j"
      if [[ "$isp" == "$isp_filter" ]]; then
        if [[ "$avg" == "-" ]]; then
          printf " %-8s %-6s %-18s ${RED}%9s %9s %9s %7s%%${PLAIN}\n" "$region" "$isp" "$ip" "超时" "-" "-" "$loss"
        else
          local color=$GREEN
          awk "BEGIN{exit !($avg>=150)}" && color=$YELLOW
          awk "BEGIN{exit !($avg>=250)}" && color=$RED
          printf " %-8s %-6s %-18s ${color}%9s${PLAIN} %9s %9s %7s%%\n" "$region" "$isp" "$ip" "$avg" "$min" "$max" "$loss"
          sum=$(awk "BEGIN{print $sum+$avg}"); cnt=$((cnt+1))
          awk "BEGIN{exit !($avg<$bestv)}"  && { bestv=$avg; best=$region; }
          awk "BEGIN{exit !($avg>$worstv)}" && { worstv=$avg; worst=$region; }
        fi
      fi
      j=$((j+1))
    done
    if [[ $cnt -gt 0 ]]; then
      printf " ${BOLD}%-6s 平均: %s ms | 最优: %s (%s ms) | 最差: %s (%s ms)${PLAIN}\n" \
        "$isp_filter" "$(awk "BEGIN{printf \"%.1f\", $sum/$cnt}")" "$best" "$bestv" "$worst" "$worstv"
    else
      printf " ${BOLD}%-6s 全部超时 (可能禁 ping 或线路异常)${PLAIN}\n" "$isp_filter"
    fi
    hr
  done
}

#-----------------------------------------------------------------------
# 模块: 回程线路识别
#-----------------------------------------------------------------------
run_trace() {
  local ip="$1"
  if [[ "$TRACE_CMD" == "traceroute" ]]; then
    timeout 120 traceroute -n -q 1 -w 2 -m 30 "$ip" 2>/dev/null
  else
    # nexttrace: 每跳一次探测; 输出去除颜色码
    timeout 120 "$TRACE_CMD" -q 1 "$ip" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
  fi
}

# 第三方国际骨干识别
detect_carrier() {
  local trace="$1" carriers=""
  echo "$trace" | grep -qE 'AS2914|ntt\.net'        && carriers+="NTT "
  echo "$trace" | grep -qE 'AS174\b|cogentco'       && carriers+="Cogent "
  echo "$trace" | grep -qE 'AS1299|arelion|telia'   && carriers+="Arelion(Telia) "
  echo "$trace" | grep -qE 'AS3491|pccw'            && carriers+="PCCW "
  echo "$trace" | grep -qE 'AS6453|tata'            && carriers+="Tata "
  echo "$trace" | grep -qE 'AS3356|lumen|level3'    && carriers+="Lumen "
  echo "$trace" | grep -qE 'AS6939|he\.net'         && carriers+="HE "
  echo "$trace" | grep -qE 'AS9002|retn'            && carriers+="RETN "
  echo "$trace" | grep -qE 'AS4637|telstra'         && carriers+="Telstra "
  echo "$trace" | grep -qE 'AS7473|singtel'         && carriers+="Singtel "
  echo "$carriers"
}

# 线路判定规则引擎: 输入 trace 文本与运营商, 输出 "标签|证据"
analyze_route() {
  local trace="$1" isp="$2"
  local label="未知/疑似专线" evidence=""
  local has_5943=0 has_20297=0
  echo "$trace" | grep -qE '(^|[^0-9.])59\.43\.'  && has_5943=1
  echo "$trace" | grep -qE '(^|[^0-9.])202\.97\.' && has_20297=1

  case "$isp" in
    电信)
      if [[ $has_5943 -eq 1 && $has_20297 -eq 0 ]]; then
        label="电信 CN2 GIA (AS4809, 精品线路)"
        evidence=$(echo "$trace" | grep -oE '59\.43\.[0-9]+\.[0-9]+' | head -1)
      elif [[ $has_5943 -eq 1 && $has_20297 -eq 1 ]]; then
        label="电信 CN2 GT (AS4809+AS4134, 半精品)"
        evidence=$(echo "$trace" | grep -oE '59\.43\.[0-9]+\.[0-9]+' | head -1)
      elif [[ $has_20297 -eq 1 ]]; then
        label="电信 163 骨干网 (AS4134, 普通线路)"
        evidence=$(echo "$trace" | grep -oE '202\.97\.[0-9]+\.[0-9]+' | head -1)
      fi
      ;;
    联通)
      if echo "$trace" | grep -qE '(^|[^0-9.])(218\.105\.|210\.51\.)|AS9929'; then
        label="联通 9929 (AS9929, 精品线路)"
        evidence=$(echo "$trace" | grep -oE '(218\.105|210\.51)\.[0-9]+\.[0-9]+' | head -1)
      elif echo "$trace" | grep -qE '(^|[^0-9.])219\.158\.|AS4837'; then
        label="联通 4837 骨干网 (AS4837, 普通线路)"
        evidence=$(echo "$trace" | grep -oE '219\.158\.[0-9]+\.[0-9]+' | head -1)
      fi
      ;;
    移动)
      if echo "$trace" | grep -qE 'AS58807'; then
        label="移动 CMIN2 (AS58807, 精品线路)"
        evidence=$(echo "$trace" | grep -oE 'AS58807' | head -1)
      elif echo "$trace" | grep -qE '(^|[^0-9.])223\.(118|119|120)\.|AS58453'; then
        label="移动 CMI (AS58453, 普通线路)"
        evidence=$(echo "$trace" | grep -oE '223\.(118|119|120)\.[0-9]+\.[0-9]+' | head -1)
      fi
      ;;
  esac
  # 电信目标但途经 CN2 也可能是联通/移动混跑, 保持按目标运营商判定即可
  echo "${label}|${evidence}"
}

module_route() {
  title "回程线路检测 (VPS -> 大陆, 共 ${#ROUTE_NODES[@]} 个目标)"
  say "说明: 此结果为${BOLD}回程${PLAIN}(VPS 到大陆方向)。去程需在大陆侧用 ITDog/ping.pe 等工具验证。\n"
  [[ -z "$TRACE_CMD" ]] && install_nexttrace
  local summary=()
  local node
  for node in "${ROUTE_NODES[@]}"; do
    IFS='|' read -r region isp ip <<< "$node"
    say "${BOLD}>> ${isp}(${region}) ${ip}${PLAIN} 追踪中..."
    local trace result label evidence carriers
    trace=$(run_trace "$ip")
    if [[ -z "$trace" ]]; then
      warn "追踪失败, 跳过"
      summary+=("${isp}(${region})|追踪失败|-")
      continue
    fi
    [[ $VERBOSE -eq 1 ]] && { echo "$trace"; hr; }
    result=$(analyze_route "$trace" "$isp")
    label="${result%%|*}"; evidence="${result##*|}"
    carriers=$(detect_carrier "$trace")
    [[ -n "$carriers" ]] && label+=" [途经: ${carriers% }]"
    if [[ "$label" == 未知* ]]; then
      say "   结论: ${YELLOW}${label}${PLAIN}"
    elif [[ "$label" == *精品* ]]; then
      say "   结论: ${GREEN}${label}${PLAIN} ${evidence:+(证据: $evidence)}"
    else
      say "   结论: ${YELLOW}${label}${PLAIN} ${evidence:+(证据: $evidence)}"
    fi
    summary+=("${isp}(${region})|${label}|${evidence:--}")
  done
  # 汇总
  title "回程线路结论汇总"
  printf "${BOLD} %-14s %-46s %s${PLAIN}\n" "目标" "线路" "证据"
  hr
  local s
  for s in "${summary[@]}"; do
    IFS='|' read -r t l e <<< "$s"
    printf " %-14s %-46s %s\n" "$t" "$l" "$e"
  done
  hr
}

#-----------------------------------------------------------------------
# 模块: 测速 (全国 / 全球共用)
#-----------------------------------------------------------------------
resolve_server_ids() {
  # $1="关键词[@国家];关键词2..."  $2=最多返回几个 id
  # 依次尝试每个关键词, 第一个有结果的关键词返回其节点 id 列表(每行一个)
  local spec="$1" max="${2:-5}" kw country resp ids
  local IFS=';'
  for kw in $spec; do
    unset IFS
    country=""
    [[ "$kw" == *@* ]] && { country="${kw#*@}"; kw="${kw%@*}"; }
    resp=$(curl -fsSL --max-time 10 \
      "https://www.speedtest.net/api/js/servers?engine=js&limit=20&search=$(echo "$kw" | sed 's/ /%20/g')" 2>/dev/null)
    [[ -z "$resp" ]] && continue
    if command -v jq >/dev/null 2>&1; then
      ids=$(echo "$resp" | jq -r --arg c "$country" \
        '.[] | select($c=="" or .country==$c) | .id' 2>/dev/null | head -n "$max")
    else
      # 无 jq 时的降级解析 (不支持国家过滤)
      ids=$(echo "$resp" | grep -oE '"id":"?[0-9]+' | grep -oE '[0-9]+' | head -n "$max")
    fi
    [[ -n "$ids" ]] && { echo "$ids"; return 0; }
  done
  return 1
}

run_speed_one() {
  # $1=server id (或 nearest)  $2=标签
  local id="$1" label="$2" json dl up lat jit loss server
  local args=(--accept-license --accept-gdpr -f json)
  [[ "$id" != "nearest" ]] && args+=(-s "$id")
  json=$(timeout 180 "$SPEEDTEST_BIN" "${args[@]}" 2>/dev/null)
  if [[ -z "$json" ]] || ! echo "$json" | jq -e '.download.bandwidth' >/dev/null 2>&1; then
    # 静默失败, 由调用方决定是否换候选节点重试
    return 1
  fi
  dl=$(echo "$json"  | jq -r '.download.bandwidth' | awk '{printf "%.1f", $1*8/1000000}')
  up=$(echo "$json"  | jq -r '.upload.bandwidth'   | awk '{printf "%.1f", $1*8/1000000}')
  lat=$(echo "$json" | jq -r '.ping.latency'        | awk '{printf "%.1f", $1}')
  jit=$(echo "$json" | jq -r '.ping.jitter'         | awk '{printf "%.1f", $1}')
  loss=$(echo "$json"| jq -r '.packetLoss // 0'     | awk '{printf "%.0f", $1}')
  server=$(echo "$json" | jq -r '"\(.server.name)-\(.server.location)"' | cut -c1-28)
  printf " %-18s ${GREEN}%10s${PLAIN} ${BLUE}%10s${PLAIN} %9s %9s %6s%%  %s\n" \
    "$label" "$dl" "$up" "$lat" "$jit" "$loss" "$server"
}

run_speed_group() {
  # $1=标题  其余=节点数组
  local group_title="$1"; shift
  local nodes=("$@")
  title "$group_title"
  install_speedtest || return 1
  command -v jq >/dev/null 2>&1 || { err "缺少 jq, 无法解析测速结果"; return 1; }
  printf "${BOLD} %-18s %10s %10s %9s %9s %7s  %s${PLAIN}\n" \
    "节点" "下载(Mbps)" "上传(Mbps)" "延迟(ms)" "抖动(ms)" "丢包" "实际服务器"
  hr
  local tested_ids=" " node src label fallback count candidates id success
  for node in "${nodes[@]}"; do
    IFS='|' read -r src label fallback count <<< "$node"
    # --fast 模式只保留带 * 标记的节点, 且每条目只测 1 个
    if [[ $FAST_MODE -eq 1 && "$label" != *\** ]]; then continue; fi
    label="${label% \*}"
    count="${count:-1}"
    [[ $FAST_MODE -eq 1 ]] && count=1

    # 组装候选池: 搜索结果在前, 静态后备 id 在后
    if [[ "$src" == "nearest" ]]; then
      candidates="nearest"
    elif [[ "$src" == search:* ]]; then
      candidates="$(resolve_server_ids "${src#search:}" 8) ${fallback//,/ }"
    else
      candidates="$src ${fallback//,/ }"
    fi
    candidates=$(echo "$candidates" | tr ' \n' '\n\n' | grep -vE '^$')
    if [[ -z "$candidates" ]]; then
      printf " %-18s ${YELLOW}%s${PLAIN}\n" "$label" "未搜到该地区/运营商的测速节点, 已跳过"
      continue
    fi

    # 依次尝试候选, 失败静默换下一个, 直到凑满 count 个成功结果
    success=0
    for id in $candidates; do
      [[ "$tested_ids" == *" $id "* ]] && continue
      tested_ids+="$id "
      run_speed_one "$id" "$label" && success=$((success+1))
      [[ $success -ge $count ]] && break
    done
    if [[ $success -eq 0 ]]; then
      printf " %-18s ${RED}%s${PLAIN}\n" "$label" "全部候选节点测试失败, 已跳过"
    fi
  done
  hr
}

module_speed_cn() {
  confirm_traffic "全国测速将消耗较多流量 (可能 1GB 以上)." || { warn "已取消"; return; }
  run_speed_group "全国测速 (大陆三网)" "${SPEED_CN_NODES[@]}"
  say "提示: 大陆 Speedtest 节点较少且经常下线, 失败节点会自动跳过; 可编辑脚本顶部 SPEED_CN_NODES 更新。"
}

module_speed_global() {
  confirm_traffic "全球测速将消耗较多流量 (可能数 GB)." || { warn "已取消"; return; }
  run_speed_group "全球测速" "${SPEED_GLOBAL_NODES[@]}"
}

#-----------------------------------------------------------------------
# 模块: 全面测试
#-----------------------------------------------------------------------
module_all() {
  local t0; t0=$(date +%s)
  module_info
  module_route
  module_ping
  module_speed_cn
  module_speed_global
  title "全部测试完成"
  say " 总耗时: $(( $(date +%s) - t0 )) 秒"
}

#-----------------------------------------------------------------------
# 菜单与入口
#-----------------------------------------------------------------------
show_menu() {
  echo -e "
${BLUE}========== NetworkTest v${VERSION} 主菜单 ==========${PLAIN}
 ${GREEN}1.${PLAIN} 回程线路检测   ${PLAIN}(判断接入大陆的线路类型)
 ${GREEN}2.${PLAIN} 全国延迟测试   ${PLAIN}(三网各省市 ping 延迟/丢包)
 ${GREEN}3.${PLAIN} 全国测速       ${PLAIN}(大陆三网上传/下载测速)
 ${GREEN}4.${PLAIN} 全球测速       ${PLAIN}(全球主要地区上传/下载测速)
 ${GREEN}5.${PLAIN} 全面测试       ${PLAIN}(依次执行 1-4)
 ${GREEN}0.${PLAIN} 退出
${BLUE}==============================================${PLAIN}"
}

menu_loop() {
  module_info
  while true; do
    show_menu
    echo -ne "请输入选项 [0-5]: "
    local choice; read -r choice
    case "$choice" in
      1) module_route ;;
      2) module_ping ;;
      3) module_speed_cn ;;
      4) module_speed_global ;;
      5) module_all ;;
      0) say "再见!"; break ;;
      *) warn "无效选项, 请输入 0-5" ;;
    esac
  done
}

usage() {
  cat <<EOF
NetworkTest v${VERSION} - VPS 大陆线路检测与测速脚本

用法: bash networktest.sh [选项]

无参数时进入交互式菜单。

选项:
  --route          回程线路检测 (判断 CN2 GIA/GT、163、9929、4837、CMI 等)
  --ping           全国延迟测试 (三网各省市 ping)
  --speed-cn       全国测速 (大陆三网)
  --speed-global   全球测速
  -a, --all        全面测试 (依次执行以上全部)
  --fast           测速使用精简节点集
  --yes            跳过流量消耗二次确认
  --ipv6           附加 IPv6 测试 (预留, 后续版本实现)
  --verbose        输出完整 traceroute 路径
  --output FILE    将报告(去色)保存到文件
  -h, --help       显示本帮助
EOF
}

main() {
  local action="menu"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --route)        action="route" ;;
      --ping)         action="ping" ;;
      --speed-cn)     action="speed_cn" ;;
      --speed-global) action="speed_global" ;;
      -a|--all)       action="all" ;;
      --fast)         FAST_MODE=1 ;;
      --yes)          AUTO_YES=1 ;;
      --ipv6)         TEST_IPV6=1; warn "IPv6 测试为预留功能, 将在后续版本提供" ;;
      --verbose)      VERBOSE=1 ;;
      --output)       shift; OUTPUT_FILE="${1:-}";
                      [[ -z "$OUTPUT_FILE" ]] && { err "--output 需要指定文件名"; exit 1; } ;;
      -h|--help)      usage; exit 0 ;;
      *) err "未知参数: $1 (使用 --help 查看帮助)"; exit 1 ;;
    esac
    shift
  done

  # 报告保存: 终端保留彩色, 文件去除颜色码
  if [[ -n "$OUTPUT_FILE" ]]; then
    : > "$OUTPUT_FILE"
    exec > >(tee >(sed -u 's/\x1b\[[0-9;]*m//g' >> "$OUTPUT_FILE")) 2>&1
  fi

  say "${BOLD}NetworkTest v${VERSION}${PLAIN} - VPS 大陆线路检测与测速  $(date '+%F %T')"
  check_deps

  case "$action" in
    menu)         menu_loop ;;
    route)        module_info; module_route ;;
    ping)         module_info; module_ping ;;
    speed_cn)     module_info; module_speed_cn ;;
    speed_global) module_info; module_speed_global ;;
    all)          module_all ;;
  esac

  [[ -n "$OUTPUT_FILE" ]] && { sleep 1; say "报告已保存到: $OUTPUT_FILE"; }
}

main "$@"
