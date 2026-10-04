# Verification checklist

Run these right after the build. Every line should pass before you start
the [troubleshooting drills](TROUBLESHOOTING.md).

```bash
source lab-8-ids.env
PUB_IP=$(aws ec2 describe-instances --instance-ids $PUB_EC2 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region $REGION)
PRIV_IP=$(aws ec2 describe-instances --instance-ids $PRIV_EC2 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text --region $REGION)
```

## Network fabric

- [ ] VPC `10.8.0.0/16` exists, DNS hostnames enabled
- [ ] Public subnet `10.8.1.0/24` has `map-public-ip-on-launch = true`
- [ ] Private subnet `10.8.2.0/24` has `map-public-ip-on-launch = false`
- [ ] IGW attached to the VPC (`aws ec2 describe-internet-gateways`)
- [ ] Public route table: `10.8.0.0/16 → local` **and** `0.0.0.0/0 → igw-…`
- [ ] Private route table: `10.8.0.0/16 → local` **only** (no `0.0.0.0/0`)
- [ ] Public SG: TCP 22 from your IP, TCP 80 from `0.0.0.0/0`
- [ ] Private SG: TCP 22 from the *public SG* (not an IP), ICMP from `10.8.0.0/16`

## Public instance (the "it works" proof)

- [ ] `ssh -i lab-8-key.pem ec2-user@$PUB_IP` connects
- [ ] `curl http://$PUB_IP` returns `lab-8 public OK`
- [ ] From the public instance: `ping -c 3 $PRIV_IP` succeeds (VPC-local routing)

## Private instance (the "it's isolated" proof)

- [ ] `ssh -i lab-8-key.pem -J ec2-user@$PUB_IP ec2-user@$PRIV_IP` connects (jump host)
- [ ] From the private instance: `ping -c 3 8.8.8.8` **fails** (no route — expected)
- [ ] From the private instance: `curl -m 5 https://checkip.amazonaws.com` **fails** (expected)
- [ ] Direct `ssh ec2-user@$PRIV_IP` from your laptop **fails** (no public IP — expected)

> The failures above are the lab working correctly. If the private instance
> *can* reach the internet, something is misconfigured — treat it as a
> bonus drill.
