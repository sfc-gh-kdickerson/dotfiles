#!/usr/bin/env bash

# LABEL=$(date '+%H:%M:%S')
LABEL=$(date '+%I:%M:%S %p')
sketchybar --set "$NAME" label="$LABEL"
