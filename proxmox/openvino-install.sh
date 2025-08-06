#!/bin/bash

# Intel NPU Driver Installation Script for Frigate Docker Container
# Updated for v1.19.0 (July 2025) and OpenVINO 2025.1 compatibility
# Downloads drivers on host, then copies into container

set -e  # Exit on any error

CONTAINER_NAME="frigate"
DOWNLOAD_DIR="$HOME/npu-drivers"

echo "🚀 Installing Intel NPU drivers v1.19.0 in Frigate container..."

# Check if container exists and is running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo "❌ Frigate container not found or not running"
    echo "Make sure container '$CONTAINER_NAME' is running with: docker compose up -d"
    exit 1
fi

echo "📥 Downloading NPU drivers to host system..."

# Create download directory
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

# Clean up any existing packages
rm -f *.deb

# Download Intel NPU drivers v1.19.0 (Ubuntu 22.04 - most compatible)
echo "  • Intel NPU driver v1.19.0..."
wget -q https://github.com/intel/linux-npu-driver/releases/download/v1.19.0/intel-driver-compiler-npu_1.19.0.20250707-16111289554_ubuntu22.04_amd64.deb
wget -q https://github.com/intel/linux-npu-driver/releases/download/v1.19.0/intel-fw-npu_1.19.0.20250707-16111289554_ubuntu22.04_amd64.deb
wget -q https://github.com/intel/linux-npu-driver/releases/download/v1.19.0/intel-level-zero-npu_1.19.0.20250707-16111289554_ubuntu22.04_amd64.deb

# Download Level Zero v1.21.9 (latest compatible)
echo "  • Level Zero v1.22.4..."
wget https://github.com/oneapi-src/level-zero/releases/download/v1.22.4/level-zero_1.22.4+u22.04_amd64.deb

# Download dependencies from Debian repos
echo "  • Dependencies..."
wget -q http://ftp.us.debian.org/debian/pool/main/o/onetbb/libtbb12_2021.8.0-2_amd64.deb
wget -q http://ftp.us.debian.org/debian/pool/main/o/onetbb/libtbbbind-2-5_2021.8.0-2_amd64.deb
wget -q http://ftp.us.debian.org/debian/pool/main/o/onetbb/libtbbmalloc2_2021.8.0-2_amd64.deb
wget -q http://ftp.us.debian.org/debian/pool/main/h/hwloc/libhwloc15_2.9.0-1_amd64.deb

wget https://github.com/intel/intel-graphics-compiler/releases/download/v2.10.8/intel-igc-core-2_2.10.8+18926_amd64.deb
wget https://github.com/intel/intel-graphics-compiler/releases/download/v2.10.8/intel-igc-opencl-2_2.10.8+18926_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/25.13.33276.16/intel-level-zero-gpu-dbgsym_1.6.33276.16_amd64.ddeb
wget https://github.com/intel/compute-runtime/releases/download/25.13.33276.16/intel-level-zero-gpu_1.6.33276.16_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/25.13.33276.16/intel-opencl-icd-dbgsym_25.13.33276.16_amd64.ddeb
wget https://github.com/intel/compute-runtime/releases/download/25.13.33276.16/intel-opencl-icd_25.13.33276.16_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/25.13.33276.16/libigdgmm12_22.7.0_amd64.deb

echo "📦 Copying packages into Frigate container..."

# Copy all .deb files to container
for deb_file in *.deb; do
    echo "  • Copying $deb_file..."
    docker cp "$deb_file" "$CONTAINER_NAME:/tmp/"
done

echo "🔧 Installing packages in container..."

# Install packages inside container
docker exec "$CONTAINER_NAME" bash -c "
cd /tmp
echo 'Removing any conflicting packages...'
dpkg --purge --force-remove-reinstreq intel-driver-compiler-npu intel-fw-npu intel-level-zero-npu level-zero 2>/dev/null || true

