# Complete Deployment Guide - TLS in Homelab Cluster

This guide walks through deploying the complete setup with TLS termination in your homelab Kubernetes cluster.

## Overview

You're setting up:
1. **Homelab**: Kubernetes cluster with Traefik, cert-manager, and your website
2. **VPS**: NGINX reverse proxy that forwards traffic to homelab

## Phase 1: Deploy Homelab Configuration

### Step 1: Review Homelab Changes

Changes made to `w_homelab`:
- ✅ Created cert-manager ClusterIssuer for Let's Encrypt
- ✅ Updated website ingress with cert-manager annotations
- ✅ Configured TLS with cert-manager

### Step 2: Commit and Deploy Homelab

```bash
# Navigate to homelab repo
cd w_homelab

# Check changes
git status
git diff

# Commit changes
git add clusters/prod/infrastructure/cert-manager/
git add clusters/prod/apps/website/website-helmrelease.yaml
git commit -m "feat: Add cert-manager ClusterIssuer and configure website TLS"

# Push to trigger Flux deployment
git push origin main
```

### Step 3: Monitor Homelab Deployment

```bash
# Watch Flux reconciliation
flux get all -A | grep -E "cert-manager|website"

# Check ClusterIssuer created
kubectl get clusterissuer
# Should show: letsencrypt-prod

# Watch for certificate creation (takes 1-2 minutes)
kubectl get certificate -n website -w

# Check certificate status
kubectl describe certificate wielandtech-com-tls -n website

# Check pods are running
kubectl get pods -n website

# Check ingress is configured
kubectl get ingress -n website
```

### Step 4: Verify Homelab is Ready

```bash
# Test internal access
curl -H "Host: wielandtech.k8s.local" http://192.168.70.240/

# Check Traefik logs
kubectl logs -n traefik daemonset/traefik --tail=50
```

## Phase 2: Configure Router Port Forwarding

Ensure your router forwards traffic to Traefik:

```
WAN Port 80  → 192.168.70.240:80  (Traefik LoadBalancer)
WAN Port 443 → 192.168.70.240:443 (Traefik LoadBalancer)
```

Test from external network:
```bash
# Get your WAN IP
curl ifconfig.me

# Test from phone/external device (not on home network)
curl -I http://YOUR_WAN_IP
curl -Ik https://YOUR_WAN_IP
```

## Phase 3: Deploy VPS Configuration

### Step 1: Prepare VPS Environment

```bash
# SSH into your VPS
ssh user@YOUR_VPS_IP

# Install Docker if not already installed
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install docker-compose-plugin -y

# Verify installation
docker --version
docker compose version
```

### Step 2: Upload Configuration to VPS

From your local machine:

```bash
# Navigate to nginx-proxy directory
cd w_nginx_proxy

# Create .env file
cp env.template .env

# Edit .env with your settings
nano .env
```

Update `.env`:
```bash
# Your homelab WAN IP or DDNS hostname
HOMELAB_IP=YOUR_WAN_IP_OR_DDNS_HOSTNAME

# Domain (should already be correct)
DOMAIN=wielandtech.com
```

Upload to VPS:
```bash
# Upload entire directory to VPS
rsync -av --exclude='.git' \
  w_nginx_proxy/ \
  user@YOUR_VPS_IP:~/nginx-proxy/

# Or use SCP
scp -r w_nginx_proxy user@YOUR_VPS_IP:~/
```

### Step 3: Deploy on VPS

```bash
# SSH into VPS
ssh user@YOUR_VPS_IP

# Navigate to nginx-proxy directory
cd ~/nginx-proxy

# Make scripts executable
chmod +x deploy.sh health-check.sh

# Deploy
./deploy.sh

# Check status
docker compose ps

# View logs
docker compose logs -f
```

### Step 4: Test VPS Configuration

```bash
# Test health endpoint
curl http://localhost/nginx-health

# Test ACME challenge forwarding
curl -I http://localhost/.well-known/acme-challenge/test

# Check NGINX config is valid
docker exec nginx-reverse-proxy nginx -t

# View logs
docker compose logs nginx

# Check for errors
docker compose logs nginx | grep -i error
```

