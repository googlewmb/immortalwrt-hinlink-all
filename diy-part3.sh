#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#
# 第三方插件 / 依赖 / 来源优先级处理
#
# 来源优先级：
#   1. package/myapp 独立第三方源码
#   2. DIY1 添加的第三方集合源
#   3. iStoreOS / OpenWrt 官方 feeds
#

set -e

echo "========================================"
echo "DIY2 - H68K + iStoreOS 24.10"
echo "第三方插件 / 依赖 / 来源优先级处理"
echo "========================================"

###############################################################################
# 0. 基础目录与环境检查
###############################################################################

TOPDIR="${TOPDIR:-$(pwd)}"

[ -d "$TOPDIR" ] || {
    echo "ERROR: TOPDIR 不存在: $TOPDIR"
    exit 1
}

cd "$TOPDIR"
TOPDIR="$(pwd)"

echo "TOPDIR: $TOPDIR"

# scripts/feeds 是可执行文件，不是目录
[ -f scripts/feeds ] && [ -x scripts/feeds ] || {
    echo "ERROR: 未找到可执行的 scripts/feeds"
    echo "请检查当前目录是否为 OpenWrt / ImmortalWrt 源码根目录"
    exit 1
}

for dir in package target include toolchain; do
    [ -d "$dir" ] || {
        echo "ERROR: 缺少源码目录: $dir"
        exit 1
    }
done

###############################################################################
# 1. 核心依赖与第三方源码预处理
###############################################################################

echo
echo "========================================"
echo "预处理核心依赖与 PassWall 组件"
echo "========================================"

# 1.1 替换 Golang 为 27.x
# 保留原配置，默认不执行。
#
# if [ -d feeds/packages/lang/golang ]; then
#     echo "删除旧 Golang"
#     rm -rf feeds/packages/lang/golang
# fi
#
# git clone \
#     -b 27.x \
#     --depth 1 \
#     https://github.com/sbwml/packages_lang_golang \
#     feeds/packages/lang/golang

# 1.2 移除官方旧库
# PassWall 已由 DIY1 拉取到 package/myapp。
# 这里保留原来的官方旧库移除逻辑。

rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}

rm -rf feeds/luci/applications/luci-app-passwall

# DIY1 已下载：
# package/myapp/passwall-packages
# package/myapp/passwall
#
# DIY2 不重复 Clone。

# 1.3 注册新拉取的软件包索引
echo "更新并安装软件包入口..."

./scripts/feeds install -p packages golang || true
./scripts/feeds install -f microsocks || true
./scripts/feeds install -a

###############################################################################
# 2. Feed 定义
###############################################################################

echo
echo "========================================"
echo "初始化 Feed 优先级"
echo "========================================"

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

REMOVE_OFFICIAL_DEPS=""

###############################################################################
# 3. 软件包入口操作函数
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
        echo "删除低优先级安装入口: ${feed}/${pkg}"
        rm -rf "$entry"
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

is_enabled()
{
    local pkg="$1"

    grep -Eq \
        "^CONFIG_PACKAGE_${pkg}=(y|m)$" \
        .config 2>/dev/null
}

###############################################################################
# 4. 明确要求移除的官方依赖入口
###############################################################################

echo
echo "========================================"
echo "官方依赖入口预处理"
echo "========================================"

for pkg in $REMOVE_OFFICIAL_DEPS; do

    [ -n "$pkg" ] || continue

    echo "明确要求：移除官方依赖入口 -> $pkg"

    for official_feed in $OFFICIAL_FEEDS; do
        remove_package_entry "$official_feed" "$pkg"
    done

done

###############################################################################
# 5. 获取包版本函数
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
echo "扫描 DIY1 独立第三方插件"
echo "========================================"

MYAPP_PACKAGES=""

if [ -d package/myapp ]; then

    while IFS= read -r pkg; do

        [ -n "$pkg" ] || continue

        case "$pkg" in
            *'('*|*')'*|*'/'*)
                continue
                ;;
        esac

        MYAPP_PACKAGES="${MYAPP_PACKAGES}
$pkg"

        echo "✓ 独立第三方包: $pkg"

    done < <(
        find package/myapp \
            -type f \
            -name Makefile \
            -print0 2>/dev/null |
        xargs -0 -r sed -nE \
            's/^[[:space:]]*define[[:space:]]+Package\/([A-Za-z0-9_.+@:-]+)[[:space:]]*$/\1/p' |
        sort -u || true
    )

else

    echo "WARNING: package/myapp 不存在"

fi

echo
echo "独立第三方包数量：$(printf '%s\n' "$MYAPP_PACKAGES" | sed '/^$/d' | wc -l)"

###############################################################################
# 7. 收集当前 .config 中实际启用的 Package
###############################################################################

echo
echo "========================================"
echo "读取当前 .config"
echo "========================================"

