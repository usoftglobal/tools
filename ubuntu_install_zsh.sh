#!/bin/bash

# 1. 安装 zsh 和必要工具
echo "Installing zsh and dependencies..."
if [ -x "$(command -v apt)" ]; then
    sudo apt update
    sudo apt install zsh curl git -y
else
    echo "Not an apt-based system? Please install zsh manually."
fi

# 2. 安装 oh-my-zsh (关键修改：添加 --unattended)
# 如果目录已存在，跳过安装
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing oh-my-zsh..."
    # --unattended: 禁止安装完成后自动进入 zsh，保证脚本能继续跑
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    echo "oh-my-zsh already installed."
fi

# 3. 克隆插件 (使用标准路径变量)
ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}

echo "Cloning zsh-autosuggestions..."
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
fi

echo "Cloning zsh-syntax-highlighting..."
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
fi

# 4. 修改 .zshrc
echo "Configuring .zshrc..."
# 备份一下防止改坏
cp ~/.zshrc ~/.zshrc.bak

# 使用更稳健的 sed 写法，直接替换 plugins=(...) 
# 注意：这假设你的 .zshrc 是标准模板
sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc

# 5. 设置 Zsh 为默认 Shell
echo "Changing default shell to zsh..."
#这一步可能需要密码，或者你可以手动做
sudo chsh -s $(which zsh) $(whoami)

echo "✅ Setup completed!"
echo "--------------------------------------------------"
echo "插件已配置，请执行以下命令立即生效："
echo "    exec zsh"
echo "--------------------------------------------------"
