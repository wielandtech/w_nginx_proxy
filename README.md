# NGINX Reverse Proxy for Homelab

This Docker-based NGINX reverse proxy forwards traffic from `wielandtech.com` to your homelab Kubernetes cluster, with **TLS termination happening in the cluster** using Traefik and cert-manager.

## 🏗️ Architecture

```
Internet → VPS (NGINX) → Homelab Router → Traefik LoadBalancer → Website Pod
         HTTP/HTTPS      Port Forward      (TLS Termination)
```

**Traffic Flow:**
- **HTTP (Port 80)**: 
  - `/.well-known/acme-challenge/` → Forwarded to homelab for Let's Encrypt verification
  - Everything else → Redirected to HTTPS
- **HTTPS (Port 443)**: TCP/TLS passthrough directly to homelab (encrypted end-to-end)
- **TLS Certificates**: Managed by cert-manager in homelab cluster with Let's Encrypt
- **Private Keys**: Stay secure in homelab, never touch the VPS

**Key Benefits:**
- ✅ End-to-end encryption (VPS never sees unencrypted traffic)
- ✅ Certificates managed automatically by cert-manager
- ✅ Private keys never leave your homelab
- ✅ Simple VPS configuration (just a TCP proxy)
- ✅ Automatic certificate renewal

## 📋 Prerequisites

1. **VPS Requirements**:
   - Docker and Docker Compose installed
   - Ports 80 and 443 open in firewall
   - Domain `wielandtech.com` DNS pointing to VPS IP

2. **Homelab Requirements**:
   - Kubernetes cluster with Traefik and cert-manager
   - Traefik LoadBalancer running (192.168.70.240)
   - Port forwarding: 80/443 → 192.168.70.240:80/443
   - Website deployed with proper ingress configuration
   - cert-manager ClusterIssuer configured for Let's Encrypt

3. **Network Requirements**:
   - Homelab accessible from VPS (WAN IP or DDNS)
   - Router port forwarding configured

## 🚀 Quick Start

### 1. Clone and Configure

```bash
# Navigate to the nginx-proxy directory
cd nginx-proxy

# Copy environment template
cp env.template .env

# Edit configuration
nano .env
```

### 2. Configure Environment

Edit `.env` file with your settings:

```bash
# Your homelab's WAN IP or DDNS hostname
HOMELAB_IP=123.456.789.012
# OR
HOMELAB_IP=yourhome.ddns.net

# Domain (usually no need to change)
DOMAIN=wielandtech.com
```

### 3. Deploy

```bash
# Make scripts executable
chmod +x deploy.sh health-check.sh

# Deploy the stack
./deploy.sh
```

### 4. Verify Deployment

```bash
# Check health
./health-check.sh

# View logs
docker-compose logs -f

# Test locally
curl -H "Host: wielandtech.com" http://localhost/nginx-health
```

## 🔧 Configuration Files

### Core Configuration

- `docker-compose.yml` - Main orchestration file
- `env.template` - Environment variables template
- `.env` - Your actual configuration (create from template)

### NGINX Configuration

- `nginx/nginx.conf` - Main NGINX configuration with stream module
- `nginx/default.conf.template` - HTTP configuration (ACME challenges & redirects)
- `nginx/stream.d/https-passthrough.conf.template` - HTTPS TCP passthrough
- `nginx/maintenance.html` - Fallback maintenance page

### Scripts

- `deploy.sh` - Automated deployment script
- `health-check.sh` - Health monitoring and diagnostics
- `test-fallback.sh` - Test fallback page functionality

## 🔍 Testing and Validation

### Local Testing

```bash
# Test HTTP health endpoint
curl -H "Host: wielandtech.com" http://localhost/nginx-health

# Test HTTP proxy
curl -H "Host: wielandtech.com" http://localhost/

# Test HTTPS pass-through (if homelab is accessible)
curl -H "Host: wielandtech.com" https://localhost/ -k

# Test fallback page functionality
./test-fallback.sh
```

### External Testing (after DNS update)

```bash
# Test HTTP access
curl -I http://wielandtech.com

# Test HTTPS access
curl -I https://wielandtech.com

# Test SSL certificate
openssl s_client -servername wielandtech.com -connect wielandtech.com:443
```

### Health Monitoring

```bash
# Run health checks
./health-check.sh check

# View recent logs
./health-check.sh logs

# Continuous monitoring
./health-check.sh monitor
```

## 🔧 Fallback Page Functionality

### Overview

When your homelab is unavailable (network issues, maintenance, etc.), NGINX automatically serves a branded "under construction" page instead of showing generic error pages.

### How It Works

- **HTTP Traffic**: When upstream returns 502/503/504 errors, NGINX serves the maintenance page
- **HTTPS Traffic**: Stream module passes through directly, so HTTPS will fail when homelab is down (expected behavior)
- **Automatic Fallback**: No manual intervention required - happens automatically

### Testing Fallback

