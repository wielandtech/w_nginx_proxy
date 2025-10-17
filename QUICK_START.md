# Quick Start Guide

## Summary

Your w_nginx_proxy has been configured for **TLS termination in your homelab cluster**. This means:
- ✅ NGINX forwards ACME challenges to homelab for Let's Encrypt
- ✅ NGINX passes encrypted HTTPS traffic directly to homelab (TCP passthrough)
- ✅ cert-manager in your cluster manages certificates
- ✅ Private keys never leave your homelab

## What's Been Updated

### w_nginx_proxy Changes
1. **nginx/nginx.conf** - Added stream module for HTTPS passthrough
2. **nginx/default.conf.template** - Simplified to handle ACME challenges and redirects
3. **nginx/stream.d/https-passthrough.conf.template** - New file for TCP passthrough
4. **docker-compose.yml** - Updated to mount stream configuration
5. **README.md** - Updated architecture documentation
6. **DEPLOYMENT_GUIDE.md** - Complete deployment walkthrough (NEW)
7. **VPS_SETUP_TLS_IN_CLUSTER.md** - Detailed VPS setup guide (NEW)

### w_homelab Changes
1. **cert-manager/clusterissuer.yaml** - Let's Encrypt issuer (NEW) ✅ Email updated
2. **cert-manager/kustomization.yaml** - Added ClusterIssuer resource
3. **website-helmrelease.yaml** - Added cert-manager annotations and TLS config

## Deployment Steps

### 1. Deploy Homelab (Do This First!)

```bash
cd w_homelab

# Commit changes
git add clusters/prod/infrastructure/cert-manager/
git add clusters/prod/apps/website/website-helmrelease.yaml
git commit -m "feat: Add cert-manager ClusterIssuer and configure website TLS"
git push origin main

# Monitor deployment
flux get all -A | grep -E "cert-manager|website"
kubectl get certificate -n website -w
```

**Wait for:**
- ClusterIssuer to be created
- Certificate to be ready (will happen after DNS points to VPS)

### 2. Configure VPS

```bash
cd w_nginx_proxy

# Create .env file
cp env.template .env

# Edit with your homelab WAN IP
nano .env
```

Update `.env`:
```env
HOMELAB_IP=YOUR_HOMELAB_WAN_IP_OR_DDNS
DOMAIN=wielandtech.com
```

### 3. Deploy to VPS

**Upload to VPS:**
```bash
# From your local machine
rsync -av --exclude='.git' w_nginx_proxy/ user@YOUR_VPS_IP:~/nginx-proxy/
```

**Deploy on VPS:**
```bash
# SSH to VPS
ssh user@YOUR_VPS_IP

# Navigate and deploy
cd ~/nginx-proxy
chmod +x deploy.sh
./deploy.sh

# Check status
docker compose ps
docker compose logs -f
```

### 4. Update DNS

Point your domain to VPS IP:
```
A    wielandtech.com      → YOUR_VPS_IP
A    www.wielandtech.com  → YOUR_VPS_IP
```

### 5. Wait for Certificate

After DNS propagates (5-15 minutes):

```bash
# Watch certificate creation
kubectl get certificate -n website -w

# Should go from "False" to "True" in 1-2 minutes
```

### 6. Test

```bash
# Test HTTP redirect
curl -I http://wielandtech.com

# Test HTTPS
curl -I https://wielandtech.com

# Visit in browser
# https://wielandtech.com
```

## Troubleshooting Quick Reference

### Certificate Stuck in "False" State

```bash
# Check challenges
kubectl get challenges -n website
kubectl describe challenge <name> -n website

# Check if ACME path is reachable
curl -v http://wielandtech.com/.well-known/acme-challenge/test

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --tail=50
```

### VPS Can't Reach Homelab

```bash
# Test from VPS
curl -I http://YOUR_HOMELAB_IP:80
curl -Ik https://YOUR_HOMELAB_IP:443

# Check VPS logs
docker compose logs nginx | grep -i error
```

### 404 Errors

```bash
# Check homelab ingress
kubectl get ingress -n website
kubectl describe ingress website -n website

# Test service directly
kubectl run test --image=curlimages/curl --rm -i --restart=Never -- \
  curl -H "Host: wielandtech.com" http://website.website.svc.cluster.local:8000/
```

## Important URLs

- **VPS Health**: http://YOUR_VPS_IP/nginx-health
- **Website**: https://wielandtech.com
- **VPS Logs**: `docker compose logs -f`
- **Homelab Logs**: `kubectl logs -n traefik daemonset/traefik`

## Reference Documents

- `DEPLOYMENT_GUIDE.md` - Complete step-by-step deployment
- `VPS_SETUP_TLS_IN_CLUSTER.md` - Detailed VPS configuration
- `README.md` - Architecture overview
- `w_homelab/MIGRATION_GUIDE.md` - Homelab migration guide
- `w_homelab/REVERSE_PROXY_SETUP.md` - Reverse proxy concepts

## Key Commands

**Homelab:**
```bash
# Watch certificate
kubectl get certificate -n website -w

# Check ingress
kubectl get ingress -n website

# Check Traefik
kubectl logs -n traefik daemonset/traefik --tail=50
```

**VPS:**
```bash
# View logs
docker compose logs -f

# Restart NGINX
docker compose restart nginx

# Check config
docker exec nginx-reverse-proxy nginx -t
```

## Success Checklist

- [ ] Homelab changes committed and deployed
- [ ] ClusterIssuer created (`kubectl get clusterissuer`)
- [ ] VPS .env configured with HOMELAB_IP
- [ ] VPS deployed and running (`docker compose ps`)
- [ ] DNS updated to point to VPS
- [ ] DNS propagated (`dig wielandtech.com`)
- [ ] Certificate issued (`kubectl get certificate -n website`)
- [ ] HTTPS works (https://wielandtech.com)
- [ ] No certificate warnings in browser
- [ ] HTTP redirects to HTTPS

## Next Steps After Success

1. Set up monitoring
2. Configure backups for cert-manager secrets  
3. Add more services to your cluster
4. Set up automatic updates

Good luck! 🚀

