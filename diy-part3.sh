
#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#
# 第三方插件 / 依赖 / 来源优先级 / 系统优化
#
# 来源优先级：
#   1. package/myapp
#   2. nas
#   3. nas_luci
#   4. jjm2473_apps
#   5. kenzo
#   6. small
#   7. iStoreOS / OpenWrt 官方 feeds
#
# Wi-Fi:
#   频段：5GHz
#   信道：36
#   国家：US
#   首次启动自动开启
#
# Conntrack:
#   nf_conntrack_max=655550
#
###############################################################################

set -Eeuo pipefail

echo "========================================"
echo "DIY2 - H68K + iStoreOS 24.10"
echo "第三方插件 / 依赖 / 来源优先级"
echo "========================================"

###############################################################################
# 0. 基础目录
###############################################################################

TOPDIR="${TOPDIR:-$(pwd)}"

[ -d "$TOPDIR" ] || {
    echo "ERROR: TOPDIR 不存在: $TOPDIR"
    exit 1
}

cd "$TOPDIR"

echo "TOPDIR: $TOPDIR"

[ -d scripts/feeds ] || {
    echo "ERROR: 未找到 scripts/feeds"
    exit 1
}

###############################################################################
# 1. Feed 定义
###############################################################################

OFFICIAL_FEEDS="
packages
luci
routing
telephony
store
third
"

THIRD_PARTY_FEEDS="
nas
nas_luci
jjm2473_apps
kenzo
small
"

# 完整优先级
ALL_FEEDS="
nas
nas_luci
jjm2473_apps
kenzo
small
packages
luci
routing
telephony
store
third
"

###############################################################################
# 2. 检查 DIY1 下载的第三方源码
###############################################################################

echo
echo "========================================"
echo "检查 DIY1 第三方源码"
echo "========================================"

if [ -d package/myapp ]; then
    echo "✓ package/myapp 存在"
else
    echo "WARNING: package/myapp 不存在"
fi

# PassWall
if [ -d package/myapp/passwall ]; then
    echo "✓ PassWall 主源码存在"
else
    echo "WARNING: PassWall 主源码不存在"
fi

if [ -d package/myapp/passwall-packages ]; then
    echo "✓ PassWall 依赖源码存在"
else
    echo "WARNING: PassWall 依赖源码不存在"
fi

# SmartDNS
if [ -d package/myapp/smartdns ]; then
    echo "✓ SmartDNS 源码存在"
else
    echo "WARNING: SmartDNS 源码不存在"
fi

###############################################################################
# 3. 安装 feeds 软件包入口
###############################################################################

echo
echo "========================================"
echo "安装 feeds 软件包入口"
echo "========================================"

# 注意：
# 不在这里删除官方源码。
# 不重复安装已经被删除的 microsocks。
# 不重复 Clone DIY1 已下载的 PassWall。

./scripts/feeds install -a

echo "feeds 安装完成"

###############################################################################
# 4. 软件包入口检查函数
###############################################################################

package_entry_exists()
{
    local feed="$1"
    local pkg="$2"

    local entry="package/feeds/${feed}/${pkg}"

    [ -e "$entry" ] || [ -L "$entry" ]
}

remove_package_entry()
{
    local feed="$1"
    local pkg="$2"

    local entry="package/feeds/${feed}/${pkg}"

    if [ -e "$entry" ] || [ -L "$entry" ]; then
        echo "删除低优先级入口: ${feed}/${pkg}"
        rm -f "$entry"
    fi
}

package_makefile()
{
    local feed="$1"
    local pkg="$2"

    local makefile="package/feeds/${feed}/${pkg}/Makefile"

    if [ -f "$makefile" ]; then
        readlink -f "$makefile" 2>/dev/null || true
    fi
}

###############################################################################
# 5. 获取软件包版本
###############################################################################

