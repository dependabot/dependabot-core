#!/bin/bash

# Build Custom Dependabot Scanner Image
# This script builds a custom Docker image with all dependencies pre-installed

set -e

IMAGE_NAME="dependabot-scanner-local:latest"
DOCKERFILE="Dockerfile.local"

echo "🔨 Building custom dependabot scanner image..."
echo "📦 Image name: $IMAGE_NAME"
echo "📁 Dockerfile: $DOCKERFILE"

# Check if base image exists
if ! docker image inspect "dependabot/dependabot-core-development-bundler:latest" >/dev/null 2>&1; then
    echo "❌ Base image not found. Pulling dependabot/dependabot-core-development-bundler:latest..."
    docker pull dependabot/dependabot-core-development-bundler:latest
else
    echo "✅ Base image found: dependabot/dependabot-core-development-bundler"
fi

echo ""
echo "🔨 Building custom image from $DOCKERFILE..."
echo "   This may take several minutes on first build..."
echo "   💡 Tip: Subsequent builds will be much faster due to layer caching!"
echo "   💡 Script changes won't trigger gem reinstalls unless dependencies change."

# Build the image
docker build -f "$DOCKERFILE" -t "$IMAGE_NAME" .

echo ""
echo "✅ Custom image built successfully!"
echo "📦 Image: $IMAGE_NAME"

echo ""
echo "🚀 You can now use this image in your scan scripts:"
echo "   IMAGE_NAME=\"$IMAGE_NAME\""

echo ""
echo "💡 Benefits of this custom image:"
echo "   - No runtime dependency installation needed"
echo "   - Faster startup times"
echo "   - Simpler scripts (no volume management)"
echo "   - Pre-configured bundle paths"
echo "   - Optimized layer caching for faster script development"

echo ""
echo "🔍 To test the image:"
echo "   docker run --rm $IMAGE_NAME"

echo ""
echo "📊 Image size:"
docker images "$IMAGE_NAME"