## Phase 4: DNS Configuration

### Update DNS Records

Point your domain to the VPS:

```
A    wielandtech.com      → YOUR_VPS_IP
A    www.wielandtech.com  → YOUR_VPS_IP
```

Wait for DNS propagation (can take up to 48 hours, usually ~5-15 minutes):

```bash
# Check DNS propagation
dig wielandtech.com
dig www.wielandtech.com

# Check from multiple locations
# https://www.whatsmydns.net/#A/wielandtech.com
```

## Phase 5: Certificate Issuance

Once DNS points to VPS and VPS is forwarding to homelab:

### Step 1: Trigger Certificate Request

The certificate should be requested automatically when the ingress is created. If not:

```bash
# Check certificate status
kubectl get certificate -n website

# If status is "False" or stuck, check events
kubectl describe certificate wielandtech-com-tls -n website

# Check challenges
kubectl get challenges -n website

# Check challenge details
kubectl describe challenge <challenge-name> -n website
```

### Step 2: Monitor Certificate Issuance

```bash
# Watch certificate (will take 1-2 minutes)
kubectl get certificate -n website -w

# Expected progression:
# NAME                   READY   SECRET                 AGE
# wielandtech-com-tls   False   wielandtech-com-tls   10s
# wielandtech-com-tls   True    wielandtech-com-tls   90s

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --tail=100
```

### Step 3: Verify Certificate

```bash
# Check certificate details
kubectl get certificate wielandtech-com-tls -n website -o yaml

# Check secret was created
kubectl get secret wielandtech-com-tls -n website

# Test HTTPS access
curl -I https://wielandtech.com

# Check certificate in browser
# Visit: https://wielandtech.com
# Click padlock icon → Certificate details
# Should show: Let's Encrypt certificate
```

## Phase 6: Final Testing

### Test All Traffic Paths

```bash
# 1. HTTP redirect
curl -I http://wielandtech.com
# Should return: 301 redirect to https://wielandtech.com

# 2. www redirect  
curl -I http://www.wielandtech.com
# Should return: 301 redirect to https://wielandtech.com

# 3. HTTPS access
curl -I https://wielandtech.com
# Should return: 200 OK

# 4. Full page load
curl https://wielandtech.com | head -50

# 5. ACME challenge path (for testing)
curl -I http://wielandtech.com/.well-known/acme-challenge/test
# Should forward to homelab (might return 404, but that's ok)
```

### Test from Multiple Locations

- ✅ Desktop browser
- ✅ Mobile browser (not on home WiFi)
- ✅ Another computer/device
- ✅ Mobile data (not WiFi)

### Check Logs

**On VPS:**
```bash
# Check VPS nginx logs
docker compose logs nginx --tail=100

# Check for errors
docker compose logs nginx | grep -i error

# Check ACME challenge logs
docker exec nginx-reverse-proxy cat /var/log/nginx/acme_challenge.log

# Check stream logs (HTTPS passthrough)
docker exec nginx-reverse-proxy cat /var/log/nginx/stream_access.log
```

**On Homelab:**
```bash
# Check Traefik logs
kubectl logs -n traefik daemonset/traefik --tail=50

# Check website logs
kubectl logs -n website deployment/website --tail=50

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --tail=50
```

## Troubleshooting

### Certificate Not Issuing

**Symptoms:** Certificate stays in "False" state

**Checks:**
```bash
# 1. Check challenge status
kubectl get challenges -n website
kubectl describe challenge <challenge-name> -n website

# 2. Check if ACME challenge is reachable
curl -v http://wielandtech.com/.well-known/acme-challenge/test

# 3. Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --tail=100

# 4. Check DNS points to VPS
dig wielandtech.com

# 5. Check VPS can reach homelab
# On VPS:
curl -I http://YOUR_HOMELAB_IP:80
```

