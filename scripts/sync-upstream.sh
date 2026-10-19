#!/bin/bash
# Keeps the Intel port in step with Homebrew's installer sources.
#   sync-upstream.sh merge              three-way merge upstream changes into the Intel files
#   sync-upstream.sh report TITLE FILE  open an issue with FILE as its body, or comment on the open one
# upstream/ holds the pristine upstream files the Intel files are currently based on.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# install.sh comes from Homebrew/install; the rest from Homebrew/brew release tags.
forked=(install.sh package/Distribution.xml package/scripts/postinstall
  package/resources/WELCOME.rtf package/resources/CONCLUSION.rtf)

output() {
  echo "$1"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]
  then
    echo "$1" >>"${GITHUB_OUTPUT}"
  fi
}

merge() {
  local install_sha brew_tag old_install_sha old_brew_tag new file
  local changed=0 conflicts=0 workflow_changed=0
  old_install_sha="$(sed -n 's/^install_sha=//p' upstream/SOURCES)"
  old_brew_tag="$(sed -n 's/^brew_tag=//p' upstream/SOURCES)"
  install_sha="${INSTALL_SHA:-$(gh api repos/Homebrew/install/commits/HEAD --jq .sha)}"
  brew_tag="${BREW_TAG:-$(gh release view --repo Homebrew/brew --json tagName --jq .tagName)}"

  new="$(mktemp -d)"
  # shellcheck disable=SC2064 # expand now: `new` is local
  trap "rm -rf '${new}'" EXIT
  curl -fsSL --create-dirs -o "${new}/install.sh" \
    "https://raw.githubusercontent.com/Homebrew/install/${install_sha}/install.sh"
  for file in "${forked[@]:1}" .github/workflows/release.yml
  do
    curl -fsSL --create-dirs -o "${new}/${file}" \
      "https://raw.githubusercontent.com/Homebrew/brew/${brew_tag}/${file}"
  done

  for file in "${forked[@]}"
  do
    cmp -s "upstream/${file}" "${new}/${file}" && continue
    changed=1
    if git merge-file -L "${file} (Intel)" -L "${file} (upstream before)" -L "${file} (upstream after)" \
      "${file}" "upstream/${file}" "${new}/${file}"
    then
      echo "Merged upstream changes into ${file}"
    else
      echo "Upstream changes to ${file} conflict with the Intel port"
      conflicts=1
    fi
    cp "${new}/${file}" "upstream/${file}"
  done

  # The build workflow can't be merged automatically (GITHUB_TOKEN may not push workflow
  # files), so flag changes to it, ignoring the frequent action pin bumps.
  if ! cmp -s upstream/release.yml "${new}/.github/workflows/release.yml"
  then
    changed=1
    if ! diff -q <(grep -v 'uses: ' upstream/release.yml) \
      <(grep -v 'uses: ' "${new}/.github/workflows/release.yml") >/dev/null
    then
      workflow_changed=1
      diff -u upstream/release.yml "${new}/.github/workflows/release.yml" >"${RUNNER_TEMP:-/tmp}/release.yml.diff" || true
    fi
    cp "${new}/.github/workflows/release.yml" upstream/release.yml
  fi

  # A new release alone still counts: it gets tested on Intel before it is published.
  if [[ "${old_install_sha}" != "${install_sha}" || "${old_brew_tag}" != "${brew_tag}" ]]
  then
    changed=1
    printf '%s\n' "# Upstream revisions the Intel files are merged with; written by scripts/sync-upstream.sh." \
      "install_sha=${install_sha}" "brew_tag=${brew_tag}" >upstream/SOURCES
  fi

  output "changed=${changed}"
  output "conflicts=${conflicts}"
  output "workflow_changed=${workflow_changed}"
  output "brew_tag=${brew_tag}"
  output "summary=Homebrew/install ${old_install_sha:0:10}..${install_sha:0:10}, Homebrew/brew ${old_brew_tag}..${brew_tag}"
}

report() {
  local title="$1" body_file="$2" number
  number="$(gh issue list --state open --search "\"${title}\" in:title" --json number --jq '.[0].number // empty')"
  if [[ -n "${number}" ]]
  then
    # Don't repeat an unresolved report every 6 hours.
    if ! gh issue view "${number}" --json body,comments --jq '.body, .comments[].body' |
       grep -qF -- "$(head -n1 "${body_file}")"
    then
      gh issue comment "${number}" --body-file "${body_file}"
    fi
  else
    gh issue create --title "${title}" --body-file "${body_file}"
  fi
}

case "${1:-}" in
  merge) merge ;;
  report) report "$2" "$3" ;;
  *)
    echo "Usage: $0 merge | report TITLE BODY_FILE" >&2
    exit 1
    ;;
esac
