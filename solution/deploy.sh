#!/bin/bash

tmp=/tmp/$$
status=1

_cleanup()
{
    rm -f $tmp.*
    exit $status
}

trap _cleanup 0 1 2 3

# Defaults
NETWORK=cfn-network
SECGRP=cfn-secgrp
PARENT=cfn-nested
REGION=ap-southeast-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET=${PARENT}-${REGION}-${ACCOUNT}

if [[ -z "$ACCOUNT" ]]
then
    _error "Unable to determine AWS account"
fi

# Network (single stack) templates
NETWORK_FIRST=$(ls -1 network-*.yaml | head -1)
ALLBUT_NETWORK_FIRST=$(ls -1 network-*.yaml | tail -n +2)
NETWORK_LAST=$(ls -1 network-*.yaml | tail -1)

# SecGrp (additional non-nested stack) templates
SECGRP_FIRST=$(ls -1 secgrp-*.yaml | head -1)
ALLBUT_SECGRP_FIRST=$(ls -1 secgrp-*.yaml | tail -n +2)
SECGRP_LAST=$(ls -1 secgrp-*.yaml | tail -1)

# Parent (multi-stack) templates
PARENT_FIRST=$(ls -1 parent-*.yaml | head -1)
ALLBUTPARENT_FIRST=$(ls -1 parent-*.yaml | tail -n +2)

# Colour output
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

