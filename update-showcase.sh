#!/bin/bash
set -e

# Configuration
USERNAME=$(gh api user -q .login)
BASE_DIR=$(pwd)
PROJECTS_DIR="$BASE_DIR/projects"
LOG_FILE="$BASE_DIR/logs/daily-update.log"
TIMESTAMP=$(date)

mkdir -p "$PROJECTS_DIR" "$BASE_DIR/logs"

echo "[$TIMESTAMP] Starting daily showcase update..." >> "$LOG_FILE"

# Fetch repos (exclude the showcase repo itself)
gh repo list "$USERNAME" --json name,updatedAt,description --limit 100 | jq "[.[] | select(.name != \"showcase-website\")]" > repos.json

# Process repos
REPOS=$(jq -r '.[].name' repos.json)

for repo in $REPOS; do
    echo "Processing $repo..." >> "$LOG_FILE"
    REPO_PATH="$PROJECTS_DIR/$repo"
    mkdir -p "$REPO_PATH"
    
    # Simple check for updates (compare updatedAt)
    UPDATE_AT=$(jq -r ".[] | select(.name == \"$repo\") | .updatedAt" repos.json)
    LAST_UPDATE_FILE="$REPO_PATH/.last_update"
    
    if [ -f "$LAST_UPDATE_FILE" ] && [ "$(cat "$LAST_UPDATE_FILE")" == "$UPDATE_AT" ]; then
        echo "No changes for $repo, skipping." >> "$LOG_FILE"
        continue
    fi
    
    # Clone temporarily for analysis
    TMP_DIR="$BASE_DIR/.tmp/$repo"
    rm -rf "$TMP_DIR"
    git clone --depth=1 "https://github.com/$USERNAME/$repo" "$TMP_DIR" 2>> "$LOG_FILE"
    
    # Analysis
    DESC=$(jq -r ".[] | select(.name == \"$repo\") | .description" repos.json)
    [ "$DESC" == "null" ] && DESC="No description provided."
    
    echo "Analyzing $repo..." >> "$LOG_FILE"
    
    # Generate project index.md
    cat <<EOF > "$REPO_PATH/README.md"
# $repo

$DESC

## Project Details
- **GitHub**: [Link](https://github.com/$USERNAME/$repo)
- **Last Updated**: $UPDATE_AT

EOF

    # CLI Demo with termframe (if it looks like a CLI)
    # Heuristic: has a shebang in a file, or package.json with bin, or setup.py
    IS_CLI=false
    if [ -f "$TMP_DIR/package.json" ] && grep -q "\"bin\"" "$TMP_DIR/package.json"; then IS_CLI=true; fi
    if [ -f "$TMP_DIR/setup.py" ] || [ -f "$TMP_DIR/pyproject.toml" ]; then IS_CLI=true; fi
    if find "$TMP_DIR" -maxdepth 1 -executable -type f | grep -q .; then IS_CLI=true; fi

    if [ "$IS_CLI" = true ]; then
        echo "Potential CLI detected for $repo. Attempting termframe..." >> "$LOG_FILE"
        # Try to run --help safely
        # Note: This is a placeholder for actual execution logic
        # For security, we should be careful about running arbitrary code
        # Here we just simulate or check for a specific help file
        if [ -f "$TMP_DIR/README.md" ] && grep -q "Usage" "$TMP_DIR/README.md"; then
             echo "## CLI Usage demo" >> "$REPO_PATH/README.md"
             echo "![Demo](demo.svg)" >> "$REPO_PATH/README.md"
             # termframe -c "echo 'Demo output for $repo'" -o "$REPO_PATH/demo.svg"
             # Since we can't safely execute everything, we'll just generate a placeholder for now
             termframe -c "echo '$repo help menu...'; echo '--help'; echo 'Usage: $repo [options]'" -o "$REPO_PATH/demo.svg" 2>> "$LOG_FILE" || true
        fi
    fi

    echo "$UPDATE_AT" > "$LAST_UPDATE_FILE"
done

# Generate main index.md
echo -e "# GitHub Repositories Showcase\n\nList of projects:\n" > index.md
for repo in $REPOS; do
    DESC=$(jq -r ".[] | select(.name == \"$repo\") | .description" repos.json)
    [ "$DESC" == "null" ] && DESC="No description."
    echo "* **[$repo](./projects/$repo/README.md)**: $DESC" >> index.md
done
echo -e "\n*Last updated: $(date)*" >> index.md

# Cleanup
rm -rf "$BASE_DIR/.tmp"

# Commit and Push
git add .
if ! git diff-index --quiet HEAD --; then
    git commit -m "Automated update: $(date)"
    git push origin master
    echo "Changes pushed to GitHub." >> "$LOG_FILE"
else
    echo "No changes to commit." >> "$LOG_FILE"
fi

echo "Update complete." >> "$LOG_FILE"
