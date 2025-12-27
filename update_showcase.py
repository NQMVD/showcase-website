
import json
import os
import subprocess
from datetime import datetime

def run_command(command, cwd=None):
    try:
        result = subprocess.run(command, shell=True, check=True, capture_output=True, text=True, cwd=cwd)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error running command {command}: {e.stderr}")
        return None

def analyze_repo(repo_path):
    files = os.listdir(repo_path)
    analysis = {
        "tech_stack": [],
        "is_cli": False,
        "entry_point": None,
        "description": "",
        "usage": ""
    }
    
    # Check for README
    readme_path = None
    for f in files:
        if f.lower() == "readme.md":
            readme_path = os.path.join(repo_path, f)
            break
    
    if readme_path:
        with open(readme_path, "r") as f:
            content = f.read()
            # Basic extraction - in a real scenario we'd use a model or more complex logic
            analysis["description"] = content[:500] + "..." if len(content) > 500 else content

    # Detect tech stack
    if "package.json" in files:
        analysis["tech_stack"].append("Node.js")
    if "Cargo.toml" in files:
        analysis["tech_stack"].append("Rust")
        analysis["is_cli"] = True # Often Rust projects are CLIs
    if "requirements.txt" in files or "setup.py" in files or "pyproject.toml" in files:
        analysis["tech_stack"].append("Python")
    if "main.lua" in files:
        analysis["tech_stack"].append("Lua (LÖVE)")
    if "go.mod" in files:
        analysis["tech_stack"].append("Go")

    return analysis

def generate_html(repo_name, analysis, repo_url, has_svg=False):
    tech_stack_html = "".join([f"<li>{tech}</li>" for tech in analysis["tech_stack"]])
    svg_html = f'<img src="demo.svg" alt="{repo_name} Demo" style="max-width: 100%; height: auto; border: 1px solid #ddd; border-radius: 4px;">' if has_svg else ""
    
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{repo_name} Showcase</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; padding: 2rem; }}
        h1 {{ border-bottom: 2px solid #eee; padding-bottom: 0.5rem; }}
        h2 {{ margin-top: 2rem; border-bottom: 1px solid #eee; padding-bottom: 0.2rem; }}
        code, pre {{ background: #f4f4f4; padding: 0.2rem 0.4rem; border-radius: 3px; }}
        pre {{ padding: 1rem; overflow-x: auto; }}
        .github-link {{ display: inline-block; margin-top: 2rem; padding: 0.5rem 1rem; background: #24292e; color: white; text-decoration: none; border-radius: 5px; }}
        .github-link:hover {{ background: #444; }}
    </style>
</head>
<body>
    <h1>{repo_name} Showcase</h1>
    <p>{analysis["description"]}</p>
    
    <h2>Tech Stack</h2>
    <ul>{tech_stack_html}</ul>
    
    {f"<h2>Demo</h2>{svg_html}" if has_svg else ""}
    
    <a href="{repo_url}" class="github-link">View on GitHub</a>
    <br><br>
    <a href="../../index.html">← Back to Projects</a>
</body>
</html>"""
    return html

def main():
    with open("repos.json", "r") as f:
        repos = json.load(f)
    
    processed_repos = []
    
    for repo in repos:
        if repo["isFork"]:
            continue
        
        name = repo["name"]
        if name in ["projects-showcase", "NQMVD.github.io", "showcase-website"]:
            continue
            
        project_dir = f"projects/{name}"
        metadata_path = f"{project_dir}/.metadata"
        
        if os.path.exists(metadata_path):
            with open(metadata_path, "r") as f:
                old_metadata = json.load(f)
                if old_metadata.get("last_pushed") == repo["pushedAt"]:
                    print(f"Skipping {name}, no updates.")
                    processed_repos.append({
                        "name": name,
                        "description": repo["description"] or old_metadata.get("description", "")[:100] + "..."
                    })
                    continue

        print(f"Processing {name}...")
        temp_dir = f"/tmp/{name}"
        run_command(f"rm -rf {temp_dir} && git clone --depth=1 https://github.com/NQMVD/{name}.git {temp_dir}")
        
        if not os.path.exists(temp_dir):
            continue
            
        analysis = analyze_repo(temp_dir)
        if not analysis["description"]:
            analysis["description"] = repo["description"] or "No description provided."
            
        project_dir = f"projects/{name}"
        os.makedirs(project_dir, exist_ok=True)
        
        has_svg = False
        if analysis["is_cli"]:
            # Try to capture SVG with termframe
            # We assume it's a Rust project if it has Cargo.toml
            if "Rust" in analysis["tech_stack"]:
                # Just an example, termframe needs a command that works
                # We won't actually build it here to save time/resources unless it's easy
                pass
        
        html_content = generate_html(name, analysis, f"https://github.com/NQMVD/{name}", has_svg)
        with open(f"{project_dir}/index.html", "w") as f:
            f.write(html_content)
        
        # Save metadata
        metadata = {
            "last_pushed": repo["pushedAt"],
            "description": repo["description"]
        }
        with open(f"{project_dir}/.metadata", "w") as f:
            json.dump(metadata, f)
            
        processed_repos.append({
            "name": name,
            "description": repo["description"] or analysis["description"][:100].replace("\\n", " ") + "..."
        })
        
        run_command(f"rm -rf {temp_dir}")

    # Generate main index.html
    processed_repos.sort(key=lambda x: x["name"].lower())
    repo_list_html = "".join([f'<li><a href="projects/{r["name"]}/">{r["name"]}</a> - {r["description"]}</li>' for r in processed_repos])
    
    main_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Project Showcase</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; padding: 2rem; }}
        h1 {{ border-bottom: 2px solid #eee; padding-bottom: 0.5rem; }}
        ul {{ list-style: none; padding: 0; }}
        li {{ margin-bottom: 1rem; padding: 1rem; border: 1px solid #eee; border-radius: 8px; }}
        li a {{ font-weight: bold; text-decoration: none; color: #0366d6; }}
        li a:hover {{ text-decoration: underline; }}
    </style>
</head>
<body>
    <h1>Project Showcase</h1>
    <ul>{repo_list_html}</ul>
    <p>Last updated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>
</body>
</html>"""
    
    with open("index.html", "w") as f:
        f.write(main_html)

if __name__ == "__main__":
    main()
