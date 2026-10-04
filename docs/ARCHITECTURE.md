# Architecture & addressing plan

## Region & AZ

| Choice | Value | Why |
|---|---|---|
| Region | `ap-south-1` (Mumbai) | Closest to India; lowest latency for testing |
| AZ | `ap-south-1a` | Single AZ keeps the lab simple — this is a networking lab, not an HA lab |

> A production design would span 2–3 AZs. That's a deliberate scope cut,
> stated here so an interviewer sees you know the difference.

## CIDR plan

| Scope | CIDR | Usable hosts | Notes |
|---|---|---|---|
| VPC | `10.8.0.0/16` | 65,531 | Private RFC 1918 space; `10.8` chosen to avoid colliding with common `10.0`/`192.168` lab networks |
| Public subnet | `10.8.1.0/24` | 251 | Web/edge tier |
| Private subnet | `10.8.2.0/24` | 251 | App/data tier pattern |
| Reserved headroom | `10.8.3.0/24`+ | — | Left free on purpose — shows you plan for growth |

AWS reserves 5 IPs per subnet (`.0` network, `.1` VPC router, `.2` DNS,
`.3` future, `.255` broadcast). Know this — it's a favorite interview
trivia question and it explains why a `/24` gives 251, not 254.

## Route tables

**`lab-8-public-rt`** (associated with the public subnet):

| Destination | Target | Meaning |
|---|---|---|
| `10.8.0.0/16` | local | VPC-internal traffic never leaves |
| `0.0.0.0/0` | `lab-8-igw` | Everything else goes to the internet |

**`lab-8-private-rt`** (associated with the private subnet):

| Destination | Target | Meaning |
|---|---|---|
| `10.8.0.0/16` | local | Only VPC-internal traffic is routable |

The private table is the entire lesson: **a subnet is "private" because of
its route table**, not because of its name or CIDR. Rename it "public" and
nothing changes.

## Gateways & firewalls

| Component | Config | Notes |
|---|---|---|
| Internet Gateway `lab-8-igw` | Attached to VPC | Does 1:1 NAT between public IPs and private instance IPs |
| `lab-8-public-sg` | In: TCP 22 from `<your-ip>/32`, TCP 80 from `0.0.0.0/0` · Out: all | SSH locked to you; HTTP open for the curl test |
| `lab-8-private-sg` | In: TCP 22 from `lab-8-public-sg`, ICMP from `10.8.0.0/16` · Out: all | SSH only via jump host; ping only inside VPC |
| NACLs | Default (allow all) to start | Drill 4 replaces this — see TROUBLESHOOTING |

## Instances

| | Public | Private |
|---|---|---|
| AMI | Amazon Linux 2023 (via SSM parameter, always current) | Same |
| Type | t2.micro / t3.micro (free tier) | Same |
| Subnet | `10.8.1.0/24` | `10.8.2.0/24` |
| Public IP | Yes (auto-assign) | No |
| Access | SSH directly | SSH via public instance (`ssh -J`) |

## What this deliberately excludes

- **NAT Gateway** — covered as a design question in CONCEPTS (with cost
  warning), not built. Keeps the lab free and the private subnet truly isolated.
- **Multi-AZ** — single AZ; HA is out of scope for a networking-fundamentals lab.
- **Load balancer / Auto Scaling** — application concerns, not networking.
