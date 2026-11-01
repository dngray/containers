
# Radicale User Management

This guide explains how to manage user accounts for your Radicale CalDAV/CardDAV server using the `htpasswd` utility.

## Prerequisites

You must have the apache utilities installed on your host machine to use the `htpasswd` command:

```bash
# Ubuntu / Debian
sudo apt update && sudo apt install apache2-utils -y

# RHEL / Rocky Linux
sudo dnf install httpd-tools -y
```

---

## Managing Users

Always execute these commands from your core configuration directory (`/opt/appdata/radicale`).

### 1. Create the File and Add the First User

To create a brand new `users` file and register your first account, use the `-c` (create) and `-B` (bcrypt encryption) flags:

```bash
htpasswd -B -c ./users alice
```

> [!WARNING]
> Only use the `-c` flag for the very first user. Running it again later will completely wipe out your existing file and delete all other users.

### 2. Add Subsequent Users

To append additional accounts (like `bob` or `charlie`) to your existing file, **omit** the `-c` flag:

```bash
htpasswd -B ./users bob
htpasswd -B ./users charlie
```

### 3. Change a User's Password

To update an existing user's password, simply run the append command again with their username. It will safely overwrite their old hash:

```text
htpasswd -B ./users alice
```

### 4. Delete a User Account

To completely remove a user's login access from the server, use the `-D` (delete) flag:

```text
htpasswd -D ./users charlie
```

---

## Post-Execution Verification

### Verify File Structure

After modifying accounts, ensure your file contains the encrypted hashes by printing it out:

```text
cat ./users
```

### Fix File Permissions

If your Docker container fails to boot with a `Permission Denied` log entry after you modify this file, reset the folder ownership so the rootless container user can read it:

```text
sudo chown -R 1000:1000 /opt/appdata/radicale
```
