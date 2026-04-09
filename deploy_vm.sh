#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Deploy Flutter web build to VM (Windows IIS) via SMB shared folder.
#
# One-time setup on VM (Windows):
#   1. Share the IIS web folder (e.g. C:\inetpub\wwwroot\pharmacy-app)
#      Right-click folder → Properties → Sharing → Share → Everyone (Read/Write)
#   2. Note the share path: \\10.90.77.66\pharmacy-app
#
# One-time setup on Mac:
#   1. Run this script — it will mount the share and deploy
#   2. Or mount manually: mount_smbfs //user:pass@10.90.77.66/pharmacy-app /tmp/vm-deploy
#
# After setup, deploy is one command:
#   ./deploy_vm.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e

# ── Configuration ──────────────────────────────────────────────────────────
VM_IP="10.90.77.66"
SHARE_NAME="pharmacy-app"          # SMB share name on VM
MOUNT_POINT="/tmp/vm-deploy"       # Local mount point
IIS_BASE_HREF="/"                  # base-href for IIS root deploy

# ── Build ──────────────────────────────────────────────────────────────────
echo "Building Flutter web..."
cd "$(dirname "$0")"
/opt/homebrew/bin/flutter build web --release --base-href "$IIS_BASE_HREF"

# ── Mount SMB if not already mounted ───────────────────────────────────────
if ! mount | grep -q "$MOUNT_POINT"; then
  echo "Mounting \\\\$VM_IP\\$SHARE_NAME → $MOUNT_POINT"
  mkdir -p "$MOUNT_POINT"
  echo "Enter VM credentials (domain\\user or just user):"
  mount_smbfs "//$VM_IP/$SHARE_NAME" "$MOUNT_POINT"
fi

# ── Deploy ─────────────────────────────────────────────────────────────────
echo "Copying build to VM..."
# Remove old files (except web.config if exists)
find "$MOUNT_POINT" -mindepth 1 -not -name "web.config" -delete 2>/dev/null || true
# Copy new build
cp -R build/web/* "$MOUNT_POINT/"

echo ""
echo "Deployed to http://$VM_IP:8080/"
echo "Done!"
