# ===============================================
# Docker One-Click Installation Script 
# ===============================================

# Exit immediately if a command exits with a non-zero status
set -e

# 1. Update system dependencies
echo ">> Updating system dependencies..."
sudo apt update
sudo apt upgrade -y

# 2. Install Docker (Official source first, with fallback mirrors)
echo ">> Installing Docker (Official source with fallback mirrors)..."
# Try official get.docker.com first
if sudo curl -fsSL https://get.docker.com | bash; then
    echo "Docker installed successfully from official source."
else
    echo "Warning: Official installation failed, trying alternative mirror (for China mainland users)..."
    if sudo curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun; then
        echo "Docker installed successfully from Aliyun mirror."
    else
        echo "Warning: Aliyun mirror failed, trying GitHub mirror..."
        if sudo curl -fsSL https://github.com/tech-shrimp/docker_installer/releases/download/latest/linux.sh | bash -s docker --mirror Aliyun; then
            echo "Docker installed successfully from GitHub mirror."
        else
            echo "Warning: GitHub mirror failed, trying Gitee mirror..."
            if sudo curl -fsSL https://gitee.com/tech-shrimp/docker_installer/releases/download/latest/linux.sh | bash -s docker --mirror Aliyun; then
                echo "Docker installed successfully from Gitee mirror."
            else
                echo "Error: Docker installation failed. Please check network connection or install manually."
                exit 1
            fi
        fi
    fi
fi

# 3. Check Docker version
echo ">> Checking Docker version..."
docker --version

# 4. Check docker compose command
echo ">> Checking docker compose plugin..."
if ! docker compose version &> /dev/null; then
    echo "Warning: 'docker compose' command not detected. This may indicate incomplete Docker installation."
    echo "You may need to install it manually or re-run the installation script."
    # Exit without proceeding
    exit 1
fi
echo "docker compose version: $(docker compose version)"

# 5. Add user permissions
echo ">> Adding current user to docker group..."
sudo usermod -aG docker $USER

echo "==============================================="
echo "All steps completed!"
echo "To apply permission changes, please re-login to your server or restart the system."
echo "After re-login, you can use 'docker' commands directly without 'sudo'."
echo "==============================================="