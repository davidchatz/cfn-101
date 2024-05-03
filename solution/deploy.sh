#!/bin/bash

tmp=/tmp/$$
status=1

_cleanup()
{
    rm -f $tmp.*
    exit $status
}

trap _cleanup 0 1 2 3

LIST=$(ls -1 *.yaml)
COUNT=$(ls -1 *.yaml | wc -l)

FIRST=$(ls -1 *.yaml | head -1)
ALLBUTFIRST=$(ls -1 *.yaml | tail -n +2)

STACK=cfn-demo
REGION=ap-southeast-1


COLOR_RUN=$(tput setaf 12)
COLOR_HEAD=$(tput setaf 10)
COLOR_ERR=$(tput setaf 1)
COLOR_NOTE=$(tput setaf 5)
COLOR_WARN=$(tput setaf 3)
COLOR_OFF=$(tput sgr0)

# Run a command, display but ignore errors
function _run()
{
    echo $COLOR_RUN$@$COLOR_OFF
    "$@"
    return $?
}

# Run a command and exit on error
function _walk()
{
    echo $COLOR_RUN$@$COLOR_OFF
    "$@"
    r=$?
    if [[ $r -ne 0 ]]
    then
        _error "Stopping on error ($r)"
        exit 1
    fi
    return $r
}

function _note()
{
    echo
    echo "$COLOR_NOTE$@$COLOR_OFF"
}

function _warn()
{
    echo
    echo "$COLOR_WARN$@$COLOR_OFF"
}

function _header()
{
    echo
    echo
    echo "$COLOR_HEAD=== "$@" ===$COLOR_OFF"
    echo
}

function _error()
{
    echo
    echo "$COLOR_ERR"$@"$COLOR_OFF"
    echo
    exit 1
}

# https://github.com/alestic/aws-cloudformation-stack-status/blob/master/aws-cloudformation-stack-status
red_font='\e[0;31m'
red_background='\e[41m'
green_font='\e[0;32m'
yellow_font='\e[0;33m'
underline='\e[4m'
no_underline='\e[24m'
no_decoration='\e[0m'

function _describe()
{
    rm -f $tmp.failed
    touch $tmp.failed

    aws cloudformation describe-stack-events \
        --region $REGION \
        --stack-name "$STACK" \
        --output text \
        --query 'StackEvents[*].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus]' \
    | sed -r -e 's/\.[0-9]{6}\+[0-9]{2}\:[0-9]{2}//g' \
    | awk -v now="$1" -v failed="$tmp.failed" '{if ($1 > now) { print; if (match($4, "[A-Z_]*FAILED[A-Z_]*")) print >> failed}}' \
    | sort \
    | awk '{printf("%-30s %-30s %-30s\n", $2, $3, $4)}' \
    | perl -ane 'print if !$seen{$F[1]}++' \
    | sed -E "s/([A-Z_]+_COMPLETE[A-Z_]*)/`printf       "${green_font}"`\1`printf "${no_decoration}"`/g" \
    | sed -E "s/([A-Z_]+_IN_PROGRESS[A-Z_]*)/`printf    "${yellow_font}"`\1`printf "${no_decoration}"`/g" \
    | sed -E "s/([A-Z_]*ROLLBACK[A-Z_]*)/`printf         "${red_font}"`\1`printf "${no_decoration}"`/g" \
    | sed -E "s/([A-Z_]*FAILED[A-Z_]*)/`printf           "${no_decoration}${red_background}"`\1`printf "${no_decoration}"`/g" \
    | sed -E "s/(AWS::CloudFormation::Stack)/`printf     "${underline}"`\1`printf "${no_decoration}"`/g"

    if [[ -s $tmp.failed ]]
    then
        cat $tmp.failed | while read ts ri rt rs
        do
            _warn $ri
            aws cloudformation describe-stack-events \
                --region $REGION \
                --stack-name "$STACK" \
                --output text \
                --query 'StackEvents[?LogicalResourceId==`'$ri'`&&contains(Timestamp,`'$ts'`)].ResourceStatusReason'
            echo
        done
    fi
}

function _status()
{
    echo

    while true
    do
        STATUS=$(aws cloudformation describe-stacks \
            --region $REGION \
            --stack-name $STACK \
            --query Stacks[0].StackStatus \
            --output text) 

        OLDNOW=$NOW
        _now
        _describe $OLDNOW

        if [[ $STATUS != *_IN_PROGRESS ]]
        then
            _describe $NOW            
            echo
            break
        fi

        sleep 2
       
    done
}

function _now()
{
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%S")
}

function _create()
{
    _header "Deploying $STACK"

    _now

    _walk aws cloudformation create-stack \
        --region $REGION \
        --stack-name $STACK \
        --template-body file://$FIRST \
        --output text

    _status

    _walk aws cloudformation wait stack-create-complete \
        --region $REGION \
        --stack-name $STACK
}

function _update()
{
    for t in $ALLBUTFIRST
    do
        _header "Updating $STACK with $t"

        _now

        _walk aws cloudformation update-stack \
            --region $REGION \
            --stack-name $STACK \
            --template-body file://$t \
            --output text \
            --capabilities CAPABILITY_AUTO_EXPAND

        _status

        _walk aws cloudformation wait stack-update-complete \
            --region $REGION \
            --stack-name $STACK

    done
}

function _apply()
{
    TEMPLATE=soln-$1.yaml
    if [[ ! -f $TEMPLATE ]]
    then
        _error "No such template $TEMPLATE"
    fi

    _header "Update $STACK with $TEMPLATE"

    _now

    _walk aws cloudformation update-stack \
        --region $REGION \
        --stack-name $STACK \
        --template-body file://$TEMPLATE \
        --output text \
        --capabilities CAPABILITY_AUTO_EXPAND

    _status

    _walk aws cloudformation wait stack-update-complete \
        --region $REGION \
        --stack-name $STACK
}

function _delete()
{
    _header "Deleting $STACK"

    _now

    _run aws cloudformation delete-stack \
        --region $REGION \
        --stack-name $STACK

    _run aws cloudformation wait stack-delete-complete \
        --region $REGION \
        --stack-name $STACK
}

function _usage()
{
    echo "Usage: $0 <create|update|delete|all|##>"
    echo ""
    echo "       $0 ##      Update solution using template soln-##.yaml"
    exit 1
}

if [[ $# -ne 1 ]]
then
    _usage
fi

case $1 in

    create)
        _create
        ;;
    
    update)
        _update
        ;;

    delete)
        _delete
        ;;

    all)
        _create
        _update
        _delete
        ;;

    status)
        _status
        ;;

    [0-1][0-9])
        _apply $1
        ;;

    *)
        _usage
        ;;

esac

status=0