#!/bin/bash

# Usage: 'contrib/coverage-diff.sh <version1> <version2>
# Outputs a list of new lines in version2 compared to version1 that are
# not covered by the test suite. Assumes you ran
# 'make coverage-test coverage-report' from root first, so .gcov files exist.

V1=$1
V2=$2

diff-lines() {
    local path=
    local line=
    while read; do
	esc=$'\033'
	if [[ $REPLY =~ ---\ (a/)?.* ]]; then
	    continue
	elif [[ $REPLY =~ \+\+\+\ (b/)?([^[:blank:]$esc]+).* ]]; then
	    path=${BASH_REMATCH[2]}
	elif [[ $REPLY =~ @@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+)(,[0-9]+)?\ @@.* ]]; then
	    line=${BASH_REMATCH[2]}
	elif [[ $REPLY =~ ^($esc\[[0-9;]+m)*([\ +-]) ]]; then
	    echo "$path:$line:$REPLY"
	    if [[ ${BASH_REMATCH[2]} != - ]]; then
		((line++))
	    fi
	fi
    done
}

git diff --raw $V1 $V2 | grep \.c$ | awk 'NF>1{print $NF}' >files.txt

for file in $(cat files.txt)
do
	hash_file=${file//\//\#}

	git diff $V1 $V2 -- $file \
		| diff-lines \
		| grep ":+" \
		>"diff_file.txt"

	cat diff_file.txt \
		| sed -E 's/:/ /g' \
		| awk '{print $2}' \
		| sort \
		>new_lines.txt

	cat "$hash_file.gcov" \
		| grep \#\#\#\#\# \
		| sed 's/    #####: //g' \
		| sed 's/\:/ /g' \
		| awk '{print $1}' \
		| sort \
		>uncovered_lines.txt

	comm -12 uncovered_lines.txt new_lines.txt \
		| sed -e 's/$/\)/' \
		| sed -e 's/^/\t/' \
		>uncovered_new_lines.txt

	grep -q '[^[:space:]]' < uncovered_new_lines.txt && \
		echo $file && \
		git blame -c $file \
			| grep -f uncovered_new_lines.txt

	rm -f diff_file.txt new_lines.txt \
		uncovered_lines.txt uncovered_new_lines.txt
done

rm -rf files.txt
