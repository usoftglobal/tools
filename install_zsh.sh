#!/bin/bash

# 安装 zsh
echo "Installing zsh..."
sudo apt update
sudo apt install zsh net-tools build-essential git -y

# 安装 oh-my-zsh
echo "Installing oh-my-zsh..."
sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" || {
    echo "Failed to install oh-my-zsh using curl. Please download the script manually, make it executable, and run it."
    exit 1
}

# 克隆插件
echo "Cloning zsh-autosuggestions..."
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

echo "Cloning zsh-syntax-highlighting..."
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# 添加插件到 .zshrc
echo "Configuring .zshrc..."
sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc

# 切换到 zsh 并加载配置
# 立即使更改生效
echo "Applying changes in zsh..."
zsh -c "source ~/.zshrc"

echo "Zsh setup completed!"
