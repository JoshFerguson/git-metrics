#!/bin/bash

set -e

# OS-independent home directory
USER_HOME="$HOME"
WORKDIR="$USER_HOME/git-metrics"
SCRIPT_DIR="$WORKDIR/scripts"
LOG_FILE="$WORKDIR/git_metrics.log"
CONFIG_FILE="$SCRIPT_DIR/config.env"
LAUNCH_SCRIPT="$WORKDIR/launch_git_metrics.sh"

# Create directories
mkdir -p "$SCRIPT_DIR"

# Prompt user for config values
read -p "Enter full path to your Git repositories (default: $HOME/dev): " repo_path
repo_path="${repo_path:-$HOME/dev}"

read -p "Enter your GitHub Personal Access Token: " github_token

# Save config
cat <<EOF > "$CONFIG_FILE"
REPO_DIR="$repo_path"
GITHUB_TOKEN="$github_token"
EOF

# Docker Compose
cat <<EOF > "$WORKDIR/docker-compose.yml"
version: '3.8'
services:
  influxdb:
    image: influxdb:1.8
    container_name: influxdb
    ports:
      - "8086:8086"
    volumes:
      - influxdb_data:/var/lib/influxdb
    environment:
      - INFLUXDB_DB=gitstats

  grafana:
    image: grafana/grafana-oss
    container_name: grafana
    ports:
      - "3000:3000"
    depends_on:
      - influxdb
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin

volumes:
  influxdb_data:
  grafana_data:
EOF

# Create launch script
cat <<EOF > "$LAUNCH_SCRIPT"
#!/bin/bash
cd "$WORKDIR"
docker-compose up -d
sleep 5
"$SCRIPT_DIR/push_git_data.sh" >> "$LOG_FILE" 2>&1
echo "Done. Access Grafana at http://localhost:3000 (admin/admin)"
EOF
chmod +x "$LAUNCH_SCRIPT"

echo "Setup complete! Run: $LAUNCH_SCRIPT"

# Wait for Grafana to be ready
echo "Waiting for Grafana to start..."
sleep 10

# Import Dashboard via API
curl -s -XPOST http://localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $(echo -n admin:admin | base64)" \
  -d @"$SCRIPT_DIR/dashboard.json"
