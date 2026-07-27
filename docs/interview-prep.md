# Interview Prep — Talking About This Project

Use the STAR method (Situation, Task, Action, Result), mapped directly to MITRE ATT&CK.

## 🌟 Situation

"I wanted to understand how a common but easy-to-miss misconfiguration — adding
a low-privileged user to the `docker` group — can quietly grant full root on
a host. I built a DevSecOps lab around MITRE ATT&CK **T1611 (Escape to
Host)**."

## 🛠️ Task

"My goal was to use Infrastructure as Code to provision a realistic AWS
environment, automate the exact misconfiguration that causes this in
practice, prove the resulting privilege escalation with a working exploit,
and then automate both the fix and runtime detection for it."

## 🚀 Action

"I used Terraform to provision an EC2 instance, and Ansible to configure it —
including, as the deliberate flaw, adding a low-privileged `dev_user` account
to the `docker` group. I wrote a Bash script that a compromised `dev_user`
account could run: it starts a container with the host's root filesystem
bind-mounted in, then `chroot`s into that mount — landing in a root shell on
the underlying host with nothing beyond `docker` group membership. I proved
impact by reading a root-only file from that shell. I then wrote a second
Ansible playbook that removes `dev_user` from the `docker` group, adds
`auditd` rules to flag future group-membership drift, and ships a Falco rule
that flags any non-admin account invoking the Docker CLI at runtime."

## 📈 Result

"The project demonstrated how a single group membership — something that
looks harmless in a code review — is functionally equivalent to unrestricted
root access on that host. It reinforced why 'is this user in the `docker`
group' has to be a hard-fail check in CI/CD and IAM audits, not a judgment
call made at deploy time."

---

## Questions an Interviewer Will Ask

**"How do you prevent this in production?"**

> We avoid granting `docker` group membership directly at all — it's
> equivalent to unrestricted root and shouldn't be treated as a convenience
> grant. Where developers genuinely need container access, we use scoped
> alternatives (rootless Docker, or a broker like a TLS+RBAC-fronted Docker
> context) instead of raw group membership. On the IaC side, we run
> `ansible-lint` and `tfsec`/`checkov` in CI to catch privilege-granting
> changes like this before they merge. At runtime, we run Falco (or an
> equivalent eBPF-based agent) to alert whenever a non-admin account invokes
> the Docker CLI or a container mounts the host filesystem — the exact
> signals this lab's detection rules are built around.

**"Why did you choose MITRE ATT&CK for this?"**

> Because it maps the technical flaw directly to real-world adversary
> behavior. It let me design defenses against an actual tactic threat actors
> use (T1611, Escape to Host) rather than just patching an isolated bug, and
> it gives me a shared vocabulary with security teams when I explain the
> risk.

**"Isn't this just a config mistake — why treat it as a security finding?"**

> Because the blast radius is identical to a root compromise, but it usually
> ships through a change that looks completely benign — "add the dev team to
> the docker group so they can manage their own containers." Attackers don't
> need a novel exploit here; they just need to compromise any account that
> already has that grant. Treating it as a security finding (not just a
> style nit) is what gets it caught in review instead of in an incident.