CONFIG_PACKAGES=""

if [ -f .config ]; then

    CONFIG_PACKAGES="$(
        sed -nE \
            's/^CONFIG_PACKAGE_([A-Za-z0-9_.+@:-]+)=(y|m)$/\1/p' \
            .config |
        sort -u
    )"

else

    echo "WARNING: .config 不存在，跳过已启用包扫描"

fi

echo "当前启用的 Package 数量：$(printf '%s\n' "$CONFIG_PACKAGES" | sed '/^$/d' | wc -l)"

###############################################################################
# 8. package/myapp 独立源码最高优先级
###############################################################################

echo
echo "========================================"
echo "第一优先级：package/myapp"
echo "========================================"

for pkg in $MYAPP_PACKAGES; do

    [ -n "$pkg" ] || continue

    echo
    echo "检查独立第三方插件: $pkg"

    MYAPP_MAKEFILE=""

    while IFS= read -r -d '' mf; do

        [ -f "$mf" ] || continue

        if grep -Eq \
            "^[[:space:]]*define[[:space:]]+Package/${pkg}([[:space:]]|\\))" \
            "$mf" 2>/dev/null; then

            MYAPP_MAKEFILE="$mf"
            break

        fi

    done < <(
        find package/myapp \
            -type f \
            -name Makefile \
            -print0 2>/dev/null || true
    )

    if [ -n "$MYAPP_MAKEFILE" ]; then

        MYAPP_VERSION="$(get_package_version "$MYAPP_MAKEFILE")"

        echo "package/myapp 版本: $MYAPP_VERSION"

    else

        MYAPP_VERSION="unknown"

    fi

    for feed in $ALL_FEEDS; do

        if package_entry_exists "$feed" "$pkg"; then

            MAKEFILE="$(package_makefile "$feed" "$pkg")"
            VERSION="$(get_package_version "$MAKEFILE")"

            echo "发现重复来源:"
            echo "  来源: ${feed}/${pkg}"
            echo "  版本: $VERSION"
            echo "选择: package/myapp"
            echo "原因: 独立第三方源码优先"

            remove_package_entry "$feed" "$pkg"

        fi

    done

done

###############################################################################
# 9. 第三方集合源 > 官方 Feed
###############################################################################

echo
echo "========================================"
echo "第二优先级：第三方集合源"
echo "第三优先级：官方 Feed"
echo "========================================"

THIRD_SELECTED=0
OFFICIAL_SELECTED=0
DUPLICATE_REMOVED=0

for pkg in $CONFIG_PACKAGES; do

    [ -n "$pkg" ] || continue

    IS_MYAPP=0

    for myapp_pkg in $MYAPP_PACKAGES; do

        if [ "$pkg" = "$myapp_pkg" ]; then
            IS_MYAPP=1
            break
        fi

    done

    [ "$IS_MYAPP" -eq 0 ] || continue

    WINNER=""

    # 按完整优先级寻找第一个可用来源。
    for feed in $ALL_FEEDS; do

        if package_entry_exists "$feed" "$pkg"; then

            WINNER="$feed"
            break

        fi

    done

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

    # 删除所有低优先级重复入口。
    LOWER_PRIORITY=0

    for feed in $ALL_FEEDS; do

        if [ "$feed" = "$WINNER" ]; then

            LOWER_PRIORITY=1
            continue

        fi

        if [ "$LOWER_PRIORITY" -eq 1 ] &&
           package_entry_exists "$feed" "$pkg"; then

            echo "移除低优先级重复来源: ${feed}/${pkg}"

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
echo "修复 SmartDNS Rust Makefile"
echo "========================================"

RUST_MAKEFILE="feeds/packages/lang/rust/rust-package.mk"

if [ -f "$RUST_MAKEFILE" ]; then

    if [ -f package/myapp/smartdns/package/openwrt/Makefile ]; then

        sed -i \
            's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
            package/myapp/smartdns/package/openwrt/Makefile

        echo "已检查: package/myapp/smartdns/package/openwrt/Makefile"

    fi

    if [ -f package/myapp/smartdns/Makefile ]; then

        sed -i \
            's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
            package/myapp/smartdns/Makefile

        echo "已检查: package/myapp/smartdns/Makefile"

    fi

else

    echo "WARNING: 未找到 $RUST_MAKEFILE"
    echo "SmartDNS Rust 依赖路径需要进一步检查"

fi

###############################################################################
# 11. 自动添加 LuCI 中文语言包
###############################################################################

echo
echo "========================================"
echo "添加 LuCI 中文语言包"
echo "========================================"