# Usage: bucket options
function _create_bucket()
{
    if [ $# -eq 0 ]
    then
        _error "_create_bucket Requires at least the bucket name"
        exit 1
    fi

    B=$1
    shift
    EXTRAS="$*"

    if aws s3api head-bucket --bucket $B $EXTRAS 2>&1 | grep -q 404;
    then
        _walk aws s3 mb s3://$B $EXTRAS > /dev/null
        sleep 2
    fi
}

# Usage: bucket options
function _empty_bucket()
{
    if [ $# -eq 0 ]
    then
        _error "_empty_bucket Requires at least the bucket name"
    fi

    B=$1
    shift
    EXTRAS="$*"

    if ! aws s3api head-bucket --bucket $B $EXTRAS 2>&1 | grep -q 404;
    then
        _run aws s3 rm --recursive s3://$B $EXTRAS > /dev/null
    fi  
}

# Usage: bucket options
function _delete_bucket()
{
    if [ $# -eq 0 ]
    then
        _error "_delete_bucket requires at least the bucket name"
        exit 1
    fi

    B=$1
    shift
    EXTRAS="$*"

    if ! aws s3api head-bucket --bucket $B $EXTRAS 2>&1 | grep -q 404;
    then
        _run aws s3 rm --recursive s3://$B $EXTRAS > /dev/null
        _run aws s3 rb s3://$B $EXTRAS > /dev/null
    fi  
}

# Based on https://github.com/alestic/aws-cloudformation-stack-status/blob/parent/aws-cloudformation-stack-status
# Display cloudformation events and errors
red_font='\e[0;31m'
red_background='\e[41m'
green_font='\e[0;32m'
yellow_font='\e[0;33m'
underline='\e[4m'
no_underline='\e[24m'
no_decoration='\e[0m'

function _describe()
{
    if [ $# -ne 2 ]
    then
        _error "_describe requires stack name and timestamp"
        exit 1
    fi

    STACK=$1
    TIMESTAMP=$2

    rm -f $tmp.failed
    touch $tmp.failed

    aws cloudformation describe-stack-events \
        --region $REGION \
        --stack-name "$STACK" \
        --output text \
        --query 'StackEvents[*].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus]' \
    | sed -r -e 's/\.[0-9]{6}\+[0-9]{2}\:[0-9]{2}//g' \
    | awk -v now="$TIMESTAMP" -v failed="$tmp.failed" '{if ($1 > now) { print; if (match($4, "[A-Z_]*FAILED[A-Z_]*")) print >> failed}}' \
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
    if [ $# -ne 1 ]
    then
        _error "_status requires stack name"
        exit 1
    fi
    echo

    while true
    do
        STATUS=$(aws cloudformation describe-stacks \
            --region $REGION \
            --stack-name $1 \
            --query Stacks[0].StackStatus \
            --output text) 

        OLDNOW=$NOW
        _now
        _describe $1 $OLDNOW

        if [[ $STATUS != *_IN_PROGRESS ]]
        then
            _describe $1 $NOW            
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

function _outputs()
{
    if [ $# -ne 1 ]
    then
        _error "_outputs requires stack name"
        exit 1
    fi
    _run aws cloudformation describe-stacks \
        --region $REGION \
        --stack-name $1 \
        --query 'Stacks[*].Outputs' \
        --output table
}

function _create()
{
    if [ $# -le 1 ]
    then
        _error "_create requires stack name and template"
        exit 1
    fi

    STACK=$1
    TEMPLATE=$2
    shift 2

    if [[ ! -f $TEMPLATE ]]
    then
        _error "No such template $TEMPLATE"
    fi

    _header "Creating stack $STACK with $TEMPLATE"

    _now

    _walk aws cloudformation create-stack \
        --region $REGION \
        --stack-name $STACK \
        --template-body file://$TEMPLATE \
        --output text \
        --capabilities CAPABILITY_AUTO_EXPAND $*

    _status $STACK

    _walk aws cloudformation wait stack-create-complete \
        --region $REGION \
        --stack-name $STACK

    _outputs $STACK
}

function _apply()
{
    if [ $# -le 1 ]
    then
        _error "_apply requires at least stack name and template"
        exit 1
    fi

    STACK=$1
    TEMPLATE=$2
    shift 2

    if [[ ! -f $TEMPLATE ]]
    then
        _error "No such template $TEMPLATE"
    fi

    _header "Update stack $STACK with $TEMPLATE"

    _now

    _walk aws cloudformation update-stack \
        --region $REGION \
        --stack-name $STACK \
        --template-body file://$TEMPLATE \
        --output text \
        --capabilities CAPABILITY_AUTO_EXPAND $*

    _status $STACK

    _walk aws cloudformation wait stack-update-complete \
        --region $REGION \
        --stack-name $STACK

    _outputs $STACK
}


function _update()
{
    if [[ $# -le 1 ]]
    then
        _error "_update expecting stack and list of templates"
    fi

    STACK=$1
    shift

    _header "Updating $STACK with $*"

    for t in $*
    do
        _apply $STACK $t
    done
}

function _delete()
{
    if [ $# -ne 1 ]
    then
        _error "_delete requires stack name"
        exit 1
    fi

    _header "Deleting stack $1"

    _run aws cloudformation delete-stack \
        --region $REGION \
        --stack-name $1

    _run aws cloudformation wait stack-delete-complete \
        --region $REGION \
        --stack-name $1
}

function _copy_to_bucket()
{
    _header "Create $BUCKET for nested templates"

    _create_bucket $BUCKET --region $REGION
    _walk aws s3 sync . s3://$BUCKET
}


function _usage()
{
    echo "Usage: $0 <create|update|outputs|delete|all|##>"
    echo ""
    echo "       $0 ##      Update solution using template soln-##.yaml"
    exit 1
}

if [[ $# -ne 1 ]]
then
    _usage
fi


case $1 in
    
    network)
        _create $NETWORK $NETWORK_FIRST
        _update $NETWORK $ALLBUT_NETWORK_FIRST
        ;;

    secgrp)
        _create $SECGRP $SECGRP_FIRST
        _apply $SECGRP secgrp-02.yaml --parameters ParameterKey=SshCidr,ParameterValue=0.0.0.0/0
        ;;
        
    bucket)
        _copy_to_bucket
        ;;

    parent|nested)
        _copy_to_bucket
        _create $PARENT $PARENT_FIRST --parameters ParameterKey=Bucket,ParameterValue=$BUCKET
        _apply $PARENT parent-02.yaml --parameters ParameterKey=Bucket,ParameterValue=$BUCKET
        ;;

    delete)
        _delete $PARENT
        _delete_bucket $BUCKET --region $REGION
        _delete $SECGRP
        _delete $NETWORK
        ;;

    output)
        _outputs $NETWORK
        _outputs $SECGRP
        _outputs $PARENT
        ;;

    status)
        _status $NETWORK
        _status $SECGRP
        _status $PARENT
        ;;

    deploy)
        _create $NETWORK $NETWORK_FIRST
        _update $NETWORK $ALLBUT_NETWORK_FIRST
        _create $SECGRP $SECGRP_FIRST
        _apply $SECGRP secgrp-02.yaml --parameters ParameterKey=SshCidr,ParameterValue=0.0.0.0/0
        _copy_to_bucket
        _create $PARENT $PARENT_FIRST --parameters ParameterKey=Bucket,ParameterValue=$BUCKET
        _apply $PARENT parent-02.yaml --parameters ParameterKey=Bucket,ParameterValue=$BUCKET
        ;;
    
    n1)
        _create $NETWORK $NETWORK_FIRST
        ;;

    n[2-9])
        _apply $NETWORK network-0${1:1}.yaml
        ;;

    s1)
        _create $SECGRP $SECGRP_FIRST
        ;;

    s2)
        _apply $SECGRP secgrp-0${1:1}.yaml --parameters ParameterKey=SshCidr,ParameterValue=0.0.0.0/0
        ;;

    p1)
        _create $PARENT $PARENT_FIRST --parameters ParameterKey=Bucket,ParameterValue=$BUCKET
        ;;
    
    p[2-3])
        _apply $PARENT parent-0${1:1}.yaml --parameters ParameterKey=Bucket,ParameterValue=$BUCKET
        ;;

    *)
        _usage
        ;;

esac

status=0