```bash
# Test fallback functionality
./test-fallback.sh

# View maintenance page directly
curl -H "Host: wielandtech.com" http://localhost/maintenance

# Simulate downtime and test (advanced)
./test-fallback.sh test
```

### Customizing the Maintenance Page

Edit `nginx/maintenance.html` to customize:
- Branding and colors
- Contact information
- Expected resolution time
- Additional messaging

After editing, restart the container:
```bash
docker-compose restart nginx
```

### Fallback Behavior

| Scenario | HTTP (Port 80) | HTTPS (Port 443) |
|----------|----------------|------------------|
| Homelab Up | Proxied to homelab | Passed through to homelab |
| Homelab Down | Shows maintenance page | Connection fails |
| Network Issues | Shows maintenance page | Connection timeout |
| Traefik Down | Shows maintenance page | Connection refused |

## 🛠️ Homelab Configuration

### Update Traefik Ingress

Your homelab website needs to accept the external domain. Update your HelmRelease:

```yaml
# In w_homelab/clusters/prod/apps/website/website-helmrelease.yaml
ingress:
  main:
    enabled: true
    className: traefik
    hosts:
      - host: wielandtech.k8s.local  # Keep existing
        paths:
          - path: /
            pathType: Prefix
      - host: wielandtech.com        # Add external domain
        paths:
          - path: /
            pathType: Prefix
      - host: www.wielandtech.com    # Add www variant
        paths:
          - path: /
            pathType: Prefix
```

### Traefik Certificate Configuration

Ensure Traefik can obtain certificates for external domains:

```yaml
# In your Traefik configuration
certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@example.com
      storage: /data/acme.json
      httpChallenge:
        entryPoint: web
      # OR for DNS challenge:
      # dnsChallenge:
      #   provider: cloudflare
```

## 🔒 Security Features

### Rate Limiting

- **General**: 30 requests/second with burst of 50
- **API**: 10 requests/second with burst of 10
- **Authentication**: 5 requests/minute with burst of 3

### Security Headers

- X-Frame-Options: SAMEORIGIN
- X-Content-Type-Options: nosniff
- X-XSS-Protection: 1; mode=block
- Referrer-Policy: strict-origin-when-cross-origin
- Content-Security-Policy: Configured for web applications

### Access Control

- Blocks access to sensitive files (`.env`, `.git`, etc.)
- Denies access to admin paths
- Hides server information
- Prevents common exploit attempts

## 📊 Monitoring and Maintenance

### Health Checks

The health check script monitors:

- Docker container status
- NGINX configuration validity
- Local health endpoint
- Homelab connectivity
- External website access
- SSL certificate status
- Resource usage

### Log Management

Logs are stored in the `logs/` directory:

- `nginx/access.log` - HTTP access logs
- `nginx/error.log` - NGINX error logs
- `nginx/stream_access.log` - HTTPS stream logs
- `nginx/stream_error.log` - Stream errors
- `health-check.log` - Health check results

### Automated Monitoring

Set up a cron job for regular health checks:

```bash
# Add to crontab
*/5 * * * * /path/to/nginx-proxy/health-check.sh check >> /var/log/nginx-proxy-health.log 2>&1
```

## 🚨 Troubleshooting

### Common Issues

#### 1. 502 Bad Gateway

**Symptoms**: HTTP 502 errors when accessing the site

**Causes & Solutions**:
- Homelab not accessible from VPS
  ```bash
  # Test connectivity
  curl -I http://YOUR_HOMELAB_IP:80
  ```
- Port forwarding not configured
  - Check router settings: 80/443 → 192.168.70.240
- Traefik not running in homelab
  ```bash
  # Check homelab
  kubectl get pods -n traefik
  ```

#### 2. SSL/TLS Issues

**Symptoms**: SSL certificate errors or connection refused on 443

**Causes & Solutions**:
- Traefik not handling SSL properly
  - Check Traefik ingress configuration
  - Verify certificate resolver settings
- DNS not pointing to VPS
  ```bash
  # Check DNS resolution
  dig wielandtech.com
  ```

#### 3. Rate Limiting

**Symptoms**: HTTP 429 errors

**Solutions**:
- Adjust rate limits in `nginx/security.conf`
- Check for bot traffic or attacks
- Review access logs for patterns

#### 4. Container Issues

**Symptoms**: Container not starting or crashing

**Solutions**:
```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs nginx

# Test configuration
docker-compose exec nginx nginx -t

# Restart services
docker-compose restart
```

#### 5. Fallback Page Issues

**Symptoms**: Generic error pages instead of maintenance page

**Causes & Solutions**:
- Maintenance page not mounted correctly
  ```bash
  # Check if file exists in container
  docker-compose exec nginx ls -la /usr/share/nginx/html/maintenance.html
  ```
- Error interception disabled
  ```bash
  # Check NGINX config
  docker-compose exec nginx nginx -T | grep proxy_intercept_errors
  ```
- Wrong error codes configured
  ```bash
  # Test specific error page
  curl -H "Host: wielandtech.com" http://localhost/maintenance
  ```

