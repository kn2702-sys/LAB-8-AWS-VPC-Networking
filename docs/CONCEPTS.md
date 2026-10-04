# Concepts — the "why" behind every click

Read this before the drills. If you can explain each of these out loud,
the lab did its job.

## Why does the public EC2 work?

Trace one SSH packet from your laptop to the public instance:

1. **Your laptop → internet** with destination = the instance's public IP.
2. **Internet Gateway** receives it. The IGW does 1:1 NAT: it translates the
   public IP to the instance's private IP (`10.8.1.x`) and forwards it into
   the VPC. (This is why the instance itself never sees its public IP —
   `ip addr` inside shows only the private one.)
3. **Route table** for the public subnet: `0.0.0.0/0 → IGW` got the packet
   *to* the VPC edge; the `10.8.0.0/16 → local` route delivers it inside.
4. **Security group** (`lab-8-public-sg`) checks: TCP 22 from your IP?
   Allow. (SGs are stateful — the return packet is automatically allowed,
   no inbound rule needed for it.)
5. Instance responds; the path reverses through the IGW's NAT.

Remove *any one* of those and it breaks — which is exactly what the drills do.

## Why can't the private EC2 reach the internet?

Three independent reasons, and you should be able to name all three:

1. **No public IP.** The instance only has `10.8.2.x`. Internet hosts can't
   route back to RFC 1918 space, so even if a packet left, the reply could
   never return.
2. **No IGW route.** Its route table has only `10.8.0.0/16 → local`. A packet
   to `0.0.0.0/0` matches *no route* and is dropped right there. This is the
   sharpest answer: **a subnet is private because of its route table.**
3. **No NAT device.** Even with a route, something must translate
   private→public. That's the IGW's job (public subnets) or a NAT Gateway's
   job (private subnets needing *outbound-only* access).

## What does a route table do?

- Every subnet **must** be associated with exactly one route table
  (explicitly, or the VPC's main table by default).
- It's a lookup: **longest-prefix match wins**. `10.8.0.0/16 → local` beats
  `0.0.0.0/0 → IGW` for VPC-internal traffic.
- `local` is automatic and **cannot be deleted** — VPC members always reach
  each other at L3 (SGs/NACLs may still block, but routing won't).

## What does a security group do?

- A **stateful virtual firewall at the instance (ENI) level**.
- **Allow rules only** — there is no deny; anything not allowed is denied.
- **Stateful**: allow inbound TCP 22 and the return traffic is automatically
  permitted, regardless of outbound rules.
- Referencing another SG as a source (`--source-group`) is how tiers talk:
  "only the public tier may SSH to me" without hardcoding IPs.

## Security Group vs Network ACL

| | Security Group | Network ACL |
|---|---|---|
| Level | Instance / ENI | Subnet |
| Stateful? | **Yes** — return traffic auto-allowed | **No** — you must allow both directions |
| Rules | Allow only | **Allow *and* deny**, evaluated by rule number (lowest first) |
| Default | Deny all inbound, allow all outbound | Allow all both ways |
| Classic trap | — | Allowing inbound 443 but forgetting **ephemeral ports 1024–65535** inbound → connections hang (Drill 4) |

Interview one-liner: *"SGs are stateful allow-lists on the instance; NACLs
are stateless numbered rule lists on the subnet. If return traffic breaks
and the SG looks fine, check the NACL's ephemeral-port range."*

## Packet-flow walkthroughs

**Public instance, `curl http://<public-ip>` from your laptop:**

```text
laptop → IGW (public→private NAT) → public route table → SG check (80 open)
→ httpd responds → SG stateful return → IGW (private→public NAT) → laptop
```

**Private instance, `ping 8.8.8.8` from inside it:**

```text
instance → private route table → no route for 0.0.0.0/0 → DROP (right here)
```

Nothing leaves. No timeout mystery — the drop happens at the route lookup.

## NAT Gateway — the design answer (not built)

"How *would* you give the private subnet outbound-only internet?" →

1. Allocate an Elastic IP, create a **NAT Gateway in the public subnet**.
2. Add `0.0.0.0/0 → nat-gw` to the **private** route table.
3. Private instances can now initiate outbound (updates, API calls); inbound
   from the internet is still impossible — NAT GW is one-way by design.

**Why not built here:** ~$0.045/hr + data charges, 24/7. It never sleeps and
it never stops billing. Know the pattern; build it only when you need it.

## IAM tie-in (your résumé claims it)

The lab uses SSH key pairs, but the modern answer is **SSM Session Manager**:

- Attach an IAM role with `AmazonSSMManagedInstanceCore` to the instance.
- Connect via `aws ssm start-session` — **no inbound port 22 rule needed at
  all**, no key pair to lose, all sessions logged to CloudTrail/S3.
- Interview line: *"I'd rather not open SSH to the world and manage keys —
  SSM with an IAM role removes the port and the secret in one move."*

That single paragraph turns "IAM" on your résumé from a keyword into a
decision you can defend.