echo 'Installing NPU packages...'
dpkg -i *.deb || {
    echo 'Fixing dependencies...'
    apt update -qq
    apt --fix-broken install -y -qq
    dpkg -i *.deb
}

echo 'Updating library cache...'
ldconfig

echo 'Cleaning up temp files...'
rm -f *.deb
"

echo "🔧 Updating OpenVINO in container..."

# Update OpenVINO with --break-system-packages since it's a container
docker exec "$CONTAINER_NAME" bash -c "
pip install --upgrade --quiet --break-system-packages openvino==2025.2.0
"

echo "🧪 Testing NPU detection..."

# Test NPU detection
docker exec "$CONTAINER_NAME" python3 -c "
try:
    from openvino import Core
    core = Core()
    devices = core.available_devices
    print('Available OpenVINO devices in Frigate:', devices)
    if 'NPU' in devices:
        print('✅ SUCCESS: NPU detected in Frigate container!')
        try:
            npu_name = core.get_property('NPU', 'FULL_DEVICE_NAME')
            print(f'NPU info: {npu_name}')
        except:
            print('NPU detected but detailed info unavailable')
    else:
        print('❌ NPU not detected. Available devices:', devices)
        print('Check that /dev/accel/accel0 is mounted in container')
except Exception as e:
    print(f'❌ OpenVINO test failed: {e}')
"

# Check NPU device access in container
echo "🔍 Checking NPU device access..."
docker exec "$CONTAINER_NAME" bash -c "
if [ -e /dev/accel/accel0 ]; then
    echo '✅ NPU device /dev/accel/accel0 is accessible'
    ls -la /dev/accel/accel0
else
    echo '❌ NPU device not found - check Docker device passthrough'
    echo 'Add to docker-compose.yaml:'
    echo '  devices:'
    echo '    - /dev/accel:/dev/accel'
fi
"

echo "🔄 Restarting Frigate container to complete setup..."
docker restart "$CONTAINER_NAME"

echo "⏳ Waiting for container to restart..."
sleep 8

echo "🧪 Final NPU verification..."
docker exec "$CONTAINER_NAME" python3 -c "
from openvino import Core
core = Core()
devices = core.available_devices
print('Final test - Available devices:', devices)
if 'NPU' in devices:
    print('🎉 NPU successfully installed and working!')
else:
    print('❌ NPU not detected after restart')
"

echo ""
echo "✅ Installation complete!"
echo ""
echo "📝 Next steps:"
echo "1. Update your Frigate config.yaml detector section:"
echo "   detectors:"
echo "     openvino:"
echo "       type: openvino"
echo "       device: NPU    # Changed from GPU to NPU"
echo ""
echo "2. Restart Frigate to use NPU:"
echo "   docker restart frigate"
echo ""
echo "3. Check Frigate logs for NPU usage:"
echo "   docker logs frigate | grep -i npu"
echo ""
echo "💾 Downloaded drivers saved in: $DOWNLOAD_DIR"
echo "⚠️  NOTE: These container changes are temporary and will be lost on container recreation."
echo "   Re-run this script after any Frigate updates."

# Clean up download directory if desired
#read -p "🗑️  Delete downloaded drivers? (y/N): " -n 1 -r
#read -p "Delete downloaded drivers? (y/N): " -n 1 -r
#echo
#if [[ $REPLY =~ ^[Yy]$ ]]; then
#    rm -rf "$DOWNLOAD_DIR"
#    echo "✅ Cleaned up downloaded files"
#else
#    echo "📁 Drivers saved in $DOWNLOAD_DIR for future use"
#fi
# Clean up download directory if desired
echo -n "Delete downloaded drivers? (y/N): "
read REPLY
echo
case "$REPLY" in
    [Yy]* ) rm -rf "$DOWNLOAD_DIR"
            echo "Cleaned up downloaded files" ;;
    * )     echo "Drivers saved in $DOWNLOAD_DIR for future use" ;;
esac