#!/usr/bin/env sh

# Load the environment variables from the .env file
if [ -f "$(dirname "$0")/.env" ]; then
    export $(cat "$(dirname "$0")/.env" | xargs)
else
    echo "Error: .env file not found. Copy .env.example and set the configuration properly"
    exit 1
fi

# Ensure git is installed
if ! command -v git > /dev/null 2>&1; then
    echo "Git not installed. Installing..."
    sudo apt-get update && sudo apt-get install git -y
fi

# Ensure Docker is installed
if ! command -v docker > /dev/null 2>&1; then
    echo "Docker not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce
    sudo usermod -aG docker $USER
fi

# Ensure Docker Compose is installed
if ! command -v docker-compose > /dev/null 2>&1; then
    echo "Docker Compose not installed. Installing..."
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Ensure npm (and Node.js) is installed
if ! command -v npm > /dev/null 2>&1; then
    echo "npm not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y nodejs npm
fi

# Clone the repo if it doesn't exist
if [ ! -d "${REPO_DIR}" ]; then
    git clone "${GITHUB_REPO}" "${REPO_DIR}"
fi


git lfs fetch
git lfs checkout
cp ./stratus_test_data.csv "./${REPO_DIR}/e2e/substrate-sync-mock-server/stratus_test_data.csv"
cd "${REPO_DIR}"

# Fetch latest changes without applying them
git fetch

if ! command -v perf > /dev/null 2>&1; then
    echo "perf not installed. Installing..."
    KERNEL_VERSION=$(uname -r)
    sudo apt-get update && sudo apt-get install -y linux-perf-$KERNEL_VERSION || sudo apt-get install -y linux-perf
fi

# Get the latest commit hash from origin/main and the last sent commit hash
LAST_COMMIT_FILE="./last_processed_commit.txt"
LATEST_COMMIT=$(git rev-parse origin/main)
LAST_SENT_COMMIT=$(cat "${LAST_COMMIT_FILE}" 2>/dev/null || echo "")

if ! command -v just > /dev/null 2>&1; then
    echo "just not installed. Attempting to install..."
    # Ensure Cargo is installed for just installation via Cargo
    if ! command -v cargo > /dev/null 2>&1; then
        echo "Cargo not installed. Installing..."
        # Install Rust and Cargo
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        source $HOME/.cargo/env
    fi
    cargo install just
fi

echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid
# Compare commit hashes
if [ "${LATEST_COMMIT}" != "${LAST_SENT_COMMIT}" ]; then
    # Pull the latest changes
    git pull origin main

    # Assuming 'just' commands are properly set up to use Docker and npm
    just setup
    just e2e-flamegraph

    # Send the flamegraph to Slack
    curl -F file=@flamegraph.svg \
         -F "initial_comment=New flamegraph generated for commit ${LATEST_COMMIT}" \
         -F channels="${SLACK_CHANNEL_ID}" \
         -F token="${SLACK_TOKEN}" \
         https://slack.com/api/files.upload

    # Update the last sent commit hash
    echo "${LATEST_COMMIT}" > "${LAST_COMMIT_FILE}"
else
    echo "No new commits to process."
fi
