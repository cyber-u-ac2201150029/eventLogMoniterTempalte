#!/usr/bin/env bash
# Render Salesforce metadata templates using Bash and standard Unix tools.
# Compatible with Git Bash on Windows and Linux-based IDE terminals.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage:
  bash scripts/bash/render-template.sh ORG_ALIAS APP_API_NAME RUN_AS_USERNAME CONTACT_PHONE [TEMPLATE_DIR] [OUTPUT_DIR]

Example:
  bash scripts/bash/render-template.sh cudev01 EventLogFileCollectorPOC \
    'target-user@example.com' '+81-3-1234-5678'

Defaults:
  TEMPLATE_DIR = templates/force-app
  OUTPUT_DIR   = build/ORG_ALIAS/APP_API_NAME/force-app

Replacements (both filenames and text content):
  @@APP_API_NAME@@     -> APP_API_NAME
  @@RUN_AS_USERNAME@@  -> RUN_AS_USERNAME
  @@CONTACT_PHONE@@    -> CONTACT_PHONE

Each app gets its own directory within the org alias, allowing multiple apps.
Output must not already exist; the input template is never modified.
HELP
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi

if (( $# < 4 || $# > 6 )); then
  usage >&2
  exit 2
fi

org_alias=$1
app=$2
run_as=$3
contact_phone=$4
source_arg=${5:-templates/force-app}
output_arg=${6:-build/$org_alias/$app/force-app}

# Validate organization alias (used only as a directory name).
if [[ ! $org_alias =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ||
      $org_alias == . || $org_alias == .. ]]; then
  echo 'ERROR: Invalid ORG_ALIAS.' >&2
  exit 2
fi

# Validate application API name.
if [[ ! $app =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
  echo 'ERROR: Invalid APP_API_NAME.' >&2
  exit 2
fi

# Validate Salesforce Run As username.
if [[ ! $run_as =~ ^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+$ ]]; then
  echo 'ERROR: RUN_AS_USERNAME must be an email-shaped username.' >&2
  exit 2
fi

# Validate contact phone.
phone_pattern="^[+0-9() .-]+$"
if [[ ! $contact_phone =~ $phone_pattern ]]; then
  echo 'ERROR: Invalid CONTACT_PHONE.' >&2
  exit 2
fi

# Check required commands.
for command in cp find grep mktemp mv sed mkdir rm dirname basename; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $command" >&2
    exit 2
  fi
done

if [[ ! -d $source_arg ]]; then
  echo "ERROR: Template directory not found: $source_arg" >&2
  exit 1
fi

source_dir=$(cd "$source_arg" && pwd -P)

output_parent=$(dirname "$output_arg")
output_name=$(basename "$output_arg")

if [[ -z $output_name ||
      $output_name == . ||
      $output_name == .. ]]; then
  echo 'ERROR: Invalid output directory.' >&2
  exit 2
fi

mkdir -p "$output_parent"
output_parent=$(cd "$output_parent" && pwd -P)
output_dir="$output_parent/$output_name"

if [[ -e $output_dir ]]; then
  echo "ERROR: Output directory already exists: $output_dir" >&2
  exit 1
fi

# Prevent overwriting or nesting within the source template.
case "$output_dir/" in
  "$source_dir/"*)
    echo 'ERROR: Output cannot be inside the template directory.' >&2
    exit 1
    ;;
esac

case "$source_dir/" in
  "$output_dir/"*)
    echo 'ERROR: Template cannot be inside the output directory.' >&2
    exit 1
    ;;
esac

# Do not follow template symlinks.
if [[ -n $(find "$source_dir" -type l -print -quit) ]]; then
  echo 'ERROR: Symlinks in templates are not supported.' >&2
  exit 1
fi

# Create temporary staging directory.
stage=$(mktemp -d "$output_parent/.render-template.XXXXXXXX")

cleanup() {
  if [[ -d $stage ]]; then
    rm -rf -- "$stage"
  fi
}

trap cleanup EXIT

# Copy template without modifying the original.
cp -R "$source_dir"/. "$stage"/

# Rename files and directories, deepest entries first.
while IFS= read -r -d '' path; do
  name=${path##*/}

  new_name=${name//@@APP_API_NAME@@/$app}
  new_name=${new_name//@@RUN_AS_USERNAME@@/$run_as}
  new_name=${new_name//@@CONTACT_PHONE@@/$contact_phone}

  if [[ $name != "$new_name" ]]; then
    mv -- "$path" "${path%/*}/$new_name"
  fi
done < <(find "$stage" -depth -mindepth 1 -print0)

# Replace placeholders in text files.
count=0

while IFS= read -r -d '' path; do
  ((count+=1))

  case "$path" in
    *.xml|*.json|*.md|*.txt|*.yaml|*.yml)
      sed -i \
        -e "s|@@APP_API_NAME@@|$app|g" \
        -e "s|@@RUN_AS_USERNAME@@|$run_as|g" \
        -e "s|@@CONTACT_PHONE@@|$contact_phone|g" \
        "$path"
      ;;
  esac
done < <(find "$stage" -type f -print0)

if (( count == 0 )); then
  echo 'ERROR: Template directory contains no files.' >&2
  exit 1
fi

# Check unresolved placeholders in filenames.
if find "$stage" -print |
   grep -Eq '@@[A-Z][A-Z0-9_]*@@'; then
  echo 'ERROR: Unresolved placeholder remains in a filename.' >&2
  exit 1
fi

# Check unresolved placeholders in file content.
if grep -R -I -n -E '@@[A-Z][A-Z0-9_]*@@' "$stage"; then
  echo 'ERROR: Unresolved placeholder remains in file content.' >&2
  exit 1
fi

# Reject active oauthLink elements.
# XML comments containing <oauthLink/> are not rejected.
if grep -R -n -E \
  '^[[:space:]]*<oauthLink([[:space:]/>])' \
  "$stage" --include='*.xml'; then
  echo 'ERROR: Active oauthLink element found.' >&2
  exit 1
fi

# Publish completed result.
mv -- "$stage" "$output_dir"
trap - EXIT

printf 'Generated %d file(s): %s\n' "$count" "$output_dir"
printf 'Organization alias: %s\n' "$org_alias"
printf 'Application API name: %s\n' "$app"

echo 'Run As username: configured (not displayed)'
echo 'Contact phone: configured (not displayed)'

# Deployment reminders.
if grep -R -I -q -E \
  '<orgScopedExternalApp>|<contactEmail>|<contactPhone>' \
  "$output_dir"; then
  echo 'WARNING: Review org-specific metadata before deployment.'
fi

echo 'NOTE: Global OAuth Settings and Run As configuration must be verified before deployment.'
