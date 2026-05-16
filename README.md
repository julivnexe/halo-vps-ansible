# halo-vps-ansible

Idempotent Ansible playbook that codifies the OS-layer hardening of a production game-server VPS — non-root sudo user, sshd hardening drop-in (with the cloud-init ordering fix), UFW baseline, Docker install, and the monitoring stack from [game-server-sentry](https://github.com/julivnexe/game-server-sentry).

This playbook was reverse-engineered from a running server. It runs `changed=0` against the live state — meaning it's a true codification of what's actually there, not aspirational config.

## What it does

Five roles, applied in order:

1. **`user`** — creates a non-root sudo user with key-based SSH access and a `NOPASSWD: ALL` sudoers drop-in.
2. **`sshd_hardening`** — writes `/etc/ssh/sshd_config.d/49-hardening.conf` (deliberately numbered to load before Ubuntu's `50-cloud-init.conf`, which uses first-match-wins and would otherwise overrule `PasswordAuthentication no`). Validates with `sshd -t` before reloading.
3. **`firewall`** — UFW baseline: default-deny inbound, default-allow outbound, explicit allows for SSH (22/tcp), game-server port (2312/udp), and the Prometheus scrape ports (9100/9101) bound to the Docker bridge interfaces only.
4. **`docker`** — installs Docker CE from the official apt repo, adds the admin user to the `docker` group.
5. **`monitoring`** — places the observability stack's `docker-compose.yml` (Prometheus + Grafana + node-exporter + the netmon-alert/auto-banner pair from game-server-sentry) under `/opt/monitoring-platform/`, with Grafana bound to `127.0.0.1` for SSH-tunnel-only access. Deliberately does **not** start the stack — operator does that after populating `.env` with secrets.

## Why this exists

Companion to two other repos:

- **[terraform-homelab](https://github.com/julivnexe/terraform-homelab)** provisions infrastructure — VPS, DNS, TLS. Layer 1.
- **halo-vps-ansible** (this repo) configures the OS layer on top of whatever Terraform provisions. Layer 2.
- **[game-server-sentry](https://github.com/julivnexe/game-server-sentry)** is the application this stack hosts and monitors. Layer 3.

Different layers, different tools. Terraform handles "does this server exist?" Ansible handles "is this server hardened?" Compose handles "is the app running?"

## Usage

1. Provision a fresh Ubuntu 22.04 VPS (use terraform-homelab or any cloud provider). Initial SSH access as root or the cloud-default user.
2. Copy your SSH public key into `group_vars/all.yml` as the `ssh_public_key` variable.
3. Set `admin_user` in `group_vars/all.yml` and the VPS IP / SSH user in `inventory.ini` (or create `inventory.ini.local` with real values — the `.local` suffix is `.gitignore`'d).
4. If running ansible directly on the VPS (no separate controller), run `./bootstrap.sh` first. This handles the Ubuntu 22.04 `ansible-core 2.12` → `2.16` upgrade and installs the required Galaxy collections.
5. Apply: `ansible-playbook -i inventory.ini playbook.yml`
6. After first `docker compose up -d` of the monitoring stack, find the new Docker bridge name and update `obs_bridge_iface` in `group_vars/all.yml`:
   ```
   ip link | grep '^[0-9]*: br-' | awk -F: '{print $2}' | tr -d ' '
   ```
   Re-run the playbook to add the per-bridge UFW rules.

## Operator customization

The committed `group_vars/all.yml` and `inventory.ini` ship with placeholders (`<username>`, `<vps-ip>`, `<docker-network-id-prefix>`, etc.) so the public repo isn't tied to one operator's deployment. Three ways to inject your real values:

1. **Fork and edit** `group_vars/all.yml` directly in your downstream copy. Simplest for a single-operator deployment.
2. **`host_vars/halo-vps.yml`** with the real values — this file is `.gitignore`'d via the `*.local` pattern if you name it `halo-vps.yml.local`, or you can extend `.gitignore` to cover `host_vars/`.
3. **`--extra-vars`** on the command line:
   ```
   ansible-playbook -i inventory.ini playbook.yml \
       -e admin_user=<username> \
       -e 'ssh_public_key="ssh-ed25519 AAAA... your-comment"' \
       -e obs_bridge_iface=br-abc123def456
   ```

Either way, keep `inventory.ini.local` for your real VPS IP and SSH user — the committed `inventory.ini` only has placeholders.

## Idempotency

Running this playbook against an already-configured host produces `changed=0`. If a re-run reports anything `changed`, something is drifting between the playbook and the actual state. Check first with:

```
ansible-playbook -i inventory.ini playbook.yml --check --diff
```

The verified baseline (against the reference deployment): `ok=21 changed=0 failed=0`.

## v0 caveats

- **Docker bridge interface name is hash-derived.** The `obs_bridge_iface` variable is a placeholder; the actual name depends on the docker network creation order. Future improvement: name the network explicitly in the compose file to get a stable bridge name across deployments.
- **Compose file is a verbatim template.** No Jinja parametrization yet. For multi-host deployments you'd want to variable-ize ports, image tags, and `.env` contents.
- **ansible-core upgrade is required on Ubuntu 22.04** because apt ships 2.12, which is too old for current Galaxy collection metadata. `bootstrap.sh` handles this on the VPS itself.
- **No CI yet.** A GitHub Actions workflow running `ansible-playbook --syntax-check` and `ansible-lint` on every push would be a v0.1 addition.
- **Reverse-engineered, not designed.** Some choices (e.g. `NOPASSWD: ALL` for the admin user, an open `22/tcp` from anywhere) are operationally convenient but not what you'd write from scratch as a security baseline. Audit before adopting elsewhere.

## License

MIT. See [LICENSE](LICENSE).