get_package_version()
{
    local makefile="$1"
    local version=""

    [ -f "$makefile" ] || {
        echo "unknown"
        return 0
    }

    version="$(
        sed -nE \
            's/^[[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*(.*)$/\1/p' \
            "$makefile" |
        head -n 1
    )"

    if [ -z "$version" ]; then

        version="$(
            sed -nE \
                's/^[[:space:]]*PKG_RELEASE[[:space:]]*:?=[[:space:]]*(.*)$/release-\1/p' \
                "$makefile" |
            head -n 1
        )"

    fi

    [ -n "$version" ] || version="unknown"

    echo "$version"
}

###############################################################################
# 6. 扫描 package/myapp 真正的 Package
###############################################################################

echo
echo "========================================"
echo "扫描 package/myapp"
echo "========================================"

MYAPP_PACKAGES=()

if [ -d package/myapp ]; then

    while IFS= read -r pkg; do

        [ -n "$pkg" ] || continue

        case "$pkg" in
            *'('*|*')'*|*'/'*)
                continue
                ;;
        esac

        MYAPP_PACKAGES+=("$pkg")

        echo "✓ 独立第三方包: $pkg"

    done < <(
        find package/myapp \
            -type f \
            -name Makefile \
            -print0 2>/dev/null |
        xargs -0 -r sed -nE \
            's/^[[:space:]]*define[[:space:]]+Package\/([A-Za-z0-9_.+@:-]+)[[:space:]]*$/\1/p' |
        sort -u
    )

fi

echo "package/myapp 软件包数量: ${#MYAPP_PACKAGES[@]}"

###############################################################################
# 7. 收集所有 Feed 中的软件包
###############################################################################

echo
echo "========================================"
echo "收集所有 Feed 软件包"
echo "========================================"

ALL_PACKAGES=()

declare -A PACKAGE_SEEN

for pkg in "${MYAPP_PACKAGES[@]}"; do

    [ -n "$pkg" ] || continue

    if [ -z "${PACKAGE_SEEN[$pkg]+x}" ]; then
        PACKAGE_SEEN["$pkg"]=1
        ALL_PACKAGES+=("$pkg")
    fi

done

for feed in $ALL_FEEDS; do

    FEED_DIR="package/feeds/${feed}"

    [ -d "$FEED_DIR" ] || continue

    while IFS= read -r -d '' entry; do

        pkg="${entry##*/}"

        [ -n "$pkg" ] || continue

        if [ -z "${PACKAGE_SEEN[$pkg]+x}" ]; then

            PACKAGE_SEEN["$pkg"]=1
            ALL_PACKAGES+=("$pkg")

        fi

    done < <(
        find "$FEED_DIR" \
            -mindepth 1 \
            -maxdepth 1 \
            -print0 2>/dev/null
    )

done

echo "扫描到的软件包入口数量: ${#ALL_PACKAGES[@]}"

###############################################################################
# 8. package/myapp 最高优先级
###############################################################################

echo
echo "========================================"
echo "第一优先级：package/myapp"
echo "========================================"

for pkg in "${MYAPP_PACKAGES[@]}"; do

    [ -n "$pkg" ] || continue

    echo
    echo "处理独立第三方包: $pkg"

    for feed in $ALL_FEEDS; do

        if package_entry_exists "$feed" "$pkg"; then

            MAKEFILE="$(package_makefile "$feed" "$pkg")"

            VERSION="$(get_package_version "$MAKEFILE")"

            echo "发现重复来源: ${feed}/${pkg}"
            echo "来源版本: $VERSION"
            echo "选择: package/myapp"

            remove_package_entry "$feed" "$pkg"

        fi

    done

done

###############################################################################
# 9. 第三方 Feed 和官方 Feed 全量优先级
###############################################################################

echo
echo "========================================"
echo "第二优先级：第三方 Feed"
echo "第三优先级：官方 Feed"
echo "========================================"

THIRD_SELECTED=0
OFFICIAL_SELECTED=0
DUPLICATE_REMOVED=0

