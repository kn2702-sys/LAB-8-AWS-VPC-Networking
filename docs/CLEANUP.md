# Cleanup — tear it all down

> Do this when the lab is done. A forgotten `t2.micro` is cheap; the habit
> of cleaning up is what interviewers actually want to hear about.

```bash
source lab-8-ids.env

# 1. Instances first (everything else depends on them being gone)
aws ec2 terminate-instances --instance-ids $PUB_EC2 $PRIV_EC2 --region $REGION
aws ec2 wait instance-terminated --instance-ids $PUB_EC2 $PRIV_EC2 --region $REGION

# 2. Security groups (can't delete while referenced — private SG references
#    the public SG, so delete private first)
aws ec2 delete-security-group --group-id $PRIV_SG --region $REGION
aws ec2 delete-security-group --group-id $PUB_SG --region $REGION

# 3. Route tables: remove the IGW route, disassociate, delete
#    (the main route table can't be deleted — only the two we made)
aws ec2 delete-route --route-table-id $PUB_RT \
  --destination-cidr-block 0.0.0.0/0 --region $REGION
for RT in $PUB_RT $PRIV_RT; do
  for ASSOC in $(aws ec2 describe-route-tables --route-table-ids $RT \
      --query 'RouteTables[0].Associations[?Main!=`true`].RouteTableAssociationId' \
      --output text --region $REGION); do
    aws ec2 disassociate-route-table --association-id $ASSOC --region $REGION
  done
  aws ec2 delete-route-table --route-table-id $RT --region $REGION
done

# 4. Internet gateway: detach, then delete
aws ec2 detach-internet-gateway --internet-gateway-id $IGW \
  --vpc-id $VPC --region $REGION
aws ec2 delete-internet-gateway --internet-gateway-id $IGW --region $REGION

# 5. Subnets, then VPC
aws ec2 delete-subnet --subnet-id $PUB --region $REGION
aws ec2 delete-subnet --subnet-id $PRIV --region $REGION
aws ec2 delete-vpc --vpc-id $VPC --region $REGION

# 6. Key pair (the .pem is yours to delete locally)
aws ec2 delete-key-pair --key-name lab-8-key --region $REGION
rm -f lab-8-key.pem lab-8-ids.env
```

Verify nothing is left billing you:

```bash
aws ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value]' \
  --output text --region $REGION
aws ec2 describe-vpcs --filters Name=tag:Name,Values=lab-8-vpc \
  --query 'Vpcs[].VpcId' --output text --region $REGION
```

Both should come back empty.
