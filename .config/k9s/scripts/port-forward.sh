#!/bin/bash
# Get the pod name and port from the user
POD_NAME=$1
POD_PORT=$2

if [ -z "$POD_NAME" ] || [ -z "$POD_PORT" ]; then
    echo "Usage: k9s-port-forward <pod-name> <pod-port>"
    exit 1
fi

(sleep 5; echo "Opening Safari"; open -a "Safari" localhost:$POD_PORT) &
# Execute kubectl port-forward command
echo "Port Forwarding $POD_NAME:$POD_PORT -> localhost:$POD_PORT"
kubectl port-forward pod/"$POD_NAME" "$POD_PORT":"$POD_PORT"