for pkg in "${ALL_PACKAGES[@]}"; do

    [ -n "$pkg" ] || continue

    # package/myapp 已经处理
    IS_MYAPP=0

    for myapp_pkg in "${MYAPP_PACKAGES[@]}"; do

        if [ "$pkg" = "$myapp_pkg" ]; then
            IS_MYAPP=1
            break
        fi

    done

    [ "$IS_MYAPP" -eq 0 ] || continue

    WINNER=""

    ###########################################################################
    # 9.1 寻找最高优先级第三方来源
    ###########################################################################

    for feed in $THIRD_PARTY_FEEDS; do

        if package_entry_exists "$feed" "$pkg"; then

            WINNER="$feed"
            break

        fi

    done

    ###########################################################################
    # 9.2 没有第三方来源时，选择第一个官方来源
    ###########################################################################

    if [ -z "$WINNER" ]; then

        for feed in $OFFICIAL_FEEDS; do

            if package_entry_exists "$feed" "$pkg"; then

                WINNER="$feed"
                break

            fi

        done

    fi

    [ -n "$WINNER" ] || continue

    WINNER_MAKEFILE="$(package_makefile "$WINNER" "$pkg")"

    WINNER_VERSION="$(get_package_version "$WINNER_MAKEFILE")"

    echo
    echo "----------------------------------------"
    echo "软件包: $pkg"
    echo "最终来源: $WINNER"
    echo "版本: $WINNER_VERSION"
    echo "----------------------------------------"

    case " $THIRD_PARTY_FEEDS " in

        *" $WINNER "*)
            THIRD_SELECTED=$((THIRD_SELECTED + 1))
            ;;

        *)
            OFFICIAL_SELECTED=$((OFFICIAL_SELECTED + 1))
            ;;

    esac

    ###########################################################################
    # 9.3 删除所有低优先级重复入口
    ###########################################################################

    LOWER_PRIORITY=0

    for feed in $ALL_FEEDS; do

        [ "$feed" != "$WINNER" ] || {
            LOWER_PRIORITY=1
            continue
        }

        if [ "$LOWER_PRIORITY" -eq 1 ] &&
           package_entry_exists "$feed" "$pkg"; then

            echo "移除重复来源: ${feed}/${pkg}"

            remove_package_entry "$feed" "$pkg"

            DUPLICATE_REMOVED=$((DUPLICATE_REMOVED + 1))

        fi

    done

done

echo
echo "第三方来源选择数量: $THIRD_SELECTED"
echo "官方来源选择数量: $OFFICIAL_SELECTED"
echo "重复入口移除数量: $DUPLICATE_REMOVED"

###############################################################################
# 10. SmartDNS Rust Makefile 修复
###############################################################################

echo
echo "========================================"
echo "SmartDNS Rust Makefile 修复"
echo "========================================"

RUST_MAKEFILE="feeds/packages/lang/rust/rust-package.mk"

if [ -f "$RUST_MAKEFILE" ]; then

    SMARTDNS_MAKEFILES=(
        "package/myapp/smartdns/package/openwrt/Makefile"
        "package/myapp/smartdns/Makefile"
    )

    for mf in "${SMARTDNS_MAKEFILES[@]}"; do

        [ -f "$mf" ] || continue

        sed -i \
            's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
            "$mf"

        echo "已检查: $mf"

    done

else

    echo "WARNING: 未找到 Rust rust-package.mk"
    echo "SmartDNS Rust 依赖需要进一步检查"

fi

###############################################################################
# 11. 自动添加 LuCI 中文语言包
###############################################################################

echo
echo "========================================"
echo "添加 LuCI 中文语言包"
echo "========================================"

