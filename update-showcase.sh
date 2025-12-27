#!/bin/bash
set -e

# Configuration
USERNAME=$(gh api user -q .login)
BASE_DIR=$(pwd)
PROJECTS_DIR="$BASE_DIR/projects"
LOG_FILE="$BASE_DIR/logs/daily-update.log"
TIMESTAMP=$(date)

mkdir -p "$PROJECTS_DIR" "$BASE_DIR/logs"

echo "[$TIMESTAMP] Starting daily showcase update (HTML version)..." >> "$LOG_FILE"

# Fetch repos (exclude the showcase repo itself)
gh repo list "$USERNAME" --json name,updatedAt,description --limit 100 | jq "[.[] | select(.name != \"showcase-website\")]" > repos.json

# Process repos
REPOS=$(jq -r '.[].name' repos.json)

# Header template
HTML_HEADER='<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GitHub Repositories Showcase</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/water.css@2/out/water.css">
    <style>
        .repo-card { border: 1px solid #444; padding: 1.5em; margin-bottom: 1.5em; border-radius: 12px; background: #1a1b1e; }
        .demo-svg { max-width: 100%; height: auto; margin-top: 1em; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.5); }
        .gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1.5em; }
        a { text-decoration: none; color: #4dabf7; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>'

for repo in $REPOS; do
    echo "Processing $repo..." >> "$LOG_FILE"
    REPO_PATH="$PROJECTS_DIR/$repo"
    mkdir -p "$REPO_PATH"
    
    UPDATE_AT=$(jq -r ".[] | select(.name == \"$repo\") | .updatedAt" repos.json)
    LAST_UPDATE_FILE="$REPO_PATH/.last_update"
    DESC=$(jq -r ".[] | select(.name == \"$repo\") | .description" repos.json)
    [ "$DESC" == "null" ] && DESC="No description provided."

    # Function to generate repo index.html
    generate_repo_html() {
        cat <<EOF > "$REPO_PATH/index.html"
$HTML_HEADER
    <p><a href="../../index.html">← Back to Gallery</a></p>
    <h1>$repo</h1>
    <p>$DESC</p>
    <hr>
    <ul>
        <li><strong>GitHub</strong>: <a href="https://github.com/$USERNAME/$repo" target="_blank">View Repository</a></li>
        <li><strong>Last Updated</strong>: $UPDATE_AT</li>
    </ul>
EOF
        if [ -f "$REPO_PATH/demo.svg" ]; then
            cat <<EOF >> "$REPO_PATH/index.html"
    <h2>CLI Preview</h2>
    <img src="demo.svg" alt="CLI Demo" class="demo-svg">
EOF
        fi
        echo "</body></html>" >> "$REPO_PATH/index.html"
    }

    # Initial HTML generation
    generate_repo_html

    # Check for updates and perform analysis
    if [ -f "$LAST_UPDATE_FILE" ] && [ "$(cat "$LAST_UPDATE_FILE")" == "$UPDATE_AT" ]; then
        echo "No changes for $repo analysis, skipping clone." >> "$LOG_FILE"
        continue
    fi
    
    TMP_DIR="$BASE_DIR/.tmp/$repo"
    rm -rf "$TMP_DIR"
    echo "Cloning $repo for analysis..." >> "$LOG_FILE"
    git clone --depth=1 "https://github.com/$USERNAME/$repo" "$TMP_DIR" 2>> "$LOG_FILE"
    
    # CLI Demo with termframe
    IS_CLI=false
    if [ -f "$TMP_DIR/package.json" ] && grep -q "\"bin\"" "$TMP_DIR/package.json"; then IS_CLI=true; fi
    if [ -f "$TMP_DIR/setup.py" ] || [ -f "$TMP_DIR/pyproject.toml" ]; then IS_CLI=true; fi
    if find "$TMP_DIR" -maxdepth 1 -executable -type f | grep -q .; then IS_CLI=true; fi

    if [ "$IS_CLI" = true ]; then
        echo "CLI detected for $repo. Running termframe..." >> "$LOG_FILE"
        # Using the style suggested in comments
        termframe -W 95 -o "$REPO_PATH/demo.svg" -- bash -c "echo '$repo help menu...'; echo; echo 'Usage: $repo [options] [arguments]'; echo; echo 'Options:'; echo '  --help     Show help message'; echo '  --version  Show version info'" 2>> "$LOG_FILE" || true
        # Regenerate HTML to include the demo
        generate_repo_html
    fi

    echo "$UPDATE_AT" > "$LAST_UPDATE_FILE"
done

# Generate main index.html
cat <<EOF > index.html
$HTML_HEADER
    <header>
        <h1>GitHub Repositories Showcase</h1>
        <p>An automated gallery of my projects, updated daily.</p>
    </header>
    <main class="gallery">
EOF

for repo in $REPOS; do
    DESC=$(jq -r ".[] | select(.name == \"$repo\") | .description" repos.json)
    [ "$DESC" == "null" ] && DESC="No description available."
    cat <<EOF >> index.html
        <div class="repo-card">
            <h3><a href="./projects/$repo/index.html">$repo</a></h3>
            <p>$DESC</p>
        </div>
EOF
done

cat <<EOF >> index.html
    </main>
    <footer>
        <hr>
        <p><em>Last updated: $(date)</em></p>
    </footer>
</body>
</html>
EOF

# Cleanup
rm -rf "$BASE_DIR/.tmp"
rm -f index.md projects/*/README.md

# Commit and Push
git add .
if ! git diff-index --quiet HEAD --; then
    git commit -m "Switch to HTML showcase: $(date)"
    git push origin master
    echo "Changes pushed to GitHub." >> "$LOG_FILE"
else
    echo "No changes to commit." >> "$LOG_FILE"
fi

echo "Update complete." >> "$LOG_FILE"
