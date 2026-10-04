# Troubleshooting drills — break it on purpose

> Do these **after** [VERIFICATION.md](VERIFICATION.md) passes. Each drill is
> one misconfiguration; fix it before starting the next. Work in this order:
> **subnet → route table → security group → NACL** — the same order a NOC
> engineer isolates "can't reach it" tickets.

## Drill 1 — Subnet: instance in the wrong subnet

**Break it:** Terminate the public instance and launch its replacement in the
*private* subnet (same SG, same key):

```bash
aws ec2 run-instances --image-id $AMI --instance-type t2.micro \
  --key-name lab-8-key --subnet-id $PRIV --security-group-ids $PUB_SG \
  --no-associate-public-ip-address --region $REGION
```

**Symptom:** No public IP is assigned. SSH times out. The console shows the
instance "running" — green everywhere, still unreachable.

**Investigate:**
1. `aws ec2 describe-instances` → `SubnetId` is the *private* subnet,
   `PublicIpAddress` is empty.
2. Check the subnet: `map-public-ip-on-launch` is false on the private subnet.

**Root cause:** Reachability starts at placement. The instance was born in a
subnet with no public-IP assignment and no IGW route.

**Fix:** Terminate it; relaunch in `$PUB` with `--associate-public-ip-address`.
**Verify:** `ssh` connects; `curl http://<ip>` returns the test page.

**Interview line:** *"The instance was healthy — it was just in the wrong
subnet. I confirmed via describe-instances: private SubnetId, no public IP."*

---

## Drill 2 — Route table: public subnet on the private table

**Break it:**

```bash
PUB_RT_ID=$(aws ec2 describe-route-tables --filters Name=tag:Name,Values=lab-8-public-rt \
  --query 'RouteTables[0].RouteTableId' --output text --region $REGION)
ASSOC=$(aws ec2 describe-route-tables --route-table-ids $PUB_RT_ID \
  --query 'RouteTables[0].Associations[?SubnetId==`'$PUB'`].RouteTableAssociationId' \
  --output text --region $REGION)
aws ec2 disassociate-route-table --association-id $ASSOC --region $REGION
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PUB --region $REGION
```

**Symptom:** SSH to the public IP that *worked five minutes ago* now times out.
Instance is running, SG unchanged, public IP unchanged.

**Investigate:**
1. SG rules — unchanged, port 22 open to your IP. Not the SG.
2. Instance health checks — passing. Not the OS.
3. Route table for the public subnet: associated table is now
   `lab-8-private-rt` → **no `0.0.0.0/0` route**. Packets arrive at the VPC
   edge and have nowhere to go.

**Root cause:** Subnet associated with a route table lacking the IGW default route.

**Fix:** Disassociate from `$PRIV_RT`, re-associate `$PUB_RT`.
**Verify:** SSH works immediately — no instance reboot needed (routing is
not on the host).

**Interview line:** *"Same IP, same SG, dead overnight — that's a route-table
change. I checked the subnet's associated table and the 0.0.0.0/0 route
was gone."*

---

## Drill 3 — Security group: SSH locked out

**Break it:** Remove your SSH rule (or change it to a wrong IP):

```bash
aws ec2 revoke-security-group-ingress --group-id $PUB_SG \
  --protocol tcp --port 22 --cidr ${MY_IP}/32 --region $REGION
```

**Symptom:** `ssh` times out (not "connection refused" — *timeout*).

**Investigate:**
1. Route table — `0.0.0.0/0 → IGW` present. Not routing.
2. `aws ec2 describe-security-groups --group-ids $PUB_SG` → no TCP 22 ingress.
3. Note the symptom carefully: **timeout = silently dropped** (SG/NACL),
   **refused = reached host, nothing listening** (service down). That
   distinction alone is worth saying in an interview.

**Root cause:** SG ingress missing — packets dropped at the ENI.

**Fix:** Re-authorize port 22 from your IP.
**Verify:** SSH connects.

**Interview line:** *"Timeout versus refused tells you where to look. Timeout
with good routes means the packet died at a firewall — I checked the SG
first and the SSH rule was gone."*

---

## Drill 4 — NACL: the ephemeral-port trap (the classic)

**Break it:** Attach a custom NACL to the public subnet that allows web/SSH
inbound but forgets return traffic:

```bash
NACL=$(aws ec2 create-network-acl --vpc-id $VPC \
  --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=lab-8-drill-nacl}]' \
  --query 'NetworkAcl.NetworkAclId' --output text --region $REGION)
# inbound: allow SSH/HTTP only (the trap: no ephemeral range)
aws ec2 create-network-acl-entry --network-acl-id $NACL --rule-number 100 \
  --protocol tcp --port-range From=22,To=22 --cidr-block 0.0.0.0/0 \
  --rule-action allow --ingress --region $REGION
aws ec2 create-network-acl-entry --network-acl-id $NACL --rule-number 110 \
  --protocol tcp --port-range From=80,To=80 --cidr-block 0.0.0.0/0 \
  --rule-action allow --ingress --region $REGION
# outbound: allow everything (so it LOOKS fine)
aws ec2 create-network-acl-entry --network-acl-id $NACL --rule-number 100 \
  --protocol -1 --cidr-block 0.0.0.0/0 \
  --rule-action allow --egress --region $REGION
ASSOC=$(aws ec2 describe-network-acls --filters Name=tag:Name,Values=lab-8-drill-nacl \
  --query 'NetworkAcls[0].Associations[0].NetworkAclAssociationId' \
  --output text --region $REGION)
aws ec2 replace-network-acl-association --association-id $ASSOC \
  --network-acl-id $NACL --region $REGION
```

**Symptom:** `curl http://<public-ip>` **hangs** — connects, then stalls.
SSH may connect but freeze. The SG is perfect. The route table is perfect.

**Investigate:**
1. SG — port 80 open. Route table — IGW route present. Instance — httpd running.
2. Everything "looks right" at L3/L4 stateful layers… so go **stateless**:
   check the subnet's NACL.
3. NACL inbound allows 22/80 — but the *response* packets come back to
   **ephemeral ports (1024–65535)**, which have no allow rule → denied by
   the implicit deny.

**Root cause:** NACLs are stateless; return traffic needs its own inbound rule.

**Fix:** Add inbound rule 120: TCP 1024–65535 from `0.0.0.0/0`, allow.
(Or re-associate the default NACL to end the drill.)
**Verify:** `curl` returns the page instantly.

**Interview line:** *"SG fine, routes fine, but traffic hangs — that's the
stateless check. The NACL allowed the inbound port but not the ephemeral
return range. SGs track connections; NACLs don't."*

---

## Drill discipline (do this every time)

1. State the symptom precisely (timeout vs refused vs hang).
2. Isolate the layer: subnet → route table → SG → NACL → host.
3. Change **one thing**, re-test, record the result.
4. Write the one-line root cause before moving on — that's your interview answer.
