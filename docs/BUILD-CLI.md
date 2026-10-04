# Build guide — AWS CLI (recommended)

> Prefer clicking? See [BUILD-CONSOLE.md](BUILD-CONSOLE.md).
> Want it hands-free? [`scripts/build.sh`](../scripts/build.sh) runs these steps.

Set these once; every command below reuses them:

```bash
REGION=ap-south-1
AZ=${REGION}a
VPC_CIDR=10.8.0.0/16
PUB_CIDR=10.8.1.0/24
PRIV_CIDR=10.8.2.0/24
MY_IP=$(curl -s https://checkip.amazonaws.com)   # your public IP for the SSH rule
```

## 1. VPC

```bash
VPC=$(aws ec2 create-vpc --cidr-block $VPC_CIDR \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-8-vpc}]' \
  --query 'Vpc.VpcId' --output text --region $REGION)
echo "VPC: $VPC"

aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames \
  --region $REGION   # lets instances resolve public DNS names
```

## 2. Subnets

```bash
PUB=$(aws ec2 create-subnet --vpc-id $VPC --cidr-block $PUB_CIDR \
  --availability-zone $AZ \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-8-public}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION)

PRIV=$(aws ec2 create-subnet --vpc-id $VPC --cidr-block $PRIV_CIDR \
  --availability-zone $AZ \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-8-private}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION)

# Public subnet auto-assigns public IPs; private does not.
aws ec2 modify-subnet-attribute --subnet-id $PUB \
  --map-public-ip-on-launch --region $REGION
echo "public: $PUB  private: $PRIV"
```

## 3. Internet Gateway

```bash
IGW=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=lab-8-igw}]' \
  --query 'InternetGateway.InternetGatewayId' --output text --region $REGION)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW \
  --vpc-id $VPC --region $REGION
echo "IGW: $IGW"
```

## 4. Route tables

```bash
PUB_RT=$(aws ec2 create-route-table --vpc-id $VPC \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=lab-8-public-rt}]' \
  --query 'RouteTable.RouteTableId' --output text --region $REGION)
aws ec2 create-route --route-table-id $PUB_RT \
  --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW --region $REGION
aws ec2 associate-route-table --route-table-id $PUB_RT \
  --subnet-id $PUB --region $REGION >/dev/null

PRIV_RT=$(aws ec2 create-route-table --vpc-id $VPC \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=lab-8-private-rt}]' \
  --query 'RouteTable.RouteTableId' --output text --region $REGION)
aws ec2 associate-route-table --route-table-id $PRIV_RT \
  --subnet-id $PRIV --region $REGION >/dev/null
echo "public RT: $PUB_RT  private RT: $PRIV_RT"
# NOTE: the private table gets NO 0.0.0.0/0 route — that absence is the lab.
```

## 5. Security groups

```bash
PUB_SG=$(aws ec2 create-security-group --group-name lab-8-public-sg \
  --description "Lab 8 public tier" --vpc-id $VPC \
  --query 'GroupId' --output text --region $REGION)
aws ec2 authorize-security-group-ingress --group-id $PUB_SG \
  --protocol tcp --port 22 --cidr ${MY_IP}/32 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $PUB_SG \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION

PRIV_SG=$(aws ec2 create-security-group --group-name lab-8-private-sg \
  --description "Lab 8 private tier" --vpc-id $VPC \
  --query 'GroupId' --output text --region $REGION)
aws ec2 authorize-security-group-ingress --group-id $PRIV_SG \
  --protocol tcp --port 22 --source-group $PUB_SG --region $REGION
aws ec2 authorize-security-group-ingress --group-id $PRIV_SG \
  --protocol icmp --port -1 --cidr $VPC_CIDR --region $REGION
echo "public SG: $PUB_SG  private SG: $PRIV_SG"
```

## 6. Key pair

```bash
aws ec2 create-key-pair --key-name lab-8-key \
  --query 'KeyMaterial' --output text --region $REGION > lab-8-key.pem
chmod 400 lab-8-key.pem
```

## 7. EC2 instances

Amazon Linux 2023, always the current AMI via SSM (no hardcoded AMI IDs):

```bash
AMI=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' --output text --region $REGION)

PUB_EC2=$(aws ec2 run-instances --image-id $AMI --instance-type t2.micro \
  --key-name lab-8-key --subnet-id $PUB --security-group-ids $PUB_SG \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=lab-8-public-ec2}]' \
  --query 'Instances[0].InstanceId' --output text --region $REGION)

PRIV_EC2=$(aws ec2 run-instances --image-id $AMI --instance-type t2.micro \
  --key-name lab-8-key --subnet-id $PRIV --security-group-ids $PRIV_SG \
  --no-associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=lab-8-private-ec2}]' \
  --query 'Instances[0].InstanceId' --output text --region $REGION)

aws ec2 wait instance-running --instance-ids $PUB_EC2 $PRIV_EC2 --region $REGION
echo "public: $PUB_EC2  private: $PRIV_EC2"
```

Install a web server on the public instance (gives the HTTP test something to hit):

```bash
PUB_IP=$(aws ec2 describe-instances --instance-ids $PUB_EC2 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text --region $REGION)
PRIV_IP=$(aws ec2 describe-instances --instance-ids $PRIV_EC2 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text --region $REGION)

ssh -i lab-8-key.pem -o StrictHostKeyChecking=no ec2-user@$PUB_IP \
  "sudo dnf install -y httpd && sudo systemctl enable --now httpd \
   && echo 'lab-8 public OK' | sudo tee /var/www/html/index.html"
```

## 8. Reach the private instance (jump host)

```bash
ssh -i lab-8-key.pem -J ec2-user@$PUB_IP ec2-user@$PRIV_IP
```

The `-J` flag is the whole lesson in one command: the private instance has
no public IP and no internet route, so you *must* hop through the public one —
and the private security group only allows SSH *from the public SG*, which is
why it works.

Save your IDs — you'll need them for cleanup:

```bash
cat > lab-8-ids.env <<EOF
REGION=$REGION
VPC=$VPC
PUB=$PUB
PRIV=$PRIV
IGW=$IGW
PUB_RT=$PUB_RT
PRIV_RT=$PRIV_RT
PUB_SG=$PUB_SG
PRIV_SG=$PRIV_SG
PUB_EC2=$PUB_EC2
PRIV_EC2=$PRIV_EC2
EOF
```

Next: [VERIFICATION.md](VERIFICATION.md) to prove it works, then
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) to break it on purpose.
