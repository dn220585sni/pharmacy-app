#!/bin/bash
# Deploy Flutter web build to GitHub Pages
# Usage: ./deploy_web.sh

set -e

REPO_URL="https://github.com/dn220585sni/pharmacy-app.git"
BUILD_DIR="build/web"
DEPLOY_DIR="/tmp/pharmacy-app-deploy"

echo "🏗  Building Flutter web..."
flutter build web --release --base-href "/pharmacy-app/"

echo "📦 Preparing deployment..."
rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"
cp -R "$BUILD_DIR/"* "$DEPLOY_DIR/"

cd "$DEPLOY_DIR"
git init
git config user.email "deploy@pharmacy-app"
git config user.name "Deploy Bot"
git checkout -b gh-pages
git add -A
git commit -m "Deploy pharmacy-app to GitHub Pages"

echo "🚀 Pushing to GitHub..."
git remote add origin "$REPO_URL"
git push -u origin gh-pages --force

echo ""
echo "✅ Done! Your app will be available at:"
echo "   https://dn220585sni.github.io/pharmacy-app/"
echo ""
echo "⏳ GitHub Pages may take 1-2 minutes to activate."
