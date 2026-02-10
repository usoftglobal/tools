#!/bin/bash

# Ubuntu系统初始化脚本
# 功能：安装zsh、golang、nodejs、supervisor、redis、mysql等组件
# 使用方法：
#   基础用法: bash install.sh
#   添加SSH密钥: bash install.sh "your-ssh-public-key"
#   添加GitHub Token: bash install.sh "your-ssh-public-key" "github-personal-access-token"

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本需要root权限运行"
        exit 1
    fi
}

# 更新系统
update_system() {
    log "更新系统包..."
    apt update -y
    apt upgrade -y
    apt install -y curl wget git build-essential software-properties-common jq lsb-release gnupg
}

# 安装zsh和插件
install_zsh() {
    log "安装zsh和oh-my-zsh..."
    apt install -y zsh
    
    # 获取当前用户信息
    CURRENT_USER=${SUDO_USER:-$USER}
    if [ "$CURRENT_USER" = "root" ] || [ -z "$CURRENT_USER" ]; then
        USER_HOME="/root"
        TARGET_USER="root"
    else
        USER_HOME="/home/$CURRENT_USER"
        TARGET_USER="$CURRENT_USER"
    fi
    
    # 为目标用户创建基础.zshrc，避免配置向导
    sudo -u $TARGET_USER touch $USER_HOME/.zshrc
    
    # 设置默认shell - 使用usermod代替chsh避免密码提示
    usermod -s $(which zsh) $TARGET_USER
    
    # 为所有新用户创建默认zsh配置
    mkdir -p /etc/skel
    touch /etc/skel/.zshrc
    
    # 切换到目标用户安装oh-my-zsh
    sudo -u $TARGET_USER sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    
    # 安装zsh插件
    sudo -u $TARGET_USER git clone https://github.com/zsh-users/zsh-autosuggestions $USER_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions || true
    sudo -u $TARGET_USER git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $USER_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting || true
    
    # 配置.zshrc
    sudo -u $TARGET_USER sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' $USER_HOME/.zshrc
    
    # 添加Go和其他环境变量到用户的.zshrc
    echo 'export PATH=$PATH:/usr/local/go/bin' >> $USER_HOME/.zshrc
    
    log "zsh为用户 $TARGET_USER 安装完成"
}

# 获取架构
get_arch() {
    case $(uname -m) in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l) echo "armv6l" ;;
        *) echo "unsupported" ;;
    esac
}

# 安装golang
install_golang() {
    log "安装Golang最新稳定版..."
    ARCH=$(get_arch)
    
    if [[ "$ARCH" == "unsupported" ]]; then
        error "不支持的系统架构"
        return 1
    fi
    
    # 获取最新稳定版本
    LATEST_GO=$(curl -s https://go.dev/dl/?mode=json | jq -r '.[] | select(.stable == true) | .version' | head -1)
    
    if [[ -z "$LATEST_GO" ]]; then
        error "无法获取Golang最新版本"
        return 1
    fi
    
    log "下载Golang ${LATEST_GO} for ${ARCH}..."
    wget -q "https://go.dev/dl/${LATEST_GO}.linux-${ARCH}.tar.gz" -O /tmp/go.tar.gz
    
    # 清理旧版本
    rm -rf /usr/local/go
    
    # 解压到/usr/local
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz
    
    # 创建软链接
    ln -sf /usr/local/go/bin/go /usr/local/bin/go
    ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
    
    # 设置环境变量
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.zshrc
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    
    log "Golang ${LATEST_GO} 安装完成"
}

# 安装nodejs
install_nodejs() {
    log "安装Node.js最新稳定版..."
    
    # 使用NodeSource仓库安装最新LTS版本
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt install -y nodejs
    
    # 安装yarn
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/yarn-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/yarn-keyring.gpg] https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
    apt update -y
    apt install -y yarn
    
    log "Node.js和Yarn安装完成"
}

