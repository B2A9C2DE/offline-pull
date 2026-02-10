# 🐳 pull-images：一键将任意 Docker 镜像拉取到本地 Minikube

> 无需科学上网！通过 GitHub Actions 在云端拉取镜像 → 打包 → 自动导入你的 Minikube。

---

## ✅ 功能特点

- 支持任意镜像（Docker Hub、gcr.io、quay.io、私有仓库等）
- 自动适配平台（默认 `linux/amd64`，可指定 `linux/arm64`）
- 全自动：触发 → 等待 → 下载 → 导入 Minikube
- 无需手动操作浏览器

---

## 🔧 前提条件

1. **本地已安装**：
   - `minikube`
   - `curl`, `jq`, `unzip`
2. **GitHub 仓库**：
   - 公开仓库（如 `yourname/offline-pull`）
   - 包含工作流文件：`.github/workflows/build-and-upload.yml`
3. **GitHub Personal Access Token (PAT)**：
   - 权限：`repo` + `workflow`（Classic Token）

---

## 🚀 快速开始

### 1. 设置环境变量（只需一次）

```bash
# 替换为你的实际值
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
export GITHUB_REPO=yourname/offline-pull
```

### 2. 全局安装脚本
```bash
# 假设脚本在当前目录
sudo cp pull-images.sh /usr/local/bin/pull-images
sudo chmod +x /usr/local/bin/pull-images
```

### 3. 使用命令
```bash
# 拉取单个镜像（amd64）
pull-images nginx:alpine

# 拉取多个镜像
pull-images \
  k8s.gcr.io/metrics-server/metrics-server:v0.7.0 \
  docker.io/kubernetesui/dashboard:v2.7.0

# 指定 arm64 平台
pull-images -p linux/arm64 alpine:latest

# 自定义超时（单位：秒）
pull-images -t 600 busybox
```

### 4. 验证结果
```bash
minikube image list | grep your-image
```

---

## 🛠️ 故障排查
* "❌ 未设置 GITHUB_TOKEN" → 检查环境变量是否导出
* "❌ 无法下载 artifact" → 确保仓库是 Public（私有仓库需额外权限）
* 工作流失败 → 查看 Actions 页面

---

## 🌐 让命令全局可用（永久生效）

### 步骤 1：安装脚本到系统路径

```bash
# 进入脚本目录
cd /mnt/c/Users/C2DEB2A9/Desktop/100-work/110-devops/111-code/script/offline-pull

# 复制并重命名
sudo cp pull-images.sh /usr/local/bin/pull-images
sudo chmod +x /usr/local/bin/pull-images
```

### 步骤 2：设置环境变量（永久）
```bash
# 编辑 ~/.bashrc（或 ~/.zshrc 如果你用 zsh）
cat >> ~/.bashrc <<EOF

# pull-images configuration
export GITHUB_TOKEN="ghp_your_actual_token_here"
export GITHUB_REPO="B2A9C2DE/offline-pull"
EOF
```
> 🔐 安全提示：确保你的 token 不被提交到 Git！


### 步骤 3：重新加载配置
```bash
source ~/.bashrc
```

### 步骤 4：验证
```bash
pull-images -v
# 输出：pull-images.sh v1.3.0

pull-images hello-world
# 应该全自动完成！
```


