# Console build path (alternative to the CLI)

> The [CLI guide](BUILD-CLI.md) is recommended — it's reproducible and it's
> what you'd show in an interview. This is the click-path for the same result.

## 1. VPC
VPC Console → **Create VPC** → *VPC and more* is overkill here; choose
**VPC only** → Name `lab-8-vpc`, CIDR `10.8.0.0/16` → Create.
Then select it → Actions → **Edit VPC settings** → enable **DNS hostnames**.

## 2. Subnets
VPC → **Subnets** → Create subnet → select `lab-8-vpc`:
- `lab-8-public` — `10.8.1.0/24`, AZ `ap-south-1a`
- `lab-8-private` — `10.8.2.0/24`, AZ `ap-south-1a`

Select `lab-8-public` → Actions → **Edit subnet settings** → enable
**auto-assign public IPv4**. Leave the private subnet off.

## 3. Internet Gateway
VPC → **Internet gateways** → Create → `lab-8-igw` → Actions →
**Attach to VPC** → `lab-8-vpc`.

## 4. Route tables
VPC → **Route tables** → Create:
- `lab-8-public-rt` → Subnet associations → associate `lab-8-public` →
  Routes → Add: `0.0.0.0/0` → Internet Gateway → `lab-8-igw`.
- `lab-8-private-rt` → associate `lab-8-private`. Add **no** routes —
  the `local` route is already there, and its absence of `0.0.0.0/0` is the lab.

## 5. Security groups
EC2 → **Security groups** → Create (VPC `lab-8-vpc`):
- `lab-8-public-sg` — Inbound: SSH/22 from **My IP**, HTTP/80 from anywhere.
- `lab-8-private-sg` — Inbound: SSH/22 from **source = `lab-8-public-sg`**
  (type the SG name, not an IP), All ICMP from `10.8.0.0/16`.

## 6. Key pair
EC2 → **Key pairs** → Create → `lab-8-key`, `.pem` → download, `chmod 400`.

## 7. Instances
EC2 → **Launch instances** → Amazon Linux 2023, t2.micro:
- **Public:** subnet `lab-8-public`, auto-assign public IP **enabled**,
  SG `lab-8-public-sg`, key `lab-8-key`. Then SSH in and
  `sudo dnf install -y httpd && sudo systemctl enable --now httpd`.
- **Private:** subnet `lab-8-private`, auto-assign public IP **disabled**,
  SG `lab-8-private-sg`, key `lab-8-key`. Reach it with
  `ssh -i lab-8-key.pem -J ec2-user@<public-ip> ec2-user@<private-ip>`.