# 配置SSH密钥
setup_ssh_key() {
    if [[ -z "$1" ]]; then
        warning "未提供SSH公钥，跳过SSH密钥配置"
        warning "请手动添加你的SSH公钥到 ~/.ssh/authorized_keys"
        return
    fi
    
    log "配置SSH密钥..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    
    echo "$1" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    
    log "SSH密钥配置完成"
}

# 配置GitHub访问
setup_github_access() {
    GITHUB_TOKEN="$1"
    
    log "配置GitHub访问..."
    
    # 方案1：使用Personal Access Token（推荐）
    if [[ -n "$GITHUB_TOKEN" ]]; then
        log "使用GitHub Personal Access Token配置..."
        
        # 配置git使用token
        git config --global credential.helper store
        
        # 创建.netrc文件用于自动认证
        cat > ~/.netrc <<EOF
machine github.com
login token
password $GITHUB_TOKEN
EOF
        chmod 600 ~/.netrc
        
        # 配置git使用token进行https访问
        git config --global url."https://token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
        git config --global url."https://token:${GITHUB_TOKEN}@github.com/".insteadOf "git@github.com:"
        
        log "GitHub Token配置完成，可以直接克隆私有仓库了"
        echo -e "${GREEN}测试命令：git clone https://github.com/你的用户名/你的私有仓库.git${NC}"
    else
        # 方案2：生成SSH密钥（需要手动添加到GitHub）
        log "生成GitHub SSH密钥..."
        
        # 生成新的SSH密钥
        ssh-keygen -t ed25519 -C "server-deploy-key" -f ~/.ssh/github_deploy_key -N ""
        
        # 配置SSH
        cat >> ~/.ssh/config <<EOF

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_deploy_key
    StrictHostKeyChecking no
EOF
        
        chmod 600 ~/.ssh/config
        
        log "GitHub SSH密钥已生成"
        echo -e "${YELLOW}注意：你需要手动将以下公钥添加到GitHub：${NC}"
        echo "=========================================="
        cat ~/.ssh/github_deploy_key.pub
        echo "=========================================="
        echo -e "${YELLOW}添加方法：${NC}"
        echo "1. 打开 https://github.com/settings/keys"
        echo "2. 点击 'New SSH key'"
        echo "3. 粘贴上面的公钥内容"
        echo ""
        echo -e "${GREEN}推荐方案：使用Personal Access Token${NC}"
        echo "1. 访问 https://github.com/settings/tokens"
        echo "2. 生成新的token（勾选repo权限）"
        echo "3. 重新运行脚本：bash install.sh \"ssh-key\" \"your-github-token\""
    fi
}

# 安装Supervisor
install_supervisor() {
    log "安装Supervisor..."
    apt install -y supervisor
    
    # 启动并设置开机自启
    systemctl enable supervisor
    systemctl start supervisor
    
    log "Supervisor安装完成"
}

# 安装Redis
install_redis() {
    log "安装Redis最新版..."
    
    # 添加Redis官方仓库
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    apt update -y
    apt install -y redis-server redis-tools
    
    # 确保Redis服务停止，以便修改配置
    systemctl stop redis-server || true
    
    # 配置Redis - 保持默认6379端口，设置密码，允许远程访问
    sed -i 's/^# requirepass foobared/requirepass Apple1992/' /etc/redis/redis.conf
    sed -i 's/^bind 127.0.0.1.*/bind 0.0.0.0/' /etc/redis/redis.conf
    sed -i 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf
    
    # 启动Redis
    systemctl start redis-server
    systemctl enable redis-server
    
    # 等待服务启动
    sleep 2
    
    # 检查服务状态
    if systemctl is-active --quiet redis-server; then
        log "Redis安装完成，监听端口：6379，密码：Apple1992"
        # 测试连接
        redis-cli -a Apple1992 ping &>/dev/null && log "Redis连接测试成功" || warning "Redis连接测试失败"
    else
        error "Redis服务启动失败"
        systemctl status redis-server
    fi
}

