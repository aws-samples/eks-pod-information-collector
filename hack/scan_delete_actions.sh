#!/bin/bash

set -o errexit

grep -qi 'delete\|remove' eks-pod-information-collector.sh
if [[ $? -eq 0 ]]; then
    exit 1
else
    exit 0
fi