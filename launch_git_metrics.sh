#!/bin/bash
cd "$HOME/git-metrics"
docker-compose up -d
sleep 5
"$HOME/git-metrics/scripts/push_git_data.sh" >> "$HOME/git-metrics/git_metrics.log" 2>&1
echo "Done. Access Grafana at http://localhost:3000 (admin/admin)"