# 安装MySQL 8
install_mysql() {
    log "安装MySQL 8..."
    
    # 预设MySQL安装选项，避免交互式提示
    export DEBIAN_FRONTEND=noninteractive
    
    # 安装MySQL
    apt install -y mysql-server
    
    # 确保MySQL服务运行
    systemctl start mysql
    systemctl enable mysql
    
    # 等待MySQL完全启动
    sleep 5
    
    # 先修改主配置文件中的bind-address
    if grep -q "bind-address" /etc/mysql/mysql.conf.d/mysqld.cnf; then
        sed -i 's/bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
    fi
    
    # 创建自定义配置文件（优先级更高）
    cat > /etc/mysql/mysql.conf.d/custom.cnf <<EOF
[mysqld]
bind-address = 0.0.0.0
port = 3306
EOF
    
    # 重启MySQL使配置生效
    systemctl restart mysql
    
    # 等待重启完成
    sleep 5
    
    # 设置root密码并配置远程访问
    mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'Apple1992';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY 'Apple1992';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
    
    if [ $? -eq 0 ]; then
        log "MySQL 8安装完成，监听端口：3306，root密码：Apple1992"
        # 测试连接
        mysql -uroot -pApple1992 -e "SELECT VERSION();" &>/dev/null && log "MySQL连接测试成功" || warning "MySQL连接测试失败"
    else
        error "MySQL配置失败"
        systemctl status mysql
    fi
}

# 检查服务状态
check_services() {
    log "检查服务状态..."
    echo ""
    echo "========== 服务状态检查 =========="
    
    # 检查Redis
    if systemctl is-active --quiet redis-server; then
        REDIS_PORT=$(ss -tlnp 2>/dev/null | grep redis-server | awk '{print $4}' | cut -d: -f2 | head -1)
        echo "✓ Redis: 运行中 (端口: ${REDIS_PORT:-未检测到})"
    else
        echo "✗ Redis: 未运行"
    fi
    
    # 检查MySQL
    if systemctl is-active --quiet mysql; then
        MYSQL_PORT=$(ss -tlnp 2>/dev/null | grep mysqld | awk '{print $4}' | cut -d: -f2 | head -1)
        echo "✓ MySQL: 运行中 (端口: ${MYSQL_PORT:-未检测到})"
    else
        echo "✗ MySQL: 未运行"
    fi
    
    # 检查Supervisor
    if systemctl is-active --quiet supervisor; then
        echo "✓ Supervisor: 运行中"
    else
        echo "✗ Supervisor: 未运行"
    fi
    
    echo "=================================="
    echo ""
    
    # 显示端口监听情况
    log "端口监听情况:"
    ss -tlnp 2>/dev/null | grep -E '(6379|3306)' || echo "未检测到Redis(6379)或MySQL(3306)端口"
}

# 清理工作
cleanup() {
    log "执行清理工作..."
    apt autoremove -y
    apt autoclean -y
    
    # 检查服务状态
    check_services
}

