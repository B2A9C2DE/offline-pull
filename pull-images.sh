#!/bin/bash
set -e

VERSION="1.2.0"
SCRIPT_NAME=$(basename "$0")

show_help() {
  cat <<HELP
$SCRIPT_NAME v$VERSION
全自动拉取任意 Docker 镜像到本地 Minikube（通过 GitHub Actions）

用法:
  $SCRIPT_NAME [选项] <镜像1> [镜像2] ...

选项:
  -p, --platform <平台>   目标平台（默认: linux/amd64）
  -t, --timeout <秒>      超时时间（默认: 300 秒 = 5 分钟）
  -h, --help             显示此帮助
  -v, --version          显示版本

要求:
  - GITHUB_TOKEN 环境变量（Personal Access Token）
  - GITHUB_REPO 环境变量（如 yourname/offline-pull）
  - minikube, curl, jq, unzip 已安装
HELP
}

PLATFORM="linux/amd64"
TIMEOUT=300
IMAGES=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--platform) PLATFORM="$2"; shift 2 ;;
    -t|--timeout) TIMEOUT="$2"; shift 2 ;;
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

# === 新增：自动获取默认分支 ===
echo "🔍 获取仓库默认分支..."
DEFAULT_BRANCH=$(curl -fsS -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$GITHUB_REPO" | jq -r '.default_branch')

if [ -z "$DEFAULT_BRANCH" ] || [ "$DEFAULT_BRANCH" = "null" ]; then
  echo "❌ 无法获取默认分支，请检查仓库是否存在且 token 有权限"
  exit 1
fi
echo "✅ 默认分支: $DEFAULT_BRANCH"

IMAGE_LIST=$(printf "%s\n" "${IMAGES[@]}")

echo "🚀 触发 GitHub Actions (分支: $DEFAULT_BRANCH)..."
response=$(curl -fsS -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$GITHUB_REPO/actions/workflows/build-and-upload.yml/dispatches" \
  -d "{\"ref\":\"$DEFAULT_BRANCH\",\"inputs\":{\"images\":\"$IMAGE_LIST\",\"platform\":\"$PLATFORM\"}}" \
  -w "%{http_code}" --output /dev/null)

if [ "$response" != "204" ]; then
  echo "❌ 触发失败，请检查 GITHUB_TOKEN 和仓库权限"
  exit 1
fi

echo "✅ 工作流已触发，等待运行完成..."

# === 增强版：获取最新运行 ID（查询所有状态 + 默认分支）===
echo "⏳ 等待 GitHub 创建工作流运行记录..."
sleep 8

run_id=""
max_attempts=25
for ((i=1; i<=max_attempts; i++)); do
  echo -n "  尝试 $i/$max_attempts... "

  # 查询所有状态（包括 completed！因为可能跑得很快）
  response=$(curl -fsS -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_REPO/actions/workflows/build-and-upload.yml/runs?branch=$DEFAULT_BRANCH" 2>/dev/null) || {
    echo "API 请求失败"
    sleep 3
    continue
  }

  count=$(echo "$response" | jq '.workflow_runs | length' 2>/dev/null || echo 0)
  if [ "$count" -gt 0 ]; then
    # 取最新的一次（按 created_at 排序，GitHub 默认降序）
    run_id=$(echo "$response" | jq -r '.workflow_runs[0].id // empty')
    status=$(echo "$response" | jq -r '.workflow_runs[0].status // empty')
    if [ -n "$run_id" ] && [ "$run_id" != "null" ] && [ -n "$status" ]; then
      echo "找到运行 ID: $run_id (状态: $status)"
      break
    fi
  fi

  echo "未找到运行"
  sleep 3
done

if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
  echo ""
  echo "❌ 超时：未检测到任何运行。"
  echo "   请手动检查: https://github.com/$GITHUB_REPO/actions"
  exit 1
fi

echo "🔍 监控运行: https://github.com/$GITHUB_REPO/actions/runs/$run_id"

# 轮询状态（即使已 completed 也继续）
start_time=$(date +%s)
while true; do
  resp=$(curl -fsS -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_REPO/actions/runs/$run_id")
  status=$(echo "$resp" | jq -r '.status')
  conclusion=$(echo "$resp" | jq -r '.conclusion // empty')

  if [ "$status" = "completed" ]; then
    if [ "$conclusion" = "success" ]; then
      echo "🎉 工作流成功完成！"
      break
    else
      echo "❌ 工作流失败（$conclusion）"
      exit 1
    fi
  elif [[ "$status" == "queued" || "$status" == "in_progress" || "$status" == "running" ]]; then
    :
  else
    echo "❓ 未知状态: $status"
    exit 1
  fi

  current_time=$(date +%s)
  elapsed=$((current_time - start_time))
  if [ $elapsed -ge $TIMEOUT ]; then
    echo -e "\n⏰ 超时（$TIMEOUT 秒）"
    exit 1
  fi

  printf "."
  sleep 4
done

# 下载 artifact
echo -e "\n📥 下载 artifact..."
artifact_url=$(curl -fsS -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$GITHUB_REPO/actions/runs/$run_id/artifacts" \
  | jq -r '.artifacts[] | select(.name == "offline-images") .archive_download_url')

if [ -z "$artifact_url" ] || [ "$artifact_url" = "null" ]; then
  echo "❌ 未找到 artifact 'offline-images'"
  exit 1
fi

curl -fsS -L -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "$artifact_url" -o offline-images.zip

# 解压并导入
echo "📤 解压并导入 Minikube..."
rm -rf offline-images && mkdir offline-images
unzip -q offline-images.zip -d offline-images
minikube image load offline-images/*.tar

echo "✅ 所有镜像已成功导入 Minikube！"
echo "🔍 验证命令: minikube image list"
