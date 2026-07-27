# Privilege Escalation Lab — Docker Group Exploitation (T1611)

A self-contained, Infrastructure-as-Code lab that demonstrates how adding a
low-privileged user to the `docker` group grants that user unrestricted root
on the host — then automates detecting and fixing it.

The vulnerability isn't hand-configured. Terraform provisions the host and
Ansible introduces the misconfiguration itself, so the whole lab mirrors how
this actually happens in the real world: as a small, easy-to-miss line of
drift in automated deployment tooling.

## MITRE ATT&CK Mapping

| Field | Value |
|---|---|
| Technique | Escape to Host |
| ID | [T1611](https://attack.mitre.org/techniques/T1611/) |
| Tactic | Privilege Escalation |
| Root cause | `dev_user` added to the `docker` group, which is root-equivalent |

## Why This Matters

The Docker daemon runs as root and, by default, exposes a socket that
anything in the `docker` group can talk to with no further authorization
check. A user in that group can run:

```bash
docker run --rm -v /:/mnt alpine chroot /mnt sh
```

...and land in a root shell on the underlying host. No CVE, no exploit
chain — just a group membership that looks like a harmless developer
convenience in a code review.

## Architecture

```
                 ┌────────────────────┐
  terraform apply│   AWS EC2 (Ubuntu)  │
 ───────────────>│                    │
                 │  ┌──────────────┐  │
                 │  │   Docker     │  │
 ansible-playbook│  │   daemon     │  │
   (vulnerable)  │  │  (runs root) │  │
 ───────────────>│  └──────────────┘  │
                 │         ▲          │
                 │   docker group     │
                 │         │          │
                 │  ┌──────────────┐  │
                 │  │  dev_user    │──┼──> exploit/docker_group_escape.sh
                 │  │ (low-priv)   │  │       │
                 │  └──────────────┘  │       ▼
                 │                    │   root shell on host
                 └────────────────────┘

 ansible-playbook (harden) ──> removes dev_user from docker group
                               + auditd watch on group/socket changes
                               + Falco rule for runtime detection
```

## Repository Structure

```
docker-group-privilege-escalation/
├── terraform/                       # Provisions the EC2 lab host
│   ├── provider.tf
│   ├── main.tf                      # EC2 instance + security group (SSH only, your IP)
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/hosts.ini.example
│   ├── playbook-vulnerable.yml      # Installs Docker, creates dev_user, introduces the flaw
│   └── playbook-harden.yml          # Remediation: removes the flaw, adds detection
├── exploit/
│   └── docker_group_escape.sh       # Run as dev_user — proves host-root access
├── detection/
│   └── falco_rule_docker_escape.yaml # Runtime detection rule, deployed by the harden playbook
├── docs/
│   └── interview-prep.md            # STAR narrative + likely interview questions
└── README.md
```

## Prerequisites

- An AWS account with credentials configured (`aws configure`)
- An existing EC2 key pair in your target region
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html) (`ansible-playbook` on your PATH)
- An SSH client

> **Cost note:** this uses a single `t3.micro` instance, Free Tier eligible
> in most accounts. Run `terraform destroy` when you're done (step 8) so
> nothing keeps running.

## Step-by-Step Guide

### 1. Clone and configure Terraform

```bash
git clone <your-fork-or-remote-url> docker-group-privilege-escalation
cd docker-group-privilege-escalation/terraform

cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
region           = "us-east-1"
instance_type    = "t3.micro"
key_name         = "your-existing-aws-keypair-name"
allowed_ssh_cidr = "203.0.113.10/32"   # your public IP — run `curl -s ifconfig.me`
```

### 2. Provision the lab host

```bash
terraform init
terraform plan
terraform apply
```

Note the `instance_public_ip` in the output.

### 3. Point Ansible at the new host

```bash
cd ../ansible
cp inventory/hosts.ini.example inventory/hosts.ini
```

Edit `inventory/hosts.ini` and replace `YOUR.EC2.PUBLIC.IP` and the key path
with your real values.

### 4. Introduce the misconfiguration

```bash
ansible-playbook playbook-vulnerable.yml
```

This installs Docker, creates `dev_user`, and — as the deliberate flaw —
adds `dev_user` to the `docker` group.

### 5. Run the exploit

SSH in as `dev_user` (the account an attacker would have compromised via
some other, out-of-scope initial access) and run the script Ansible already
copied over:

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<instance_public_ip>
sudo su - dev_user
./docker_group_escape.sh
```

You should see output ending in a successful read from `/etc/shadow` as
root — proof that `dev_user` reached full host root using nothing but
`docker`.

### 6. Remediate

Back on your local machine:

```bash
cd ../ansible
ansible-playbook playbook-harden.yml
```

This removes `dev_user` from the `docker` group, adds `auditd` rules that
flag future group/socket drift, installs Falco (modern eBPF driver — no
DKMS or kernel headers needed), and deploys the detection rule from
`detection/falco_rule_docker_escape.yaml`. No manual driver setup or
Falco install required.

### 7. Confirm the fix

SSH back in and re-run the exploit:

```bash
sudo su - dev_user
./docker_group_escape.sh
```

It should now fail with a permission error — `dev_user` can no longer talk
to the Docker socket.

### 8. Clean up

```bash
cd ../terraform
terraform destroy
```

## Detection

`detection/falco_rule_docker_escape.yaml` ships two rules:

- **Unapproved User Invoked Docker CLI** — fires the moment any account
  outside `allowed_docker_admins` runs `docker`.
- **Host Filesystem Bind-Mounted Into Container** — fires specifically on
  the `-v /:/mnt` pattern used in the exploit script.

`playbook-harden.yml` installs Falco itself (from the official apt
repository, forced to the modern eBPF driver — no DKMS or kernel headers
needed) and drops this rule into `/etc/falco/rules.d/` automatically, so
`terraform apply` → `ansible-playbook playbook-vulnerable.yml` →
`ansible-playbook playbook-harden.yml` gets you a working detection stack
with zero manual steps. Falco runs as the `falco-modern-bpf` systemd
service — check it with `systemctl status falco-modern-bpf`.

## Safety Notes

- This lab intentionally creates a root-equivalent misconfiguration. Only
  run it on an isolated, disposable EC2 instance you control — never on
  shared or production infrastructure.
- `allowed_ssh_cidr` is enforced by a Terraform validation rule that refuses
  `0.0.0.0/0` — scope it to your own IP.
- Destroy the instance (`terraform destroy`) once you're done demoing it.
