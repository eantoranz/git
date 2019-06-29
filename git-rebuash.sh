#!/bin/bash
# Copyright 2019 Edmundo Carmona Antoranz

# Released under the terms of GPLv2

# Rebuash will be used mainly when you want to squash and rebase
# so that you don't have to go through the ordeal of rebasing
# which would potencially bring conflicts that you would
# rather avoid it at all possible.

# rebuash takes a different strategy by merging with the target (upstream) branch
# then resetting --soft onto the target branch to finish off with a new
# revision

# Valid options:
# -u upstream branch (if it's not specified, it will be retrieved from current branch)
# -m comment for the final revision (can be multiline)
# --abort if the user wants to abort the rebuash operation
# --continue if there was a previous conflict and the user wants to continue with the current rebuash operation

UPSTREAM="" # upstream branch (will be retrieved from current branch if it is not provided)
HEAD="" # the point where we started rebuash from (revision or branch, for messaging)
HEAD_REV="" # point where we started the operation from (the revision)
STEP="" # will be used when we need to continue to know in which step we are at the moment
COMMENT="" # comment to be used on the final revision (might be empty)

# actions
START=true
CONTINUE=false
ABORT=false

. git-sh-setup

STATE_FILE="$GIT_DIR"/REBUASH_STATE

function report_bug {
    echo "You just hit a bug in git-rebuash"
    echo "BUG: $1"
    echo "Please, report this problem to the git mailing list and cc eantoranz at gmail.com"
    exit 1
}

function save_state {
    echo "UPSTREAM: $UPSTREAM" > "$STATE_FILE"
    echo "HEAD: $HEAD" >> "$STATE_FILE"
    echo "HEAD_REV: $HEAD_REV" >> "$STATE_FILE"
    echo "STEP: $STEP" >> "$STATE_FILE"
    echo "" >> "$STATE_FILE" # an empty line
    echo "$COMMENT" >> "$STATE_FILE"
}

function read_state {
    # read the content of state file and put it into the variables
    if [ ! -f "$STATE_FILE" ]
    then
        echo Unexpected Error: Rebuash state file was expected to exist.
        echo Aborting operation.
        echo Please, notify the git mail list and explain them what the situation was
        echo so that this bug can be taken care of.
        exit 1
    fi
    UPSTREAM=$( head -n 1 "$STATE_FILE" | sed 's/UPSTREAM: //' )
    HEAD=$( head -n 2 "$STATE_FILE" | tail -n 1 | sed 's/HEAD: //' )
    HEAD_REV=$( head -n 3 "$STATE_FILE" | tail -n 1 | sed 's/HEAD_REV: //' )
    STEP=$( head -n 4 "$STATE_FILE" | tail -n 1 | sed 's/STEP: //' )
    # there is an empty line
    COMMENT=$( tail -n +6 "$STATE_FILE" )
}

function remove_state {
    if [ -f "$STATE_FILE" ]
    then
        rm -f "$STATE_FILE"
    fi
}

function check_status {
    if [ $CONTINUE == true ]
    then
        if [ $ABORT == true ]
        then
            echo Can\'t use --abort and --continue at the same time
            exit 1
        fi

        # there has to be an state file
        if [ ! -f "$STATE_FILE" ]
        then
            echo There\'s no rebuash session currently going on. Can\'t continue.
            exit 1
        fi
    elif [ $ABORT == true ]
    then
        if [ ! -f "$STATE_FILE" ]
        then
            echo There\'s no rebuash session currently going on. Can\'t abort.
            exit 1
        fi
    else
        if [ $START != true ]
        then
            report_bug "START is set to false even though we were not aborting or continuing"
        fi

        if [ "$UPSTREAM" == "" ]
        then
            # as a fallback, try to get upstream from current branch
            UPSTREAM=$( git rev-parse --abbrev-ref --symbolic-full-name @{u} 2> /dev/null )
            if [ "$UPSTREAM" == "" ]
            then
                echo "Could not find out upstream branch. Please provide it with -u"
                exit 1
            else
                echo Using $UPSTREAM as the upstream branch
            fi
        fi

        # starting execution
        # there must _not_ be anything going on
        status=$( git status --short --untracked-files=no )
        if [ "$status" != "" ]
        then
            echo Status is not clean before rebuashing.
            echo Make sure to clean up your working tree before starting rebuash
            exit 1
        fi
    fi
}

