#!/usr/bin/env sh

# Load the environment variables from the .env file
if [ -f "$(dirname "$0")/.env" ]; then
    export $(cat "$(dirname "$0")/.env" | xargs)
else
    echo "Error: .env file not found. Copy .env.example and set the configuration properly"
    exit 1
fi

# Ensure git is installed
if ! command -v git &> /dev/null; then
    echo "Git not installed. Installing..."
    sudo apt-get update && sudo apt-get install git -y
fi

# Clone the repo if it doesn't exist
if [ ! -d "${REPO_DIR}" ]; then
    git clone "${GITHUB_REPO}" "${REPO_DIR}"
fi

cd "${REPO_DIR}"

# Fetch latest changes without applying them
git fetch

# Get the latest commit hash from origin/master and the last sent commit hash
LATEST_COMMIT=$(git rev-parse origin/master)
LAST_SENT_COMMIT=$(cat "${LAST_COMMIT_FILE}" 2>/dev/null || echo "")

if ! command -v just &> /dev/null; then
    echo "just not installed. Attempting to install..."

    # Update and install just. This requires sudo permission.
    sudo apt-get update && sudo apt-get install just -y
fi

# Compare commit hashes
if [ "${LATEST_COMMIT}" != "${LAST_SENT_COMMIT}" ]; then
    # Pull the latest changes
    git pull origin master

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