### Debug Commands

```bash
# Check NGINX configuration
docker-compose exec nginx nginx -T

# Test upstream connectivity
curl -I http://YOUR_HOMELAB_IP:80

# Monitor real-time logs
docker-compose logs -f

# Check container resources
docker stats

# Test DNS resolution
nslookup wielandtech.com

# Check port connectivity
telnet YOUR_HOMELAB_IP 80
telnet YOUR_HOMELAB_IP 443
```

### Performance Tuning

#### NGINX Optimization

Edit `nginx/nginx.conf` for high-traffic sites:

```nginx
# Increase worker processes
worker_processes auto;

# Optimize connections
events {
    worker_connections 2048;
    use epoll;
    multi_accept on;
}

# Increase buffer sizes
client_body_buffer_size 256k;
proxy_buffers 16 4k;
proxy_buffer_size 8k;
```

#### Resource Monitoring

```bash
# Monitor resource usage
./health-check.sh check

# Check system resources
htop
df -h
free -h

# Monitor network connections
netstat -tulpn | grep :80
netstat -tulpn | grep :443
```

## 🔄 Updates and Changes

### Updating NGINX Configuration

When making configuration changes:

```bash
# Edit configuration files
nano nginx/default.conf.template  # or other config files

# Test configuration
docker-compose exec nginx nginx -t

# Restart to apply changes
docker-compose restart nginx

# Verify changes
./health-check.sh check
```

### Updating Environment Variables

```bash
# Edit .env file
nano .env

# Recreate containers with new environment
docker-compose down
docker-compose up -d

# Verify connectivity
./health-check.sh check
```

## 📝 Maintenance Tasks

### Regular Tasks

- **Monitor health**: Run `./health-check.sh check` regularly
- **Review logs**: Check for anomalies or attack patterns
- **Update images**: Update Docker images monthly
- **Certificate monitoring**: cert-manager handles renewal automatically
- **Homelab connectivity**: Ensure port forwarding is stable

### Automated Monitoring (Optional)

Set up a cron job for regular health checks:

```bash
# Add to crontab (every 5 minutes)
crontab -e
```

Add this line:
```bash
*/5 * * * * /path/to/w_nginx_proxy/health-check.sh check >> /var/log/nginx-proxy-health.log 2>&1
```

### Updates

```bash
# Update NGINX image
docker-compose pull nginx
docker-compose up -d

# Update configuration
nano nginx/default.conf.template  # Edit as needed
docker-compose exec nginx nginx -t
docker-compose restart nginx
```

### Log Rotation

Set up logrotate to manage log files:

```bash
# Create logrotate config
sudo nano /etc/logrotate.d/nginx-proxy
```

Add:
```
/path/to/w_nginx_proxy/logs/nginx/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    missingok
    sharedscripts
    postrotate
        docker-compose -f /path/to/w_nginx_proxy/docker-compose.yml exec nginx nginx -s reload
    endscript
}
```

## 🔗 Related Documentation

- [Homelab Repository](https://github.com/wielandtech/w_homelab) - Kubernetes cluster configuration
- [Website Repository](https://github.com/wielandtech/w_tech) - Django application source
- [NGINX Documentation](https://nginx.org/en/docs/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)

## 📞 Support

For issues or questions:

1. Check the troubleshooting section above
2. Review logs: `./health-check.sh logs`
3. Test connectivity: `./health-check.sh check`
4. Check homelab Traefik status
5. Verify network configuration

## 🎯 Production Checklist

Ensure everything is properly configured:

- [x] VPS deployed with NGINX reverse proxy
- [x] DNS pointing to VPS IP (159.89.246.9)
- [x] HTTPS working with Let's Encrypt certificates
- [x] TLS termination in homelab cluster (Traefik + cert-manager)
- [x] ACME challenges forwarding correctly
- [ ] Health check cron job configured
- [ ] Log rotation set up
- [ ] Monitoring/alerting configured (optional)
- [ ] Backup strategy for configuration files

## 📈 Monitoring and Alerts

Consider setting up:

1. **Uptime Monitoring**: Use services like UptimeRobot or Healthchecks.io
2. **Log Aggregation**: Forward logs to a centralized logging system
3. **Alert Notifications**: Configure alerts for:
   - Container downtime
   - High error rates
   - Certificate expiration (backup to cert-manager)
   - Connectivity issues with homelab

## 🔐 Security Best Practices

Current security measures:

- ✅ Rate limiting enabled (30 req/s general, 10 req/s API)
- ✅ Security headers configured
- ✅ Hidden server information
- ✅ End-to-end encryption (TLS passthrough)
- ✅ Automatic certificate renewal
- ✅ Sensitive file access blocked

**Additional recommendations:**

1. **Firewall**: Ensure only ports 80 and 443 are open
2. **SSH Hardening**: Use key-based auth, disable root login
3. **Fail2ban**: Consider installing for brute-force protection
4. **Updates**: Keep VPS OS and Docker up to date
5. **Backups**: Regularly backup this configuration directory
