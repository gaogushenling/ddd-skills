#!/bin/bash

# DDD 项目脚手架生成脚本
# 使用 ddd-scaffold-lite-jdk17 模板创建 DDD 多模块项目
# 支持: Windows (Git Bash/MSYS)、Mac、Linux

set -e

# ============================================================
# 1. 操作系统检测
# ============================================================
detect_os() {
    local os_name="$(uname -s)"
    case "$os_name" in
        CYGWIN*|MINGW*|MSYS*)  echo "windows";;
        Darwin*)               echo "mac";;
        Linux*)                echo "linux";;
        *)
            # 兜底检测：查 /etc/os-release
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                case "$ID" in
                    windows|msys|cygwin) echo "windows";;
                    macos|darling)        echo "mac";;
                    *)                    echo "linux";;
                esac
            else
                echo "linux"  # 默认按 linux 处理
            fi
            ;;
    esac
}

OS_TYPE=$(detect_os)

# ============================================================
# 2. 跨平台工具函数
# ============================================================

# 转换路径为当前 OS 兼容格式
normalize_path() {
    local path="$1"
    if [ "$OS_TYPE" = "windows" ]; then
        # 转为 Windows 风格路径
        cygpath -w "$path" 2>/dev/null || echo "$path"
    else
        echo "$path"
    fi
}

# 检测命令是否存在
has_command() {
    command -v "$1" >/dev/null 2>&1
}

# 获取用户 home 目录（兼容 Windows MSYS/Git Bash）
get_home_dir() {
    if [ "$OS_TYPE" = "windows" ]; then
        # MSYS/Git Bash 下用 ~ 可能有歧义，显式取 home
        echo "$HOME"
    else
        echo "$HOME"
    fi
}

# 读取用户输入（兼容 Windows MSYS/Git Bash 的 tty 检测）
read_input() {
    local prompt="$1"
    local default="$2"
    local result_var="$3"

    if [ -n "$default" ]; then
        if has_command "readlink" && [ -t 0 ]; then
            # 标准环境
            read -p "$prompt [$default]: " input
        else
            # Windows Git Bash / 非交互环境
            input=""
        fi
        input="${input:-$default}"
    else
        input=""
        if has_command "readlink" && [ -t 0 ]; then
            read -p "$prompt: " input
        fi
    fi
    eval "$result_var='$input'"
}

# ============================================================
# 3. 环境检测（各平台通用）
# ============================================================
check_environment() {
    echo ""
    echo "============================================"
    echo "  [${OS_TYPE}] 环境检测"
    echo "============================================"

    local env_ok=true

    # Java
    if has_command "java"; then
        local java_version
        java_version=$(java -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/')
        echo "  ✅ Java:    $java_version ($(which java))"
    else
        echo "  ❌ Java:    未找到，请先安装 JDK 17+"
        echo "             Windows: https://adoptium.net/"
        echo "             Mac:     brew install openjdk@17"
        echo "             Linux:   sudo apt install openjdk-17-jdk"
        env_ok=false
    fi

    # Maven
    if has_command "mvn"; then
        local mvn_version
        mvn_version=$(mvn -version 2>&1 | head -1 | sed 's/.*Apache Maven \(.*\)/\1/')
        echo "  ✅ Maven:   $mvn_version ($(which mvn))"
    else
        echo "  ❌ Maven:   未找到，请先安装 Maven 3.6+"
        echo "             Windows: https://maven.apache.org/download.cgi"
        echo "             Mac:     brew install maven"
        echo "             Linux:   sudo apt install maven"
        env_ok=false
    fi

    echo ""

    if [ "$env_ok" = false ]; then
        echo "❌ 环境检测未通过，请先安装缺失工具后重试"
        exit 1
    fi
}

# ============================================================
# 4. 平台特定配置
# ============================================================
platform_config() {
    local target_dir
    target_dir=$(get_home_dir)

    case "$OS_TYPE" in
        windows)
            # Windows 下建议生成到用户目录，避免路径含空格问题
            echo ""
            echo "  📂 目标目录: $target_dir"
            echo "     Windows 环境检测到"
            echo "     注意: 路径中避免空格和中文，建议使用英文目录名"
            ;;
        mac)
            echo ""
            echo "  📂 目标目录: $target_dir"
            echo "     macOS 环境"
            ;;
        linux)
            echo ""
            echo "  📂 目标目录: $target_dir"
            echo "     Linux 环境"
            ;;
    esac

    # 返回目标目录（平台无关路径，用于 cd）
    echo "$target_dir"
}

# ============================================================
# 5. 交互式询问
# ============================================================
DEFAULT_GROUP_ID="com.yourcompany"
DEFAULT_ARTIFACT_ID="your-project-name"
DEFAULT_VERSION="1.0.0-SNAPSHOT"
DEFAULT_PACKAGE="com.yourcompany.project"
DEFAULT_ARCHETYPE_VERSION="1.3"

