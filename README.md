# halo-vps-ansible

A setup script for a Linux server that hosts a Halo: Custom Edition game server.

Run one command and the server gets a non-root user, locked-down SSH, a firewall, Docker, and a Prometheus + Grafana monitoring stack — without you typing a hundred commands by hand.

This script was built by inspecting a real, already-running server and writing down exactly what was there. Re-running it against that server reports zero changes — proof that the script matches reality, not wishful thinking.

## What it sets up

Five steps, run in order:

1. **user** — creates a regular user with admin rights, adds your SSH key, and lets them run admin commands without typing a password.
2. **sshd_hardening** — turns off SSH password logins and root logins. Tests the SSH config before applying so you can't accidentally lock yourself out. (Loads before Ubuntu's cloud-init SSH config so the hardening actually wins.)
3. **firewall** — blocks all incoming traffic by default, then opens only what's needed: SSH (22), the Halo CE game port (2312/udp), and the monitoring ports (9100/9101) on the internal Docker network only.
4. **docker** — installs Docker from the official source and lets your user run it without sudo.
5. **monitoring** — drops a Prometheus + Grafana + node-exporter setup at `/opt/monitoring-platform/`, with Grafana only reachable through an SSH tunnel. Does **not** start it — you do that yourself after filling in `.env` with your secrets.

## How it fits with the other repos

Three repos, three jobs:

- **[terraform-homelab](https://github.com/julivnexe/terraform-homelab)** — rents the server (cloud VPS, DNS, TLS).
- **halo-vps-ansible** (this repo) — sets up and hardens the server.
- **[Halo-CE-Command-Center](https://github.com/julivnexe/Halo-CE-Command-Center)** — the actual Halo CE server software + the watchdog tools that monitor and auto-ban bad actors.

Terraform answers "does this server exist?" Ansible answers "is it set up safely?" Docker Compose answers "is the game running?"

## How to use it

1. Get a fresh Ubuntu 22.04 VPS (from terraform-homelab or any cloud provider). You'll log in as root or the default cloud user.
2. Open `group_vars/all.yml` and put your SSH public key in `ssh_public_key` and your desired username in `admin_user`.
3. Put the server's IP and SSH user in `inventory.ini` — or make a private copy called `inventory.ini.local` (that filename is gitignored).
4. If you're running Ansible directly on the VPS itself, run `./bootstrap.sh` first. It upgrades Ubuntu 22.04's old Ansible to a version new enough to work, and installs the required add-ons.
5. Run it:
   ```
   ansible-playbook -i inventory.ini playbook.yml
   ```
6. After the monitoring stack runs `docker compose up -d` for the first time, find its Docker bridge name and put it in `group_vars/all.yml` as `obs_bridge_iface`:
   ```
   ip link | grep '^[0-9]*: br-' | awk -F: '{print $2}' | tr -d ' '
   ```
   Re-run the playbook so the firewall opens monitoring ports on that bridge.

## Customizing for your own deployment

The committed config ships with placeholders (`<username>`, `<vps-ip>`, etc.) so this public repo isn't tied to one person's setup. Three ways to plug in your own values:

1. **Fork and edit** `group_vars/all.yml` directly. Simplest for a single-server deployment.
2. **`host_vars/halo-vps.yml`** with your real values — name it `halo-vps.yml.local` (gitignored) or extend `.gitignore` to cover the whole folder.
3. **`--extra-vars`** on the command line:
   ```
   ansible-playbook -i inventory.ini playbook.yml \
       -e admin_user=<username> \
       -e 'ssh_public_key="ssh-ed25519 AAAA... your-comment"' \
       -e obs_bridge_iface=br-abc123def456
   ```

Either way, keep `inventory.ini.local` for your real IP and SSH user.

## "Does it actually match the live server?"

Run it with `--check --diff` to preview without changing anything:

```
ansible-playbook -i inventory.ini playbook.yml --check --diff
```

A real run against the reference deployment reports `ok=21 changed=0 failed=0`. If you re-run it and see anything `changed`, that means the live server has drifted from the script — go investigate.

## Known rough edges (v0)

- **Docker bridge name is random.** `obs_bridge_iface` is a placeholder because the bridge name depends on the order Docker created networks. A future fix is to name the network explicitly in the compose file.
- **Compose file is copied as-is.** No templating yet. If you wanted to deploy this to multiple servers with different ports, you'd want to make the compose file a template.
- **Ubuntu 22.04 needs the bootstrap script.** Its built-in Ansible is too old. `bootstrap.sh` upgrades it.
- **No CI yet.** A GitHub Actions workflow running `ansible-playbook --syntax-check` and `ansible-lint` would be a nice v0.1 addition.
- **Reverse-engineered, not designed.** Some choices (passwordless sudo, SSH open to the whole internet) are convenient but wouldn't be your first pick if you were designing a security baseline from scratch. Read it before copying it.

## License

MIT. See [LICENSE](LICENSE).