# Parse arguments
function parse_options {

    while true
    do
        value=$1
        shift
        if [ $? -ne 0 ]
        then
            # no more parameters
            break
        fi

        if [ "$value" == "-u" ]
        then
            # user wants to specify the upstream branch
            UPSTREAM="$1"
            shift
        elif [ "$value" == "-m" ]
        then
            # user wants to set up the comment for the commit
            COMMENT="$1"
            shift
        elif [ "$value" == "--continue" ]
        then
            # user wants to resume execution
            CONTINUE=true
            START=false
        elif [ "$value" == "--abort" ]
        then
            ABORT=true
            START=false
        fi
    done
}

# Start execution of rebuash
function start_rebuash {

    # there must not exist a previous state file
    if [ -f "$STATE_FILE" ]
    then
        echo You are in the middle of a previous rebuash execution
        echo If that is not the case, remove the file "$STATE_FILE"
        echo and also feel free to file a report with int git mail list
        exit 1
    fi

    git show "$UPSTREAM" &> /dev/null
    if [ $? -ne 0 ]
    then
        echo "Provided upstream ($UPSTREAM) does not exist"
        exit 1
    fi

    # persist execution information
    HEAD=$( git rev-parse --abbrev-ref --symbolic-full-name @ 2> /dev/null )
    HEAD_REV=$( git show --quiet --pretty="%H" )
    save_state

    # start doing our magic
    echo "Merging with upstream branch ($UPSTREAM)"
    git merge --no-ff --no-commit "$UPSTREAM" 2> /dev/null

    # we let the process move forward as if we are continuing
    STEP=MERGE
    save_state # continue_rebuash will read the state from file
    CONTINUE=true
    return

}

function continue_rebuash {
    read_state
    if [ "$STEP" == "" ]
    then
        report_bug "Bug: Can't determine in what step we are in order to do --continue."
    fi

    if [ "$STEP" == "MERGE" ]
    then
        git -c core.editor=/bin/true merge --continue &> /dev/null # do not open editor, use previous comment

        if [ $? -ne 0 ]
        then
            save_state # just in case we add more _previous_ STEPS later on
            echo "There are unmerged paths to take care of (or tracked and pending to be added to index)"
            echo Check with git status
            echo "Finish them (_DO NOT_ commit nor run git merge --continue). Then run:"
            echo
            echo git rebuash --continue
            echo
            echo You can also run git rebuash --abort if you would like to stop the whole process
            echo and go back to where you were before rebuashing
            exit 1
        fi
        STEP=RESET
    fi

    if [ "$STEP" == "RESET" ]
    then
        # move branch pointer to UPSTREAM
        git reset --soft "$UPSTREAM"

        # merge/reset went fine so we set the STEP to COMMIT
        STEP=COMMIT
    fi

    if [ "$STEP" == "COMMIT" ]
    then
        # create new revision
        if [ "$COMMENT" == "" ]
        then
            # no comment was provided
            # what was checked out when we started?
            if [ "$HEAD" == "HEAD" ]
            then
                # was working on detached head
                TEMP_COMMENT="Rebuashing $HEAD_REV on top of $UPSTREAM"
            else
                TEMP_COMMENT="Rebuashing $HEAD on top of $UPSTREAM"
            fi
            git commit -m "$TEMP_COMMENT" --edit
        else
            git commit -m "$COMMENT"
        fi

        if [ $? -ne 0 ]
        then
            # there was some error while committing
            save_state

            echo There was an error while committing.
            echo Aborting rebuash operation.
            echo When you are ready to finish, run:
            echo git rebuash --continue
            exit 1
        fi
        STEP=END # just in case
    fi

    # everything went fine
    remove_state
    echo Rebuash operation was successful.
    exit 0
}

function abort_rebuash {
    # take it back to the original state
    # make sure there was an state to start from
    read_state

    # most cases, we are in the middle of the merge operation
    if [ "$STEP" == "" ]
    then
        echo Bug: Could not figure out the step we are in.
        echo Please, report this problem to the git mail list
        exit 1
    fi
    if [ "$STEP" == "MERGE" ]
    then
        # can ask to abort merge and we go back to where we were when we started
        git merge --abort &> /dev/null
    elif [ "$STEP" == "COMMIT" ]
    then
        # need to got back to where we were before
        git reset --hard "$HEAD_REV" &> /dev/null
    else
        report_bug "Unknown step ($STEP)"
    fi

    remove_state

    echo Rebuash was successfully aborted
    exit 0
}

parse_options "$@"

check_status

if [ $START == true ]
then
    start_rebuash
fi

if [ $CONTINUE == true ]
then
    continue_rebuash
fi

if [ $ABORT == true ]
then
    abort_rebuash
fi