collect_params() {
    echo ""
    echo "============================================"
    echo "  📦 项目配置"
    echo "============================================"

    # 1. GroupId
    read_input "请输入 GroupId（项目包前缀）" "$DEFAULT_GROUP_ID" "GROUP_ID"
    echo ""
    echo "   用途: Maven 坐标的 groupId，用于标识组织或公司"
    echo "   示例: com.yourcompany、cn.bugstack"
    echo ""

    # 2. ArtifactId
    read_input "请输入 ArtifactId（项目名称）" "$DEFAULT_ARTIFACT_ID" "ARTIFACT_ID"
    echo ""
    echo "   用途: 项目模块的唯一标识名称"
    echo "   示例: order-system、user-center"
    echo ""

    # 3. Version
    read_input "请输入 Version（版本号）" "$DEFAULT_VERSION" "VERSION"
    echo ""
    echo "   用途: 项目的版本号"
    echo "   示例: 1.0.0-SNAPSHOT、2.1.0-RELEASE"
    echo ""

    # 4. Package
    # 自动从 GroupId 推导默认 Package
    local default_pkg="${DEFAULT_PACKAGE}"
    if [ "$GROUP_ID" != "$DEFAULT_GROUP_ID" ]; then
        default_pkg="$GROUP_ID.${ARTIFACT_ID//-/.}"
    fi
    read_input "请输入 Package（根包名）" "$default_pkg" "PACKAGE"
    echo ""
    echo "   用途: Java 代码的根包名"
    echo "   示例: com.yourcompany.project、cn.bugstack.order"
    echo ""

    # 5. Archetype 版本
    read_input "请输入 Archetype 版本" "$DEFAULT_ARCHETYPE_VERSION" "ARCHETYPE_VERSION"
    echo ""
}

# ============================================================
# 6. 确认 & 生成
# ============================================================
confirm_and_generate() {
    local target_dir="$1"

    echo ""
    echo "============================================"
    echo "  ✅ 确认配置"
    echo "============================================"
    echo "   OS 类型:   $OS_TYPE"
    echo "   GroupId:   $GROUP_ID"
    echo "   ArtifactId: $ARTIFACT_ID"
    echo "   Version:   $VERSION"
    echo "   Package:   $PACKAGE"
    echo "   Archetype: $ARCHETYPE_VERSION"
    echo ""

    local confirm=""
    read -p "确认以上配置开始生成？(y/n): " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消生成"
        exit 0
    fi

    # ============================================================
    # 7. 执行 Maven Archetype（跨平台统一命令）
    # ============================================================
    echo ""
    echo "============================================"
    echo "  🚀 开始生成项目..."
    echo "============================================"

    cd "$target_dir"

    # 构建 Maven 命令（参数顺序不影响功能）
    local mvn_cmd="mvn archetype:generate"
    local mvn_args=(
        -DarchetypeGroupId=io.github.fuzhengwei
        -DarchetypeArtifactId=ddd-scaffold-lite-jdk17
        -DarchetypeVersion="$ARCHETYPE_VERSION"
        -DarchetypeRepository=https://maven.xiaofuge.cn/
        -DgroupId="$GROUP_ID"
        -DartifactId="$ARTIFACT_ID"
        -Dversion="$VERSION"
        -Dpackage="$PACKAGE"
        -B
    )

    # Windows MSYS/Git Bash 下有时 PATH 不完整，显式补充
    if [ "$OS_TYPE" = "windows" ]; then
        # 确保 PATH 包含常见工具路径（兼容 Git Bash / MSYS2）
        export PATH="$PATH:/c/Program Files/Java:/c/Program Files/Apache/Maven/bin"
    fi

    # 执行 Maven
    # shellcheck disable=SC2068
    $mvn_cmd ${mvn_args[@]}

    # ============================================================
    # 8. 完成提示
    # ============================================================
    echo ""
    echo "============================================"
    echo "  🎉 项目生成完成！"
    echo "============================================"
    echo ""
    echo "📁 项目位置: $target_dir/$ARTIFACT_ID"
    echo ""
    echo "📋 下一步操作:"
    echo "   1. cd $target_dir/$ARTIFACT_ID"
    echo "   2. mvn clean install -DskipTests"
    echo "   3. 导入 IDE 开始开发"
    echo ""

    # 平台特定 IDE 提示
    case "$OS_TYPE" in
        windows)
            echo "💡 IDE 推荐:"
            echo "   - IntelliJ IDEA (https://www.jetbrains.com/idea/)"
            echo "   - 打开目录后等待 Maven 索引完成"
            ;;
        mac)
            echo "💡 IDE 推荐:"
            echo "   - IntelliJ IDEA: brew install --cask intellij-idea-ce"
            echo "   - 或 VS Code:      brew install --cask visual-studio-code"
            ;;
        linux)
            echo "💡 IDE 推荐:"
            echo "   - IntelliJ IDEA (https://www.jetbrains.com/idea/)"
            echo "   - 或使用 IDE 直接打开项目目录"
            ;;
    esac
    echo ""
}

# ============================================================
# MAIN
# ============================================================
main() {
    echo ""
    echo "============================================"
    echo "  DDD 六边形架构项目脚手架生成工具"
    echo "  版本: v2.0 (跨平台版)"
    echo "============================================"

    # 1. 检测环境
    check_environment

    # 2. 平台配置 & 获取目标目录
    TARGET_DIR=$(platform_config)

    # 3. 收集参数
    collect_params

    # 4. 确认并生成
    confirm_and_generate "$TARGET_DIR"
}

main "$@"
