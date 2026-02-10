#!/bin/bash
set -e

VERSION="1.0.0"
SCRIPT_NAME=$(basename "$0")

show_help() {
  cat <<HELP
$SCRIPT_NAME v$VERSION
一键拉取任意 Docker 镜像到本地 Minikube（通过 GitHub Actions）

用法:
  $SCRIPT_NAME [选项] <镜像1> [镜像2] ...

选项:
  -p, --platform <平台>   目标平台（默认: linux/amd64）
  -h, --help             显示此帮助
  -v, --version          显示版本

示例:
  $SCRIPT_NAME registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.5
  $SCRIPT_NAME -p linux/arm64 gcr.io/xxx:tag

要求:
  - GITHUB_TOKEN 环境变量（Personal Access Token）
  - GITHUB_REPO 环境变量（如 yourname/offline-pull）
  - minikube, curl, jq, unzip 已安装
HELP
}

PLATFORM="linux/amd64"
IMAGES=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--platform) PLATFORM="$2"; shift 2 ;;
    -h|--help) show_help; exit 0 ;;
    -v|--version) echo "$SCRIPT_NAME v$VERSION"; exit 0 ;;
    -*) echo "未知选项: $1" >&2; show_help >&2; exit 1 ;;
    *) IMAGES+=("$1"); shift ;;
  esac
done

if [ ${#IMAGES[@]} -eq 0 ]; then
  echo "错误: 至少需要一个镜像" >&2; show_help >&2; exit 1
fi

GITHUB_TOKEN="${GITHUB_TOKEN}"
GITHUB_REPO="${GITHUB_REPO}"

if [ -z "$GITHUB_TOKEN" ]; then echo "❌ 未设置 GITHUB_TOKEN"; exit 1; fi
if [ -z "$GITHUB_REPO" ]; then echo "❌ 未设置 GITHUB_REPO"; exit 1; fi

for cmd in curl jq unzip minikube; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "❌ 缺少依赖: $cmd"; exit 1
  fi
done

echo "📦 处理 ${#IMAGES[@]} 个镜像 (平台: $PLATFORM):"
printf '  - %s\n' "${IMAGES[@]}"

IMAGE_LIST=$(printf "%s\n" "${IMAGES[@]}")

echo "🚀 触发 GitHub Actions..."
curl -fsS -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$GITHUB_REPO/actions/workflows/build-and-upload.yml/dispatches" \
  -d "{\"ref\":\"main\",\"inputs\":{\"images\":\"$IMAGE_LIST\",\"platform\":\"$PLATFORM\"}}" \
  >/dev/null

echo "✅ 工作流已触发，请稍候（首次约1-2分钟）..."

# 简化版：提示用户手动等待（完整自动版见前文，此处为教学简化）
echo "💡 请访问以下链接查看进度："
echo "   https://github.com/$GITHUB_REPO/actions"
echo ""
echo "构建成功后，下载 artifact 并运行："
echo "   unzip offline-images.zip"
echo "   minikube image load *.tar"
