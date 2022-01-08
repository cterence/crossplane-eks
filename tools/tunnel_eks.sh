#!/bin/sh

# Usage : ./tunnel_eks.sh <bastion_name> <cluster_name> (args are optional if you do not edit the names in the resources)

BASTION_NAME_ARG="$1"
CLUSTER_NAME_ARG="$2"
BASTION_NAME="${BASTION_NAME_ARG:=bastion}"
CLUSTER_NAME="${CLUSTER_NAME_ARG:=eks-cluster}"

# Get the bastion instance ID
BASTION_INSTANCE_ID=$(aws ec2 describe-instances | jq -r --arg bastion_name "$BASTION_NAME" '.Reservations[].Instances[] | select(.State.Name == "running" and .Tags[] == {"Key": "Name", "Value": $bastion_name}) | .InstanceId')

# Get the cluster endpoint domain
CLUSTER_ENDPOINT_DOMAIN=$(aws eks describe-cluster --name "$CLUSTER_NAME" | jq -r '.cluster.endpoint' | sed 's/https:\/\///')

# Get the IPs of the cluster endpoint (one by subnet)
CLUSTER_ENDPOINT_IPS=$(dig +short "$CLUSTER_ENDPOINT_DOMAIN" | grep '^[.0-9]*$'| sed 's/$/\/32/' | xargs)

# Start an SSM session with the bastion instance :
# - in the background 
# - portforwarding the 22 remote port to the 9999 local port 
aws ssm start-session --target "$BASTION_INSTANCE_ID" --document-name AWS-StartPortForwardingSession --parameters 'portNumber=22,localPortNumber=9999' &

# Record the PID of the session
SESSION_PID=$!

# Start an SSH tunnel 
# - on local port 9999
# - with retry on failure
# - with the bastion SSH key as the identity key
# - forwarding the cluster endpoint IPs to the tunnel 
sshuttle -e 'ssh -o '\''ConnectionAttempts 5'\'' -p 9999 -i ~/.ssh/bastion.pem' -r ubuntu@localhost $CLUSTER_ENDPOINT_IPS

# Stop the SSM session after the SSH tunnel was closed by the user
kill $SESSION_PID
