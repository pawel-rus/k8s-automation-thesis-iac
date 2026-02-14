#!/bin/bash

kubectl get pvc -A -o json | jq -c '.items[] | {name:.metadata.name, ns:.metadata.namespace, finalizers:.metadata.finalizers}' | \
while read i; do
  name=$(echo $i | jq -r .name)
  ns=$(echo $i | jq -r .ns)
  kubectl patch pvc $name -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge
  kubectl delete pvc $name -n $ns
done

kubectl get pv -o json | jq -c '.items[] | {name:.metadata.name, finalizers:.metadata.finalizers}' | \
while read i; do
  name=$(echo $i | jq -r .name)
  kubectl patch pv $name -p '{"metadata":{"finalizers":[]}}' --type=merge
  kubectl delete pv $name
done

kubectl get pv -o json | jq -r '.items[] | select(.spec.csi.driver=="ebs.csi.aws.com") | .spec.csi.volumeHandle' | \
while read vol; do
  aws ec2 delete-volume --volume-id $vol
done

aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(DNSName, 'ingress')].[LoadBalancerName,DNSName,State]"
aws elbv2 describe-load-balancers --region eu-central-1

aws ec2 describe-volumes --region eu-central-1   --query "Volumes[*].{ID:VolumeId,State:State,Size:Size,AZ:AvailabilityZone,Tags:Tags}"   --output table > storages.txt