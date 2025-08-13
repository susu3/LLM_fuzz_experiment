# 安装配置指南

## 系统要求

- Linux服务器环境
- Docker 和 Docker Compose
- Python 3.6+
- Git
- 至少32GB内存和500GB磁盘空间（用于存储模糊测试结果）

## 安装步骤

### 1. 克隆项目

```bash
git clone <repository_url>
cd LLM_fuzz_experiment
```

### 2. 安装依赖

```bash
# 安装Python依赖
pip3 install PyYAML

# 确保Docker可用
sudo systemctl start docker
sudo usermod -aG docker $USER
```

### 3. 设置SSH密钥

由于工具仓库是私有的，需要设置SSH密钥：

```bash
# 如果还没有SSH密钥
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"

# 将公钥添加到GitHub账户
cat ~/.ssh/id_rsa.pub
# 复制输出并添加到GitHub -> Settings -> SSH Keys
```

### 4. 验证权限

```bash
# 验证可以访问私有仓库
ssh -T git@github.com
git clone git@github.com:susu3/AFL-ICS.git /tmp/test-clone
rm -rf /tmp/test-clone
```

### 5. 准备测试目标

确保libmodbus在正确位置：

```bash
# 检查libmodbus是否存在
ls -la /home/ecs-user/libmodbus

# 如果需要，从其他位置复制
# cp -r /path/to/libmodbus /home/ecs-user/
```

## 配置网络代理

如果需要通过代理访问外网：

```bash
export HTTPS_PROXY=http://hwcloud-hk.ring0.me:48527
export HTTP_PROXY=http://hwcloud-hk.ring0.me:48527
```

## 设置LLM API密钥

```bash
export LLM_API_KEY=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
```

## 验证安装

```bash
# 验证脚本可执行
./scripts/setup_target.sh libmodbus

# 检查生成的文件
ls -la dockerfiles/
ls -la targets/libmodbus/
```

## 故障排除

### 权限问题
```bash
# 如果遇到权限问题
sudo chown -R $USER:$USER .
chmod +x scripts/*.sh
```

### Docker问题
```bash
# 重启Docker服务
sudo systemctl restart docker

# 清理Docker缓存
docker system prune -a
```

### 网络问题
```bash
# 测试GitHub连接
ssh -T git@github.com

# 测试代理
curl --proxy http://hwcloud-hk.ring0.me:48527 https://github.com
```
