#!/usr/bin/env bash

ls -altrh

MATCH=$(grep -i 'delete\|remove' ../eks-pod-information-collector.sh)
if [[ -n $MATCH ]]; then
    exit 1
else
    exit 0
fi