#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_dir="$(mktemp -d)"
trap 'rm -rf "$task_dir"' EXIT

export HOME="${task_dir}/home"
export GIT_CONFIG_GLOBAL="${task_dir}/gitconfig"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=0
export GIT_AUTHOR_NAME=Test GIT_COMMITTER_NAME=Test
export GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_EMAIL=test@example.com
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES
mkdir -p "$HOME"
git config --global pull.rebase true
git config --global branch.master.rebase true
git config --global commit.gpgsign false

git init -q --bare -b master "${task_dir}/origin.git"
git init -q --bare -b master "${task_dir}/work.git"
git init -q -b master "${task_dir}/checkout"
git -C "${task_dir}/checkout" commit --allow-empty -qm base
git -C "${task_dir}/checkout" remote add origin "${task_dir}/origin.git"
git -C "${task_dir}/checkout" remote add work "${task_dir}/work.git"
git -C "${task_dir}/checkout" push -q origin master
git -C "${task_dir}/checkout" push -q work master
git clone -q "${task_dir}/work.git" "${task_dir}/other"

(
    # shellcheck source=../install.sh
    source "${repo_dir}/install.sh"
    export DOTFILES_DIR="${task_dir}/checkout"
    setup_repo_git
    setup_repo_git
)

[ "$(git -C "${task_dir}/checkout" config pull.rebase)" = false ]
[ "$(git -C "${task_dir}/checkout" config branch.master.rebase)" = false ]
[ "$(git -C "${task_dir}/other" config pull.rebase)" = true ]
[ "$(git config --global branch.master.rebase)" = true ]
[ "$(git -C "${task_dir}/checkout" remote get-url origin)" = "${task_dir}/origin.git" ]
[ "$(git -C "${task_dir}/checkout" remote get-url work)" = "${task_dir}/work.git" ]

printf 'local\n' >"${task_dir}/checkout/local.txt"
git -C "${task_dir}/checkout" add local.txt
git -C "${task_dir}/checkout" commit -qm local
local_head="$(git -C "${task_dir}/checkout" rev-parse HEAD)"
printf 'work\n' >"${task_dir}/other/work.txt"
git -C "${task_dir}/other" add work.txt
git -C "${task_dir}/other" commit -qm work
work_head="$(git -C "${task_dir}/other" rev-parse HEAD)"
git -C "${task_dir}/other" push -q origin master
git -C "${task_dir}/checkout" pull -q --no-edit work master
git -C "${task_dir}/checkout" merge-base --is-ancestor "$local_head" HEAD
git -C "${task_dir}/checkout" merge-base --is-ancestor "$work_head" HEAD
git -C "${task_dir}/checkout" push -q origin HEAD:master
git -C "${task_dir}/checkout" push -q work HEAD:master
expected="$(git -C "${task_dir}/checkout" rev-parse HEAD)"
[ "$(git --git-dir="${task_dir}/origin.git" rev-parse master)" = "$expected" ]
[ "$(git --git-dir="${task_dir}/work.git" rev-parse master)" = "$expected" ]
echo '[INFO] Git sync smoke test passed'