if [ -f .config ]; then

    mapfile -t LUCI_APPS < <(

        sed -nE \
            's/^CONFIG_PACKAGE_(luci-app-[A-Za-z0-9_.+-]+)=(y|m)$/\1/p' \
            .config |
        sort -u

    )

    for pkg in "${LUCI_APPS[@]}"; do

        trans="luci-i18n-${pkg#luci-app-}-zh-cn"

        if grep -Fqx "CONFIG_PACKAGE_${trans}=y" .config; then
            continue
        fi

        if grep -Fqx "CONFIG_PACKAGE_${trans}=m" .config; then
            continue
        fi

        # 确认中文语言包真实存在
        if grep -rnqE \
            "^[[:space:]]*define[[:space:]]+Package/${trans}([[:space:]]|$)" \
            package feeds 2>/dev/null; then

            echo "添加中文语言包: $trans"

            TEMP_CONFIG="$(mktemp)"

            awk -v key="CONFIG_PACKAGE_${trans}" '
                index($0,key"=") != 1 &&
                $0 != "# "key" is not set"
            ' .config > "$TEMP_CONFIG"

            printf '%s=y\n' "$key" >> "$TEMP_CONFIG"

            mv "$TEMP_CONFIG" .config

        else

            echo "未找到中文包，跳过: $trans"

        fi

    done

else

    echo "WARNING: .config 不存在，跳过中文语言包"

fi

###############################################################################
# 12. conntrack 调优
###############################################################################

echo
echo "========================================"
echo "设置 conntrack"
echo "========================================"

SYSCTL_FILE="package/base-files/files/etc/sysctl.conf"

mkdir -p "$(dirname "$SYSCTL_FILE")"

touch "$SYSCTL_FILE"

sed -i \
    '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' \
    "$SYSCTL_FILE"

cat >> "$SYSCTL_FILE" <<'EOF'

# Conntrack maximum connections
net.netfilter.nf_conntrack_max=655550
EOF

echo "nf_conntrack_max = 655550"

###############################################################################
# 13. Wi-Fi 首次启动自动开启
#
# 5GHz
# Channel 36
# Country US
#
# 只处理能够识别为 5GHz 的 radio。
# 不强制修改 2.4GHz。
# 不负责安装无线驱动或创建硬件 DTS。
###############################################################################

echo
echo "========================================"
echo "设置 5GHz Wi-Fi"
echo "========================================"

mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/zz-enable-wifi <<'EOF'
#!/bin/sh

# H68K 5GHz Wi-Fi 默认配置
# Frequency: 5GHz
# Channel: 36
# Country: US

. /lib/functions.sh

# 如果无线配置不存在，尝试生成
if [ ! -s /etc/config/wireless ]; then
    wifi config 2>/dev/null
fi

if [ ! -s /etc/config/wireless ]; then
    logger -t enable-wifi "wireless config unavailable"
    exit 0
fi

config_load wireless

RADIOS_5G=""

###############################################################################
# 识别 5GHz 无线设备
###############################################################################

find_5g_radio()
{
    local cfg="$1"
    local band
    local hwmode

    band="$(uci -q get "wireless.${cfg}.band" 2>/dev/null)"
    hwmode="$(uci -q get "wireless.${cfg}.hwmode" 2>/dev/null)"

    case "${band}:${hwmode}" in

        5g:*|*:11a|*:11an|*:11ac|*:11ax|*:11be)

            RADIOS_5G="${RADIOS_5G} ${cfg}"

            logger -t enable-wifi "5GHz radio detected: ${cfg}"

            ;;

    esac
}

config_foreach find_5g_radio wifi-device

###############################################################################
# 没有识别到 5GHz 时，不盲目修改无线配置
###############################################################################

if [ -z "$RADIOS_5G" ]; then

    logger -t enable-wifi \
        "No identifiable 5GHz radio; skip Wi-Fi modification"

    exit 0

fi

###############################################################################
# 设置 5GHz 无线参数
###############################################################################

for radio in $RADIOS_5G; do

    uci -q set "wireless.${radio}.country=US"
    uci -q set "wireless.${radio}.channel=36"
    uci -q set "wireless.${radio}.disabled=0"

    logger -t enable-wifi \
        "Enabled ${radio}: country=US channel=36"

done

###############################################################################
# 仅开启关联到 5GHz radio 的无线接口
###############################################################################

