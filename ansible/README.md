# BoneLab Ansible Design

Clusters and projects in the lab use a variety of Ansible roles for configuration purposes. There are also supplied playbooks and a recommended cluster environment layout to keep things clean.

We've set the `roles_path` parameter in a sample included `ansible.cfg` file so playbooks can be located in a subdirectory for the sake of organization.

> [!NOTE]
> All of the roles described here assume Debian-based Linux systems. No effort was made to generalize to other Linux platforms or accommodate BSD. Carefully examine roles before attempting to use them on anything but a Debian, Ubuntu, Mint, etc., system.

## Groups

Based on the TODO of roles that currently or will exist, these are the host groups that should be used to follow the best practices for this Ansible setup.

- `docker` - Any system which should act as a Docker host. Recommended for using the `docker` role.
- `home` - Intended for "home" or "local" systems not otherwise part of a dev/stage/prod environment. This is commonly a system used to launch playbooks, code projects, and so on.
- `proxmox` - All Proxmox systems. Recommended for using the `proxmox` role.
- `webserver` - Any server which should serve HTTP(S), PHP, WSGI, etc. Recommended for using the `webserver` role.

## Roles

The list of roles will continue to expand. Any variables mentioned here are listed with defaults so the role operates normally when they are unset.

### `common` Role

This role should be applied to all servers in all environments, including the local "home" system. It sets a standard baseline of expectations. It performs multiple actions:

- Installs direnv, nano, less, and rsync as standard utilities.
- Strongly discourages kernel page swapping.
- Disables memory overcommit, and sets the amount of overcommit memory to the total RAM for the server.
- Defines a few useful CLI aliases.
- "Beautifies" the system prompt. Prompt includes user, hostname, current working directory, current date and time, and the number of commands executed in the shell. It is also color-coded based on environment using the following list: prod = red, stage = green, dev = green, local = blue. This makes it _very_ obvious what environment is being accessed and minimizes mistakes.

#### Recognized Variables

- `env_name` : Set to one of `prod`, `stage`, `dev`, or `local`. Default `dev`.

### `k0s-proxy Role

Bootstraps a proxy host specifically for a K0s control plane. This allows multiple control plane nodes within a K0s cluster as described in the [Control Plane High Availability](https://docs.k0sproject.io/head/high-availability) documentation. This role will:

- Install and enable HAProxy
- Configure HAProxy to direct traffic on ports 6443, 8132, and 9443 to control plane nodes in a round-robin manner. Control plane nodes are identified as any nodes assigned to the `control_plane` group.
- Restart HAProxy if necessary

### `firewall` Role

Intended as a "meta" role, meant for public-facing servers of any kind.

- Installs and enables [fail2ban](https://github.com/fail2ban/fail2ban) using service defaults.
- Sets up `iptables` to reject all traffic from China and Lithuania as _strong_ sources of past break-in attempts.

This role will eventually be modified to allow expanding or overriding the country blacklist.

### `proxmox` Role

Should prepare any Proxmox system for standard use.

- Installs and configures nginx to act as a proxy for the web admin dashboard.
- Overrides `sysstat` to collect system information every minute rather than every 10 minutes.

## Pending Roles

These roles are planned but are not yet part of the repository. This may be because they are in some stage of testing, or require an internal migration before initial public-facing commit.

### `docker` Role

Install Docker and related utilties on desired hosts. This role will use the community edition directly from Docker's repositories.

- Removes any docker related packages from the distribution's standard repository.
- Installs the Docker-CE repository
- Installs Docker-CE, CLI, containerd, and the buildx and compose plugins.
- Adds the `ansible_user` variable user to the `docker` system group.
- Reboots the system if the user was added to the `docker` group.

### `webserver` Role

Installs the standard web-server expected in the current stack and any necessary build utilities.

- Installs nginx configured for hosting any domains defined in the inventory.
- Installs a specified version of Hugo for site deployment.

Eventually this role will also set up Lets Encrypt for configured domains, likely using [acmetool](https://github.com/hlandau/acmetool) unless a better option presents itself.

#### Recognized Variables

- `hugo_version` : This determines which version of Hugo to install. Should be either `latest` or the version number with the `v` omitted; eg. `0.124.0`. Default is `latest`.
- `public_facing` : If true, will also include the `firewall` role. Strongly encourage enabling this on production systems.  Default is false.
