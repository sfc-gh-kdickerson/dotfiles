#!/usr/bin/env bash
# Create (or relink) a snowbox project: sf worktrees, per-stack symlinks, gitignore.
set -euo pipefail

SNOWBOX="${SNOWBOX:-/home/repo/snowbox-kdickerson}"
PROJECTS="${PROJECTS:-$SNOWBOX/projects}"
REPO_ROOT="${REPO_ROOT:-/home/repo}"
SF="${SF:-/usr/local/bin/sf}"

usage() {
  cat <<'EOF'
Usage: setup-project.sh [--wt-name NAME] <project-slug> <spec> [spec ...]

Each spec is:
  repo[:branch]           symlink named <repo>, share one worktree with other
                          unaliased repos
  link=repo[:branch]      symlink named <link>, own worktree <wt>-<link>
                          (required for a second checkout of the same repo)

Repos are directories under /home/repo. :branch is passed through to
`sf worktree create -r`.

Examples:
  setup-project.sh disk-space snowflake snowml
  setup-project.sh lora snowflake \
    snowml-client=snowml:kaleb/lora-client/main \
    snowml-container=snowml:kaleb/lora-container/main
EOF
}

wt_name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wt-name)
      wt_name="${2:?--wt-name requires a value}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "unknown flag: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 2
fi

slug="$1"
shift

if [[ ! "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "project slug must be kebab-case (got: $slug)" >&2
  exit 2
fi

[[ -n "$wt_name" ]] || wt_name="$slug"
if [[ ! "$wt_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
  echo "worktree name must be a simple identifier (got: $wt_name)" >&2
  exit 2
fi

if [[ ! -x "$SF" ]]; then
  echo "sf CLI not found at $SF" >&2
  exit 1
fi

if [[ ! -d "$REPO_ROOT" ]]; then
  echo "repo root missing: $REPO_ROOT" >&2
  exit 1
fi

link_names=()
repo_dirs=()
create_rs=()
wt_for_link=()
declare -A seen_links=()
unaliased_rs=()

for spec in "$@"; do
  link=""
  rest="$spec"
  if [[ "$spec" == *=* ]]; then
    link="${spec%%=*}"
    rest="${spec#*=}"
  fi
  if [[ -z "$rest" ]]; then
    echo "invalid spec: $spec" >&2
    exit 2
  fi
  left="${rest%%:*}"
  repo_dir="${left##*/}"
  [[ -n "$link" ]] || link="$repo_dir"
  if [[ -z "$repo_dir" || -z "$link" ]]; then
    echo "invalid spec: $spec" >&2
    exit 2
  fi
  if [[ ! "$link" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    echo "symlink name must be a simple identifier (got: $link)" >&2
    exit 2
  fi
  if [[ -n "${seen_links[$link]:-}" ]]; then
    echo "duplicate symlink $link (from $spec). Alias extra checkouts: link=repo[:branch]" >&2
    exit 2
  fi
  seen_links[$link]=1
  src="$REPO_ROOT/$repo_dir"
  if [[ ! -d "$src/.git" && ! -f "$src/.git" ]]; then
    echo "no clone at $src — clone into $REPO_ROOT first" >&2
    exit 1
  fi
  if [[ "$link" == "$repo_dir" ]]; then
    this_wt="$wt_name"
    unaliased_rs+=("$rest")
  else
    this_wt="${wt_name}-${link}"
  fi
  link_names+=("$link")
  repo_dirs+=("$repo_dir")
  create_rs+=("$rest")
  wt_for_link+=("$this_wt")
done

wt_exists() {
  local name="$1"
  if [[ -n "${existing_json:-}" ]] && command -v jq >/dev/null 2>&1; then
    jq -e --arg n "$name" '.[] | select(.Name == $n)' <<<"$existing_json" >/dev/null 2>&1
    return $?
  fi
  [[ -d "/src/$name/.worktree" ]]
}

ensure_worktree() {
  local name="$1"
  shift
  if wt_exists "$name"; then
    echo "reusing existing worktree: $name"
    return 0
  fi
  local -a args=("$name")
  local r
  for r in "$@"; do
    args+=(-r "$r")
  done
  echo "creating worktree: $SF worktree create ${args[*]}"
  "$SF" worktree create "${args[@]}"
}

project_dir="$PROJECTS/$slug"
mkdir -p "$project_dir"

existing_json="$("$SF" worktree list --json 2>/dev/null || true)"

if ((${#unaliased_rs[@]})); then
  ensure_worktree "$wt_name" "${unaliased_rs[@]}"
fi

declare -A sidecar_created=()
i=0
for link in "${link_names[@]}"; do
  name="${wt_for_link[$i]}"
  if [[ "$name" != "$wt_name" && -z "${sidecar_created[$name]:-}" ]]; then
    ensure_worktree "$name" "${create_rs[$i]}"
    sidecar_created[$name]=1
  fi
  i=$((i + 1))
done

gitignore="$project_dir/.gitignore"
touch "$gitignore"
ensure_ignore() {
  local line="$1"
  grep -qxF "$line" "$gitignore" 2>/dev/null || printf '%s\n' "$line" >>"$gitignore"
}

echo "project: $project_dir"
echo "links:"
i=0
for link in "${link_names[@]}"; do
  name="${wt_for_link[$i]}"
  repo_dir="${repo_dirs[$i]}"
  target="$("$SF" worktree path "$name" "$repo_dir")"
  if [[ ! -d "$target" ]]; then
    echo "worktree path missing for $link: $target" >&2
    exit 1
  fi
  ln -sfn "$target" "$project_dir/$link"
  ensure_ignore "$link"
  echo "  $link -> $target  ($name)"
  i=$((i + 1))
done
ensure_ignore ".cursor/"

agents="$project_dir/AGENTS.md"
if [[ ! -f "$agents" ]]; then
  {
    echo "# ${slug}"
    echo
    echo "Working directory for TODO."
    echo
    echo "Edit through the symlinks, not \`/home/repo/<repo>\`."
    echo
    echo "## Stacks"
    echo
    echo "| Stack | Symlink | Backing |"
    echo "| ----- | ------- | ------- |"
    i=0
    for link in "${link_names[@]}"; do
      name="${wt_for_link[$i]}"
      repo_dir="${repo_dirs[$i]}"
      target="$("$SF" worktree path "$name" "$repo_dir")"
      echo "| ${link} | [\`${link}\`](${link}) | \`${target}\` (\`sf wt create ${name}\`) |"
      i=$((i + 1))
    done
    echo
    echo "## Keep this file high-level"
    echo
    echo "Durable investigation notes stay out of this file."
  } >"$agents"
  echo "wrote $agents (fill in purpose/scope)"
else
  echo "left existing $agents"
fi