**Common Issues:**
- DNS not pointing to VPS yet (wait for propagation)
- Port forwarding not configured on router
- VPS can't reach homelab (check firewall, WAN IP)
- ACME challenges blocked by firewall

### 404 Errors

**If you see 404 from Traefik:**

```bash
# Check ingress is correct
kubectl get ingress website -n website -o yaml

# Check service exists
kubectl get svc website -n website

# Check pods are running
kubectl get pods -n website

# Test direct service access
kubectl run test --image=curlimages/curl --rm -i --restart=Never -- \
  curl -H "Host: wielandtech.com" http://website.website.svc.cluster.local:8000/
```

### HTTPS Not Working

**If HTTPS shows certificate errors:**

```bash
# Check certificate is ready
kubectl get certificate -n website

# Check secret exists
kubectl get secret wielandtech-com-tls -n website

# Check ingress TLS config
kubectl get ingress website -n website -o yaml | grep -A 5 tls

# Restart Traefik to reload certificates
kubectl rollout restart -n traefik daemonset/traefik
```

### VPS Can't Reach Homelab

**Test connectivity:**

```bash
# From VPS, test homelab
curl -I http://YOUR_HOMELAB_IP:80
curl -Ik https://YOUR_HOMELAB_IP:443

# Check if ports are filtered
telnet YOUR_HOMELAB_IP 80
telnet YOUR_HOMELAB_IP 443

# Check from external server (not VPS)
# If works externally but not from VPS, check VPS firewall
```

## Maintenance

### Certificate Renewal

cert-manager automatically renews certificates 30 days before expiry. No action needed!

Monitor renewal:
```bash
# Check certificate expiry
kubectl get certificate -n website -o yaml | grep -A 5 "notAfter"

# Watch renewal logs
kubectl logs -n cert-manager deployment/cert-manager --follow
```

### Update NGINX Configuration

```bash
# 1. Edit local files
cd w_nginx_proxy
nano nginx/default.conf.template

# 2. Upload to VPS
rsync -av nginx/ user@YOUR_VPS_IP:~/nginx-proxy/nginx/

# 3. Restart NGINX on VPS
ssh user@YOUR_VPS_IP "cd ~/nginx-proxy && docker compose restart nginx"

# 4. Check logs
ssh user@YOUR_VPS_IP "cd ~/nginx-proxy && docker compose logs nginx --tail=50"
```

### Monitor VPS

```bash
# Check container status
docker compose ps

# Check logs
docker compose logs --tail=100

# Check resource usage
docker stats nginx-reverse-proxy

# Check nginx process
docker exec nginx-reverse-proxy ps aux
```

## Security Checklist

- ✅ Firewall configured (UFW or iptables)
- ✅ SSH key authentication only (disable password auth)
- ✅ Fail2ban installed
- ✅ Automatic security updates enabled
- ✅ TLS 1.2+ only (configured in Traefik)
- ✅ Rate limiting enabled (configured in NGINX)
- ✅ Security headers set (configured in NGINX)

## Success Criteria

Your deployment is complete when:

- [x] Certificate shows "Ready: True" in cluster
- [x] https://wielandtech.com loads without warnings
- [x] Certificate is from Let's Encrypt
- [x] HTTP redirects to HTTPS
- [x] www redirects to non-www
- [x] Website loads correctly from external devices
- [x] No certificate errors in browser
- [x] Logs show no errors

## Next Steps

1. Set up monitoring (Prometheus/Grafana)
2. Configure alerting for certificate expiry
3. Add more services to your cluster
4. Set up backups for cert-manager secrets
5. Consider adding WAF rules to NGINX

## Support Resources

- **cert-manager docs**: https://cert-manager.io/docs/
- **Traefik docs**: https://doc.traefik.io/traefik/
- **Let's Encrypt**: https://letsencrypt.org/docs/
- **NGINX stream module**: https://nginx.org/en/docs/stream/ngx_stream_core_module.html

Congratulations! Your website is now live with automated TLS! 🎉

