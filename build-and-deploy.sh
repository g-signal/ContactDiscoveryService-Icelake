#!/bin/bash
set -e

# CDSI Docker Build and Deploy Script
# Based on config/build.properties configuration

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/build.properties"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# 读取配置函数
read_config() {
    local key=$1
    grep "^$key=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 || echo ""
}

# 读取配置
DOCKER_REPO=$(read_config "docker.repo")
BUILD_PUSH=$(read_config "build.push")
LATEST_TAG=$(read_config "build.latest_tag")
BUILD_OPTIMIZATION=$(read_config "build.optimization")

echo "🚀 CDSI Docker Build and Deploy Script"
echo "======================================="
echo "Docker Repository: $DOCKER_REPO"
echo "Build Push: $BUILD_PUSH"
echo "Latest Tag: $LATEST_TAG"
echo "Optimization: $BUILD_OPTIMIZATION"
echo ""

# 验证必要配置
if [ -z "$DOCKER_REPO" ]; then
    echo "❌ docker.repo not configured in build.properties"
    exit 1
fi

# Step 1: 清理和准备
echo "🧹 Cleaning previous builds..."
mvn clean
echo "✅ Clean completed"

# 可选: 清理Docker缓存
# docker system prune -f --filter "until=24h"

# Step 2: 构建SGX Enclave
echo "🔐 Building SGX Enclave..."
if [ "$BUILD_OPTIMIZATION" = "native" ]; then
    echo "Building production enclave..."
    mvn compile exec:exec@build-enclave
else
    echo "Building development enclave..."
    mvn compile exec:exec@build-dev-enclave
fi
echo "✅ SGX Enclave build completed"

# Step 3: 构建Java应用
echo "☕ Building Java application..."
mvn package -DskipTests
echo "✅ Java application build completed"

# 获取版本信息
APP_VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout 2>/dev/null || echo "unknown")
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BUILD_TAG="${APP_VERSION}-${TIMESTAMP}"
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

echo "📦 Application Version: $APP_VERSION"
echo "🏷️  Build Tag: $BUILD_TAG"
echo "🔗 Git Commit: $GIT_COMMIT"

# Step 4: 构建Docker镜像
echo "🐳 Building Docker images..."

# 构建主镜像
echo "Building main image: ${DOCKER_REPO}/cdsi:${BUILD_TAG}"
docker build \
    --platform linux/amd64 \
    --build-arg APP_VERSION="$APP_VERSION" \
    --build-arg BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --build-arg GIT_COMMIT="$GIT_COMMIT" \
    -t "${DOCKER_REPO}/cdsi:${BUILD_TAG}" \
    -t "${DOCKER_REPO}/cdsi:${APP_VERSION}" \
    .

echo "✅ Docker image built successfully"

# Latest标签
if [ "$LATEST_TAG" = "true" ]; then
    echo "🏷️  Tagging as latest..."
    docker tag "${DOCKER_REPO}/cdsi:${APP_VERSION}" "${DOCKER_REPO}/cdsi:latest"
    echo "✅ Latest tag created"
fi


# Step 5: 镜像上传
if [ "$BUILD_PUSH" = "true" ]; then
    echo "📤 Pushing Docker images..."

    # 检查Docker登录状态
    if ! docker info > /dev/null 2>&1; then
        echo "❌ Docker is not running or accessible"
        exit 1
    fi

    # 推送构建标签
    echo "Pushing ${DOCKER_REPO}/cdsi:${BUILD_TAG}..."
    docker push "${DOCKER_REPO}/cdsi:${BUILD_TAG}"

    echo "Pushing ${DOCKER_REPO}/cdsi:${APP_VERSION}..."
    docker push "${DOCKER_REPO}/cdsi:${APP_VERSION}"

    # 推送latest标签
    if [ "$LATEST_TAG" = "true" ]; then
        echo "Pushing ${DOCKER_REPO}/cdsi:latest..."
        docker push "${DOCKER_REPO}/cdsi:latest"
    fi

    echo "✅ All images pushed successfully!"
else
    echo "⏭️  Skipping push (build.push=false in config)"
fi

# Step 6: 显示镜像信息
echo "📊 Built images:"
docker images "${DOCKER_REPO}/cdsi" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | head -10

# Step 7: 可选清理
echo ""
read -p "🧹 Clean up intermediate Docker layers? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker image prune -f
    echo "✅ Docker cleanup completed"
fi

echo ""
echo "🎉 Build and deploy completed successfully!"
echo "📊 Summary:"
echo "   Repository: ${DOCKER_REPO}/cdsi"
echo "   Version: $APP_VERSION"
echo "   Build Tag: $BUILD_TAG"
echo "   Latest Tag: $LATEST_TAG"
echo "   Pushed: $BUILD_PUSH"
echo "   Git Commit: $GIT_COMMIT"
echo ""

# 提供运行示例
if [ "$BUILD_PUSH" = "true" ]; then
    echo "🚀 To run the container:"
    echo "   docker run -p 8080:8080 \\"
    echo "     -e ENCLAVE_TOKEN_SECRET=\"\$(openssl rand -hex 32)\" \\"
    echo "     ${DOCKER_REPO}/cdsi:${APP_VERSION}"
    echo ""
    echo "🔍 To check health:"
    echo "   curl http://localhost:8080/health"
fi

echo "✨ Done!"
