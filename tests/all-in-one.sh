#!/bin/bash

cd "$(mktemp -d ${TMPDIR:-/tmp}/dl-XXXXXXX)"

# recipe from https://stackoverflow.com/a/4024263/1265472
# sort -V seems to work on OSX yoh has access to.
verlte() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

verlt() {
    [ "$1" = "$2" ] && return 1 || verlte $1 $2
}


set -eux

# provide versioning information to possibly ease troubleshooting
git annex version
rclone --version

export HOME=$PWD
echo -e '[local]\ntype = local\nnounc =' > ~/.rclone.conf
# to pacify git/git-annex
git config --global user.name Me
git config --global user.email me@example.com
git config --global init.defaultBranch master

git_annex_version=$(git annex version | awk '/git-annex version:/{print $3;}')

# Prepare rclone remote local store
mkdir rclone-local
export RCLONE_PREFIX=$PWD/rclone-local

git-annex version
mkdir testrepo
cd testrepo
git init .
git-annex init
git-annex initremote GA-rclone-CI type=external externaltype=rclone target=local prefix=$RCLONE_PREFIX chunk=100MiB encryption=${GARR_TEST_ENCRYPTION:-shared} mac=HMACSHA512

# Rudimentary test, spaces in the filename must be ok, 0 length files should be ok
if verlte "10.20220525+git73" "$git_annex_version"; then
	# Was fixed in 10.20220525-73-g13fc6a9b6
	echo "I: Fixed git-annex $git_annex_version, adding empty file"
	touch "test 0"
fi

echo 1 > "test 1"
git-annex add *
git-annex copy * --to GA-rclone-CI
git-annex drop *
git-annex get *

# Do a cycle with --debug to ensure that we are passing desired DEBUG output
git-annex --debug drop test\ 1 2>&1 | grep -q 'grep.*exited with rc='
git-annex --debug get test\ 1 2>/dev/null

# test copy/drop/get cycle with parallel execution and good number of files and spaces in the names, and duplicated content/keys
set +x
for f in `seq 1 20`; do echo "load $f" | tee "test-$f.dat" >| "test $f.dat"; done
set -x
git annex add -J5 --quiet .
git-annex copy -J5 --quiet . --to GA-rclone-CI
git-annex drop -J5 --quiet .
git-annex get -J5 --quiet .
git-annex drop --from GA-rclone-CI -J5 --quiet .

# annex testremote --fast
git-annex testremote GA-rclone-CI --fast