if [ -f .config ]; then

    LUCI_APPS="$(
        sed -nE \
            's/^CONFIG_PACKAGE_(luci-app-[A-Za-z0-9_.+-]+)=(y|m)$/\1/p' \
            .config |
        sort -u
    )"

    for pkg in $LUCI_APPS; do

        [ -n "$pkg" ] || continue

        trans="luci-i18n-${pkg#luci-app-}-zh-cn"

        if grep -Fqx "CONFIG_PACKAGE_${trans}=y" .config; then
            continue
        fi

        if grep -Fqx "CONFIG_PACKAGE_${trans}=m" .config; then
            continue
        fi

        if grep -R -n -E \
            "^[[:space:]]*define[[:space:]]+Package/${trans}([[:space:]]|$)" \
            package feeds 2>/dev/null; then

            echo "添加中文语言包: $trans"

            TEMP_CONFIG="$(mktemp)"

            awk -v key="CONFIG_PACKAGE_${trans}" '
                index($0, key "=") != 1 &&
                $0 != "# " key " is not set"
            ' .config > "$TEMP_CONFIG"

            printf '%s=y\n' "CONFIG_PACKAGE_${trans}" >> "$TEMP_CONFIG"

            mv "$TEMP_CONFIG" .config

        else

            echo "未找到中文包，跳过: $trans"

        fi

    done

else

    echo "WARNING: .config 不存在，跳过中文语言包"

fi

###############################################################################
# 12. Conntrack 调优
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
# 5GHz:
#   Channel: 36
#   Country: US
###############################################################################

echo
echo "========================================"
echo "设置 Wi-Fi 首次启动自动开启"
echo "5GHz: Channel 36 / Country US"
echo "========================================"

mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/zz-enable-wifi <<'EOF'
#!/bin/sh

. /lib/functions.sh

# 无线配置不存在时尝试生成。
if [ ! -s /etc/config/wireless ]; then
    wifi config 2>/dev/null
fi

if [ ! -s /etc/config/wireless ]; then
    logger -t enable-wifi "wireless config unavailable"
    exit 0
fi

config_load wireless

###############################################################################
# 开启所有 radio 和 wifi-iface
###############################################################################

enable_wifi()
{
    local cfg="$1"

    uci -q set "wireless.${cfg}.disabled=0"
}

config_foreach enable_wifi wifi-device
config_foreach enable_wifi wifi-iface

###############################################################################
# 识别 5GHz radio
###############################################################################

RADIOS_5G=""

find_5g_radio()
{
    local cfg="$1"
    local band=""
    local hwmode=""

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
# 设置 5GHz 国家码和信道
###############################################################################

if [ -n "$RADIOS_5G" ]; then

    for radio in $RADIOS_5G; do

        uci -q set "wireless.${radio}.country=US"
        uci -q set "wireless.${radio}.channel=36"
        uci -q set "wireless.${radio}.disabled=0"

        logger -t enable-wifi \
            "Enabled ${radio}: country=US channel=36"

    done

else

    logger -t enable-wifi \
        "No identifiable 5GHz radio; skip 5GHz channel configuration"

fi

###############################################################################
# 提交无线配置
###############################################################################

uci -q commit wireless

logger -t enable-wifi "Wi-Fi default configuration completed"

exit 0
EOF

chmod +x files/etc/uci-defaults/zz-enable-wifi

echo "Wi-Fi 首次启动自动开启脚本已生成"
echo "5GHz 国家码和信道设置：US / 36"

###############################################################################
# 14. 最终来源检查
###############################################################################

echo
echo "========================================"
echo "最终第三方插件来源检查"
echo "========================================"

for pkg in $MYAPP_PACKAGES; do

    [ -n "$pkg" ] || continue

    echo
    echo "[$pkg]"

    if [ -d package/myapp ]; then

        FOUND_MYAPP=""

        while IFS= read -r -d '' mf; do

            [ -f "$mf" ] || continue

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
                -print0 2>/dev/null || true
        )

        if [ -n "$FOUND_MYAPP" ]; then

            echo "  来源: package/myapp"
            echo "  Makefile: $FOUND_MYAPP"
            echo "  版本: $(get_package_version "$FOUND_MYAPP")"

        else

            echo "  WARNING: 未找到对应 Package 定义"

        fi

    fi

done

###############################################################################
# 15. 最终配置检查
###############################################################################

echo
echo "========================================"
echo "最终配置检查"
echo "========================================"

echo
echo "Conntrack:"
grep -n 'nf_conntrack_max' \
    package/base-files/files/etc/sysctl.conf || true

echo
echo "Wi-Fi 初始化脚本:"
ls -l files/etc/uci-defaults/zz-enable-wifi

echo
echo "Feed 安装入口目录:"
ls -ld package/feeds 2>/dev/null || true

echo
echo "当前 .config:"
if [ -f .config ]; then
    echo ".config 存在"
else
    echo "WARNING: .config 不存在"
fi

###############################################################################
# 16. DIY2 完成
###############################################################################

echo
echo "========================================"
echo "DIY2 OK"
echo "========================================"
