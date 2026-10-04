#!/usr/bin/env bash
# Lab 8 — tear it all down. Mirrors docs/CLEANUP.md.
# Usage: ./scripts/cleanup.sh   (reads lab-8-ids.env)
set -euo pipefail

source lab-8-ids.env

echo "==> Terminating instances"
aws ec2 terminate-instances --instance-ids "$PUB_EC2" "$PRIV_EC2" --region "$REGION"
aws ec2 wait instance-terminated --instance-ids "$PUB_EC2" "$PRIV_EC2" --region "$REGION"

echo "==> Security groups (private first: it references the public SG)"
aws ec2 delete-security-group --group-id "$PRIV_SG" --region "$REGION"
aws ec2 delete-security-group --group-id "$PUB_SG" --region "$REGION"

echo "==> Route tables"
aws ec2 delete-route --route-table-id "$PUB_RT" \
  --destination-cidr-block 0.0.0.0/0 --region "$REGION"
for RT in "$PUB_RT" "$PRIV_RT"; do
  for ASSOC in $(aws ec2 describe-route-tables --route-table-ids "$RT" \
      --query 'RouteTables[0].Associations[?Main!=`true`].RouteTableAssociationId' \
      --output text --region "$REGION"); do
    aws ec2 disassociate-route-table --association-id "$ASSOC" --region "$REGION"
  done
  aws ec2 delete-route-table --route-table-id "$RT" --region "$REGION"
done

echo "==> Internet gateway"
aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" \
  --vpc-id "$VPC" --region "$REGION"
aws ec2 delete-internet-gateway --internet-gateway-id "$IGW" --region "$REGION"

echo "==> Subnets + VPC"
aws ec2 delete-subnet --subnet-id "$PUB" --region "$REGION"
aws ec2 delete-subnet --subnet-id "$PRIV" --region "$REGION"
aws ec2 delete-vpc --vpc-id "$VPC" --region "$REGION"

echo "==> Key pair"
aws ec2 delete-key-pair --key-name lab-8-key --region "$REGION"
rm -f lab-8-key.pem lab-8-ids.env

echo "Cleanup complete. Verify with:"
echo "  aws ec2 describe-vpcs --filters Name=tag:Name,Values=lab-8-vpc --region $REGION"
