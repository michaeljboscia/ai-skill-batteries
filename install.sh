#!/usr/bin/env bash
set -euo pipefail

# AI Skill Batteries — Installer
# Copies skill directories into ~/.claude/skills/ (flat structure required by Claude Code)
#
# Usage:
#   ./install.sh              # Install all skills
#   ./install.sh python       # Install only Python skills
#   ./install.sh aws gcp      # Install AWS + GCP skills

SKILLS_DIR="${HOME}/.claude/skills"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$SKILLS_DIR"

install_skill() {
    local src="$1"
    local name
    name=$(basename "$src")
    if [ -f "$src/SKILL.md" ]; then
        mkdir -p "$SKILLS_DIR/$name"
        cp -r "$src"/* "$SKILLS_DIR/$name/"
        echo "  Installed: $name"
    fi
}

install_category() {
    local category_dir="$1"
    local count=0
    if [ -d "$category_dir" ]; then
        for skill_dir in "$category_dir"/mx-*/; do
            [ -d "$skill_dir" ] && install_skill "$skill_dir" && ((count++)) || true
        done
        echo "  ($count skills)"
    fi
}

# If specific packages requested, install only those
if [ $# -gt 0 ]; then
    for package in "$@"; do
        echo "Installing: $package"
        # Search all category dirs for matching package
        found=false
        for category in cloud languages frameworks platforms meta; do
            if [ -d "$REPO_DIR/$category/$package" ]; then
                install_category "$REPO_DIR/$category/$package"
                found=true
            fi
        done
        # Check for skill-forge specifically
        if [ "$package" = "skill-forge" ] && [ -d "$REPO_DIR/skill-forge" ]; then
            mkdir -p "$SKILLS_DIR/skill-forge"
            cp -r "$REPO_DIR/skill-forge"/* "$SKILLS_DIR/skill-forge/"
            echo "  Installed: skill-forge (enables /skill-forge slash command)"
            found=true
        fi
        if [ "$found" = false ]; then
            echo "  Package '$package' not found. Available:"
            for category in cloud languages frameworks platforms meta; do
                ls -d "$REPO_DIR/$category"/*/ 2>/dev/null | xargs -I{} basename {} | sed 's/^/    /'
            done
            exit 1
        fi
    done
    exit 0
fi

# Install everything
echo "Installing all AI Skill Batteries..."
echo ""

echo "Cloud:"
for pkg in aws gcp gpu; do
    [ -d "$REPO_DIR/cloud/$pkg" ] && echo "  $pkg:" && install_category "$REPO_DIR/cloud/$pkg"
done

echo "Languages:"
for pkg in go python rust typescript; do
    [ -d "$REPO_DIR/languages/$pkg" ] && echo "  $pkg:" && install_category "$REPO_DIR/languages/$pkg"
done

echo "Frameworks:"
for pkg in gsap lottie nextjs react tailwind; do
    [ -d "$REPO_DIR/frameworks/$pkg" ] && echo "  $pkg:" && install_category "$REPO_DIR/frameworks/$pkg"
done

echo "Platforms:"
for pkg in hubspot supabase wordpress; do
    [ -d "$REPO_DIR/platforms/$pkg" ] && echo "  $pkg:" && install_category "$REPO_DIR/platforms/$pkg"
done

echo "Meta:"
install_category "$REPO_DIR/meta"

echo "Skill Forge:"
if [ -d "$REPO_DIR/skill-forge" ] && [ -f "$REPO_DIR/skill-forge/SKILL.md" ]; then
    mkdir -p "$SKILLS_DIR/skill-forge"
    cp -r "$REPO_DIR/skill-forge"/* "$SKILLS_DIR/skill-forge/"
    echo "  Installed: skill-forge (enables /skill-forge slash command)"
fi

echo ""
total=$(find "$REPO_DIR" -name "SKILL.md" | wc -l | tr -d ' ')
installed=$(ls -d "$SKILLS_DIR"/mx-*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
echo "Done. $total skills available, $installed installed in $SKILLS_DIR"
