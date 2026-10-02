# VPS Deployment Guide

## Initial Setup (one-time)

### 1. Prepare VPS (Ubuntu)

```bash
# SSH into your VPS
ssh user@your-vps-ip

# Install Python 3 and pip
sudo apt update
sudo apt install -y python3 python3-pip git

# Create deploy user (optional but recommended)
sudo useradd -m -s /bin/bash deploy
sudo usermod -aG sudo deploy

# Create app directory
sudo mkdir -p /opt/alchemists-loop
sudo chown deploy:deploy /opt/alchemists-loop

# Clone repository
sudo -u deploy git clone https://github.com/RedRad1sh/alchemists-loop.git /opt/alchemists-loop
```

### 2. Configure Environment

```bash
# Create database directory
sudo mkdir -p /var/lib/alchemists-loop
sudo chown deploy:deploy /var/lib/alchemists-loop

# Create .env file
sudo -u deploy nano /opt/alchemists-loop/discovery-server/server/.env
```

Add your configuration:
```
DATABASE_URL=postgresql://user:pass@localhost/alchemists
API_KEY=your-secret-key
# ... other env vars
```

### 3. Install systemd Service

```bash
# Copy service file
sudo cp /opt/alchemists-loop/discovery-server/server/discovery-server.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable discovery-server

# Start service
sudo systemctl start discovery-server

# Check status
sudo systemctl status discovery-server
```

### 4. Configure GitHub Secrets

In your GitHub repository:
- Go to **Settings** → **Secrets and variables** → **Actions**
- Add these secrets:
  - `VPS_HOST`: Your VPS IP address or hostname
  - `VPS_USER`: SSH username (e.g., `deploy`)
  - `VPS_SSH_KEY`: Private SSH key (contents of `~/.ssh/id_rsa` or `~/.ssh/id_ed25519`)

### 5. Setup SSH Key Authentication

```bash
# On your local machine, generate SSH key if you don't have one
ssh-keygen -t ed25519 -C "github-actions"

# Copy public key to VPS
ssh-copy-id -i ~/.ssh/id_ed25519.pub deploy@your-vps-ip

# Copy private key to GitHub secret (VPS_SSH_KEY)
cat ~/.ssh/id_ed25519
```

## Deployment

### Manual Deployment via GitHub Actions

1. Go to **Actions** tab in GitHub
2. Select **Deploy to VPS** workflow
3. Click **Run workflow**
4. Choose environment (production/staging)
5. Click **Run workflow**

### Manual Deployment via SSH

```bash
# SSH into VPS
ssh deploy@your-vps-ip

# Navigate to app directory
cd /opt/alchemists-loop

# Pull latest changes
git pull origin master

# Install dependencies
cd discovery-server/server
python3 -m pip install -r requirements.txt --user

# Restart service
sudo systemctl restart discovery-server

# Check status
sudo systemctl status discovery-server
```

## Monitoring

### View Logs

```bash
# Real-time logs
sudo journalctl -u discovery-server -f

# Last 100 lines
sudo journalctl -u discovery-server -n 100

# Logs since specific time
sudo journalctl -u discovery-server --since "2026-09-28 12:00:00"
```

### Service Management

```bash
# Start service
sudo systemctl start discovery-server

# Stop service
sudo systemctl stop discovery-server

# Restart service
sudo systemctl restart discovery-server

# Check status
sudo systemctl status discovery-server

# Disable auto-start
sudo systemctl disable discovery-server
```

## Troubleshooting

### Service won't start

```bash
# Check service status
sudo systemctl status discovery-server

# Check logs
sudo journalctl -u discovery-server -n 50

# Test manually
cd /opt/alchemists-loop/discovery-server/server
python3 server.py
```

### Permission denied

```bash
# Fix ownership
sudo chown -R deploy:deploy /opt/alchemists-loop

# Check service user
sudo systemctl cat discovery-server | grep User
```

### Port already in use

```bash
# Find process using port
sudo lsof -i :8000

# Kill process
sudo kill -9 <PID>
```

## Multiple Applications

To deploy multiple apps on the same VPS:

1. Create separate directories:
   ```bash
   /opt/alchemists-loop/
   /opt/another-app/
   ```

2. Create separate systemd services:
   ```bash
   /etc/systemd/system/discovery-server.service
   /etc/systemd/system/another-app.service
   ```

3. Use different ports or reverse proxy (nginx/caddy)

## Security Checklist

- [ ] SSH key authentication enabled (no passwords)
- [ ] Firewall configured (UFW or iptables)
- [ ] Fail2ban installed for SSH protection
- [ ] Regular backups configured
- [ ] `.env` file not in git repository
- [ ] Service runs as non-root user
- [ ] Python dependencies updated regularly