# 创建使用说明
create_usage_doc() {
    cat > ~/server-init-summary.txt <<EOF
Ubuntu服务器初始化完成摘要
==========================
生成时间: $(date)

已安装组件:
-----------
1. zsh + oh-my-zsh + 插件
   - zsh-autosuggestions
   - zsh-syntax-highlighting

2. Golang: $(go version 2>/dev/null | awk '{print $3}')
   - 安装路径: /usr/local/go
   - 二进制文件: /usr/local/bin/go

3. Node.js: $(node -v 2>/dev/null)
   - npm: $(npm -v 2>/dev/null)
   - Yarn: $(yarn -v 2>/dev/null)

4. Supervisor
   - 配置目录: /etc/supervisor/conf.d/
   - 管理命令: supervisorctl

5. Redis
   - 端口: 6379 (允许远程访问)
   - 密码: Apple1992
   - 配置文件: /etc/redis/redis.conf

6. MySQL 8
   - 端口: 3306 (允许远程访问)
   - root密码: Apple1992
   - 配置文件: /etc/mysql/mysql.conf.d/custom.cnf

GitHub访问配置:
--------------
$(if [[ -n "$GITHUB_TOKEN" ]]; then
    echo "✓ 已配置Personal Access Token"
    echo "  可直接使用: git clone https://github.com/用户名/私有仓库.git"
else
    echo "✗ 未配置Token，使用SSH密钥方式"
    echo "  SSH公钥位置: ~/.ssh/github_deploy_key.pub"
    echo "  请添加到GitHub后使用: git clone git@github.com:用户名/私有仓库.git"
fi)

常用命令:
---------
- 切换到zsh: exec zsh
- 查看Redis状态: systemctl status redis-server
- 查看MySQL状态: systemctl status mysql
- 管理Supervisor: supervisorctl
- 测试GitHub连接: ssh -T git@github.com
- 测试Redis连接: redis-cli -a Apple1992 ping
- 测试MySQL连接: mysql -uroot -pApple1992 -e "SELECT VERSION();"

安全建议:
---------
1. 定期更新系统: apt update && apt upgrade
2. 修改默认密码（Redis/MySQL）
3. 配置云服务商安全组规则
4. 定期备份重要数据

EOF
    
    log "使用说明已保存到: ~/server-init-summary.txt"
}

# 主函数
main() {
    check_root
    
    log "开始Ubuntu系统初始化..."
    
    # 获取参数
    SSH_PUBLIC_KEY="$1"
    GITHUB_TOKEN="$2"
    
    # 显示配置信息
    echo "========== 配置信息 =========="
    echo "SSH公钥: $(if [[ -n "$SSH_PUBLIC_KEY" ]]; then echo "已提供"; else echo "未提供"; fi)"
    echo "GitHub Token: $(if [[ -n "$GITHUB_TOKEN" ]]; then echo "已提供"; else echo "未提供"; fi)"
    echo "=============================="
    echo ""
    
    # 执行安装步骤
    update_system
    install_zsh
    install_golang
    install_nodejs
    setup_ssh_key "$SSH_PUBLIC_KEY"
    setup_github_access "$GITHUB_TOKEN"
    install_supervisor
    install_redis
    install_mysql
    cleanup
    create_usage_doc
    
    log "系统初始化完成！"
    echo ""
    echo "========== 安装摘要 =========="
    echo "✓ zsh + oh-my-zsh + 插件"
    echo "✓ Golang $(go version 2>/dev/null | awk '{print $3}')"
    echo "✓ Node.js $(node -v 2>/dev/null)"
    echo "✓ Yarn $(yarn -v 2>/dev/null)"
    echo "✓ Supervisor"
    echo "✓ Redis (端口: 6379, 密码: Apple1992)"
    echo "✓ MySQL 8 (端口: 3306, root密码: Apple1992)"
    if [[ -n "$GITHUB_TOKEN" ]]; then
        echo "✓ GitHub Token已配置"
    else
        echo "! GitHub需手动配置SSH密钥"
    fi
    echo "=============================="
    echo ""
    
    if [[ -z "$GITHUB_TOKEN" ]]; then
        warning "获取GitHub Personal Access Token的方法："
        echo "1. 访问 https://github.com/settings/tokens/new"
        echo "2. 填写Note（如：Server Deploy Token）"
        echo "3. 设置过期时间（建议：No expiration）"
        echo "4. 勾选权限：repo（完整的仓库访问权限）"
        echo "5. 点击 Generate token"
        echo "6. 复制生成的token"
        echo ""
        echo "然后重新运行脚本："
        echo 'bash install.sh "你的SSH公钥" "你的GitHub-Token"'
        echo ""
    fi
    
    echo "详细信息请查看: cat ~/server-init-summary.txt"
    echo ""
    echo "立即切换到zsh请执行: exec zsh"
}

# 执行主函数
main "$@"
