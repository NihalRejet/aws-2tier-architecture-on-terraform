# AWS Two-Tier Architecture with Terraform

[![Terraform CI](https://github.com/NihalRejet/aws-2tier-architecture-on-terraform/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/NihalRejet/aws-2tier-architecture-on-terraform/actions/workflows/terraform-ci.yml)

Terraform code that builds a classic two-tier web application on AWS: a public
web tier running a containerised Flask app, and a private data tier running
MySQL on RDS that cannot be reached from the internet.

Everything is written as reusable modules. The database password is generated
by Terraform, kept in Secrets Manager, and read by the app at start-up through an
IAM role, so it never appears in the code or on the server's boot script. Every
push is checked by CI.

---

## Architecture

```mermaid
graph TB
    User["User / Browser"]

    subgraph Region["AWS Region: us-east-1"]
        SM["Secrets Manager<br/>DB username + password"]
        IGW["Internet Gateway"]

        subgraph VPC["VPC &mdash; 10.0.0.0/16"]
            subgraph Public["Public Subnet &mdash; 10.0.1.0/24 &mdash; AZ a"]
                EC2["EC2 t3.micro<br/>Docker &rarr; Flask app<br/>port 80"]
            end

            subgraph Private["Private Subnets &mdash; 10.0.2.0/24 + 10.0.3.0/24 &mdash; AZ a, AZ b"]
                RDS[("RDS MySQL 8.0<br/>db.t3.micro<br/>encrypted, not publicly accessible")]
            end
        end
    end

    User -->|"HTTP :80"| IGW
    IGW --> EC2
    EC2 -->|"MySQL :3306<br/>web SG only"| RDS
    EC2 -.->|"GetSecretValue at start-up<br/>(IAM role, this secret only)"| SM
```

**How the two tiers are kept apart**

- The public subnet has a route table pointing at the Internet Gateway, so the
  EC2 instance is reachable from outside.
- The private subnets are left on the VPC's main route table, which only has
  the `local` route. There is no path to the internet from them in either
  direction, so there is no NAT Gateway and no NAT Gateway bill.
- The database security group has no CIDR-based rule at all. Its only inbound
  rule references the **web security group**, so the database accepts traffic
  from the web tier and nothing else, even if the routing were wrong.
- Two private subnets exist because an RDS subnet group requires subnets in two
  availability zones. The database instance itself runs in one AZ.

---

## What gets created

| Module | Resources |
|---|---|
| `vpc` | VPC, 1 public subnet, 2 private subnets, Internet Gateway, public route table and association |
| `security_groups` | Web SG (HTTP from anywhere, SSH from a CIDR you choose) and DB SG (MySQL from the web SG only) |
| `secrets` | A 16-character random password and a Secrets Manager secret holding the credentials |
| `rds` | DB subnet group and a MySQL 8.0 instance, encrypted at rest, not publicly accessible |
| `ec2` | Ubuntu 22.04 instance that installs Docker, builds the Flask image and runs it on port 80, plus an IAM role and instance profile that can read only the database secret |

---

## Repository layout

```
.
├── main.tf                     # wires the modules together
├── variables.tf                # input variables and their defaults
├── outputs.tf                  # URLs, endpoints and IDs after apply
├── terraform.tfvars.example    # copy to terraform.tfvars and edit
├── modules/
│   ├── vpc/                    # network layer
│   ├── security_groups/        # firewall rules for both tiers
│   ├── secrets/                # password generation + Secrets Manager
│   ├── rds/                    # MySQL database
│   └── ec2/                    # web server
│       └── templates/
│           └── user_data.sh    # bootstraps Docker and the Flask app
└── .github/workflows/
    └── terraform-ci.yml        # validate + security scan on every push
```

---

## Prerequisites

- Terraform 1.0 or newer
- An AWS account and the AWS CLI configured (`aws configure`)
- IAM permissions to create VPC, EC2, RDS and Secrets Manager resources

---

## Deploying

```bash
# 1. Set your variables
cp terraform.tfvars.example terraform.tfvars

# 2. Restrict SSH to your own IP before applying
curl -s https://checkip.amazonaws.com        # note the address
# then set ssh_allowed_cidr = "YOUR.IP.ADDR/32" in terraform.tfvars

# 3. Deploy
terraform init
terraform plan
terraform apply
```

The database takes several minutes to come up, and the EC2 instance needs
another minute or two after that to install Docker and build the image. If the
page does not load straight away, give it a moment.

### Checking it worked

```bash
terraform output application_url     # open this in a browser
terraform output health_check_url    # returns 200 if the app reached the DB
```

If something goes wrong on the instance, the bootstrap log is written to
`/var/log/user-data.log` on the EC2 box, and `sudo docker logs flask-container`
shows the app's own output.

To confirm the password is not on the server, look at the boot script AWS
stored for the instance. It contains the secret's ARN but no password:

```bash
aws ec2 describe-instance-attribute --attribute userData \
  --instance-id "$(terraform output -raw web_server_instance_id)" \
  --query UserData.Value --output text | base64 -d | grep -i secret
```

### Tearing it down

```bash
terraform destroy
```

This removes everything, including the secret. Leaving the stack running costs
money, so destroy it when you are done.

---

## Cost

The stack uses the smallest sizes: a `t3.micro` instance, a `db.t3.micro`
database and 20 GB of storage. How much of that is free depends on when your
AWS account was created:

- **Created on or after 15 July 2025:** the Free plan gives $100 in credits at
  sign-up (up to $200 by completing a few starter tasks) for 6 months, and it
  cannot charge you until you upgrade to a paid plan.
- **Created before that:** the older 12-month Free Tier applies, which covers
  one micro instance and one micro database for the first year.

Things to watch:

- **Secrets Manager is not in the free tier.** It charges a small amount per
  secret per month (around $0.40 at the time of writing — check the
  [current pricing](https://aws.amazon.com/secrets-manager/pricing/)). This repo
  sets the secret's recovery window to 0, so `terraform destroy` deletes it
  straight away instead of keeping it, and billing it, for another 30 days.
- Public IPv4 addresses are billed by the hour outside the free allowance.
- Run `terraform destroy` when you are done. A running stack costs money every
  hour, whatever you are or are not doing with it.

---

## Security choices

What this code does:

- The database has no public IP and no route to the internet.
- The database security group trusts the web security group, not an IP range.
- The master password is generated by Terraform, never written in the repo, and
  stored in Secrets Manager.
- The web server reads the credentials from Secrets Manager when the app
  starts. Its IAM role allows one action (`secretsmanager:GetSecretValue`) on
  one secret. user_data only holds the secret's ARN.
- RDS storage and the EC2 root volume are both encrypted at rest.
- The instance requires IMDSv2, so instance metadata cannot be read through a
  simple server-side request forgery against the app. The hop limit is 2 so
  the app inside its Docker container can still reach it for the role's
  credentials.
- `*.tfvars` and `*.tfstate` are gitignored. State files hold secrets in
  plaintext, so they must never be committed.
- Message content is HTML-escaped before it is rendered, and SQL uses
  parameterised queries.
- GitHub Actions are pinned to full commit SHAs rather than version tags,
  because tags can be moved to different code (as happened to
  `trivy-action` in March 2026, CVE-2026-33634).

### Known gaps

These are deliberate trade-offs for a demo, not oversights. They are the first
things that would change for a real deployment.

| Gap | Why it matters | What production would do |
|---|---|---|
| The password is in the Terraform **state** file | Terraform generated it, so state holds it in plaintext; `sensitive = true` only hides it from terminal output | Encrypted remote state with tight access, or let RDS create and rotate the password itself (`manage_master_user_password = true`) |
| HTTP only, no TLS | Traffic and form data travel in clear text | An ALB with an ACM certificate, redirecting port 80 to 443 |
| Single instance, single AZ | Any instance or AZ failure takes the whole app down | ALB + Auto Scaling Group across AZs, and `multi_az = true` on RDS |
| No remote state backend | State lives on one laptop, with no locking | Encrypted, versioned S3 bucket with state locking |
| No VPC Flow Logs | No record of what connected to what | Flow Logs to CloudWatch or S3 |
| `skip_final_snapshot = true` | `destroy` throws the data away | Take a final snapshot and turn on deletion protection |

---

## Live application

The app writes to and reads from the RDS database, so the page proves the two
tiers are actually talking to each other.

![Application UI](assets/demo1.png)

![Database health check](assets/demo2.png)

---

## Built with

Terraform · AWS (VPC, EC2, RDS, Secrets Manager) · Docker · Python / Flask ·
MySQL · GitHub Actions · Trivy
