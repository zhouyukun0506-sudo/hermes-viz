#!/bin/zsh
set -e

# Bundle hermes-agent source (Python only) + all wheels for offline install
APP_RESOURCES="HermesViz.app/Contents/Resources"
OFFLINE_DIR="${APP_RESOURCES}/offline"
HERMES_SRC="/Users/ethan_chou/.hermes/hermes-agent"

echo "📦 Bundling offline resources..."

rm -rf "${OFFLINE_DIR}"
mkdir -p "${OFFLINE_DIR}/wheels"
mkdir -p "${OFFLINE_DIR}/hermes-agent"

# Copy only what pip needs: Python packages + config files
echo "  Copying hermes-agent Python source..."
EXCLUDES=(
    'venv' '.git' '__pycache__' '*.pyc' '*.pyo'
    'web' 'ui-tui' 'node_modules' 'website' '.github'
    'tests' 'optional-skills' 'plugins' 'skills'
    'docs' '.plans' 'docker-compose*' 'Dockerfile*'
    '.dockerignore' '.envrc' '.env.example' '.gitattributes'
    '.mailmap' 'CONTRIBUTING.md' 'CONTRIBUTORS.md'
    'AGENTS.md' 'SPRINTS.md' 'ROADMAP.md' 'TESTING.md'
    'BUGS.md' 'CHANGELOG.md' 'DESIGN.md' 'ARCHITECTURE.md'
    'HERMES.md' 'THEMES.md'
)
RSYNC_ARGS=()
for e in "${EXCLUDES[@]}"; do
    RSYNC_ARGS+=(--exclude "$e")
done
rsync -a "${RSYNC_ARGS[@]}" "${HERMES_SRC}/" "${OFFLINE_DIR}/hermes-agent/"

echo "  → hermes-agent: $(du -sh "${OFFLINE_DIR}/hermes-agent" | cut -f1)"

# Download wheels for hermes-agent and its dependencies
echo "  Downloading wheels..."
if [ -f "${HERMES_SRC}/venv/bin/pip" ]; then
    "${HERMES_SRC}/venv/bin/pip" download \
        -d "${OFFLINE_DIR}/wheels" \
        "${HERMES_SRC}" 2>&1 | tail -3
else
    pip3 download -d "${OFFLINE_DIR}/wheels" "${HERMES_SRC}" 2>&1 | tail -3
fi

echo "  → $(ls "${OFFLINE_DIR}/wheels" | wc -l | tr -d ' ') wheels ($(du -sh "${OFFLINE_DIR}/wheels" | cut -f1))"
echo "  → Total offline bundle: $(du -sh "${OFFLINE_DIR}" | cut -f1)"
echo "✅ Done."
