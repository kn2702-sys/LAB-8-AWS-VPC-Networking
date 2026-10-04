# Interview Q&A — say it out loud

## "Why does the public EC2 work?"

"My laptop hits the instance's public IP. The internet gateway does 1:1 NAT
to the private IP, the public route table's `0.0.0.0/0 → IGW` route brings it
in, and the security group allows my IP on port 22. The SG is stateful, so
the return traffic is automatically permitted."

## "Why can't the private EC2 reach the internet?"

"Three reasons: it has no public IP, its route table has no `0.0.0.0/0`
route — only `local` — and there's no NAT device. Packets to the internet
match no route and get dropped at the route lookup. A subnet is private
because of its route table, not its name."

## "What does a route table do?"

"It maps destination CIDRs to targets for a subnet. Longest-prefix match
wins, so `10.8.0.0/16 → local` beats `0.0.0.0/0 → IGW` for internal traffic.
Every subnet needs exactly one — explicit or the VPC main table — and the
`local` route can't be removed."

## "What does a security group do?"

"It's a stateful firewall on the instance's network interface. Allow-rules
only — no deny, everything else is implicitly denied. Because it's stateful,
allowing inbound SSH automatically permits the response."

## "Security group vs NACL?"

"SGs are stateful allow-lists at the instance level; NACLs are stateless
numbered allow/deny lists at the subnet level, lowest rule number first. The
classic failure is a NACL that allows port 443 in but forgets ephemeral ports
1024–65535 — connections hang because return traffic has no rule. I hit
exactly that in Drill 4."

## "How would you give the private subnet internet access?"

"Outbound-only: put a NAT Gateway in the public subnet, add
`0.0.0.0/0 → nat-gw` to the private route table. Inbound stays impossible by
design. And I'd flag the cost — NAT Gateways bill hourly plus data, so it's
a deliberate decision, not a default."
