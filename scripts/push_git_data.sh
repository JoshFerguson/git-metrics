#!/bin/bash

# Load config
CONFIG_FILE="$HOME/git-metrics/scripts/config.env"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config.env not found. Run setup_git_metrics.sh to create it."
  exit 1
fi
source "$CONFIG_FILE"

INFLUX_URL="http://localhost:8086/write?db=gitstats"
LOG_FILE="$HOME/git-metrics/git_metrics.log"
ONE_YEAR_AGO=$(date -u -d "1 year ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -v-1y +"%Y-%m-%dT%H:%M:%SZ")

# Check dependencies
command -v git >/dev/null || { echo "git is required"; exit 1; }
command -v curl >/dev/null || { echo "curl is required"; exit 1; }
command -v jq >/dev/null || { echo "jq is required"; exit 1; }

# Process each repo
find "$REPO_DIR" -type d -name ".git" | while read -r git_dir; do
  repo_dir="$(dirname "$git_dir")"
  repo_name="$(basename "$repo_dir")"
  echo "Processing $repo_name..." >> "$LOG_FILE"
  cd "$repo_dir" || continue

  # Commit stats
  git log --since="$ONE_YEAR_AGO" --pretty=format:'%H|%an|%ad' --numstat --date=iso | awk -v repo="$repo_name" '
  BEGIN { OFS="|" }
  /^[0-9]/ {
    added = $1 == "-" ? 0 : $1
    removed = $2 == "-" ? 0 : $2
    print commit, author, date, added, removed, repo
  }
  /^[0-9a-f]{40}/ {
    split($0, meta, "|")
    commit = meta[1]; author = meta[2]; date = meta[3]
  }' > /tmp/gitstats.txt

  while IFS='|' read -r commit author date added removed repo; do
    ts=$(date -d "$date" +"%s" 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$date" +"%s")
    curl -s -XPOST "$INFLUX_URL" \
      --data-binary "code_changes,repo=$repo,author=\"$author\" added=$added,removed=$removed,count=1 $((ts))000000000"
  done < /tmp/gitstats.txt

  # Merge stats
  git log --merges --pretty=format:'%H|%an|%ad' --date=iso | while IFS='|' read -r commit author date; do
    ts=$(date -d "$date" +"%s" 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$date" +"%s")
    curl -s -XPOST "$INFLUX_URL" \
      --data-binary "merged_commits,repo=$repo_name,author=\"$author\" count=1 $((ts))000000000"
  done

  # GitHub Issues
  remote_url=$(git remote get-url origin 2>/dev/null)
  if [[ $remote_url =~ github.com[:/](.+)/(.+)\.git ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    issues_url="https://api.github.com/repos/$owner/$repo/issues?state=all&since=$ONE_YEAR_AGO"

    curl -s -H "Authorization: token $GITHUB_TOKEN" "$issues_url" | \
      jq -r '.[] | "\(.created_at)|\(.user.login)|opened", "\(.closed_at)|\(.user.login)|closed"' | \
      grep -v '^null' > /tmp/issue_events.txt

    while IFS='|' read -r date author state; do
      ts=$(date -d "$date" +"%s" 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$date" +"%s")
      curl -s -XPOST "$INFLUX_URL" \
        --data-binary "issues,repo=$repo_name,author=\"$author\",state=\"$state\" count=1 $((ts))000000000"
    done < /tmp/issue_events.txt
  fi
done