enable_5g_iface()
{
    local cfg="$1"
    local device
    local radio

    device="$(uci -q get "wireless.${cfg}.device" 2>/dev/null)"

    [ -n "$device" ] || return 0

    for radio in $RADIOS_5G; do

        if [ "$device" = "$radio" ]; then

            uci -q set "wireless.${cfg}.disabled=0"

            logger -t enable-wifi \
                "Enabled 5GHz interface: ${cfg}"

            break

        fi

    done
}

config_foreach enable_5g_iface wifi-iface

###############################################################################
# 提交配置
###############################################################################

uci -q commit wireless

logger -t enable-wifi \
    "5GHz Wi-Fi initialization completed"

exit 0
EOF

chmod +x files/etc/uci-defaults/zz-enable-wifi

echo "5GHz Wi-Fi 首次启动配置已写入"
echo "国家码: US"
echo "信道: 36"
echo "默认开启: 是"

###############################################################################
# 14. 最终来源检查
###############################################################################

echo
echo "========================================"
echo "最终第三方来源检查"
echo "========================================"

FINAL_DUPLICATES=0

for pkg in "${ALL_PACKAGES[@]}"; do

    [ -n "$pkg" ] || continue

    FOUND_SOURCES=()

    for feed in $ALL_FEEDS; do

        if package_entry_exists "$feed" "$pkg"; then
            FOUND_SOURCES+=("$feed")
        fi

    done

    if [ "${#FOUND_SOURCES[@]}" -gt 1 ]; then

        echo
        echo "WARNING: 仍存在重复入口: $pkg"

        for feed in "${FOUND_SOURCES[@]}"; do
            echo "  - $feed"
        done

        FINAL_DUPLICATES=$((FINAL_DUPLICATES + 1))

    fi

done

###############################################################################
# 15. 输出 package/myapp 版本信息
###############################################################################

echo
echo "========================================"
echo "package/myapp 最终检查"
echo "========================================"

for pkg in "${MYAPP_PACKAGES[@]}"; do

    [ -n "$pkg" ] || continue

    FOUND_MYAPP=""

    while IFS= read -r -d '' mf; do

        if grep -Eq \
            "^[[:space:]]*define[[:space:]]+Package/${pkg}([[:space:]]|\\))" \
            "$mf" 2>/dev/null; then

            FOUND_MYAPP="$mf"
            break

        fi

    done < <(
        find package/myapp \
            -type f \
            -name Makefile \
            -print0 2>/dev/null
    )

    if [ -n "$FOUND_MYAPP" ]; then

        echo "[$pkg]"
        echo "  来源: package/myapp"
        echo "  版本: $(get_package_version "$FOUND_MYAPP")"

    fi

done

###############################################################################
# 16. 最终配置检查
###############################################################################

echo
echo "========================================"
echo "最终配置检查"
echo "========================================"

echo
echo "[Conntrack]"

grep -n \
    'nf_conntrack_max' \
    "$SYSCTL_FILE" || true

echo
echo "[Wi-Fi]"

if [ -x files/etc/uci-defaults/zz-enable-wifi ]; then
    echo "5GHz 首次启动脚本: OK"
else
    echo "5GHz 首次启动脚本: ERROR"
fi

echo
echo "[Package Sources]"

echo "扫描包数量: ${#ALL_PACKAGES[@]}"
echo "myapp 包数量: ${#MYAPP_PACKAGES[@]}"
echo "第三方优先来源数量: $THIRD_SELECTED"
echo "官方来源数量: $OFFICIAL_SELECTED"
echo "删除重复入口数量: $DUPLICATE_REMOVED"
echo "最终重复入口数量: $FINAL_DUPLICATES"

###############################################################################
# 17. DIY2 完成
###############################################################################

echo
echo "========================================"

if [ "$FINAL_DUPLICATES" -eq 0 ]; then

    echo "DIY2 OK"
    echo "第三方软件包来源检查通过"

else

    echo "DIY2 WARNING"
    echo "发现仍然存在重复安装入口"

fi

echo "========================================"
