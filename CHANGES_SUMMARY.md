# Changes Summary

## ✅ Completed Configuration

### Homelab (w_homelab) - ALREADY COMMITTED ✓
Your homelab repository has been updated and committed:

**Commits:**
- `fd21cca` - Updated email to raphael@wielandtech.com for Let's Encrypt ClusterIssuer
- `7ad8c45` - Added ClusterIssuer for Let's Encrypt with cert-manager

**Files Changed:**
- ✅ `clusters/prod/infrastructure/cert-manager/clusterissuer.yaml` (NEW)
- ✅ `clusters/prod/infrastructure/cert-manager/kustomization.yaml`
- ✅ `clusters/prod/apps/website/website-helmrelease.yaml`

**What This Does:**
- cert-manager can now request Let's Encrypt certificates
- Website ingress configured to use cert-manager for TLS
- Certificates will be automatically managed and renewed

### VPS (w_nginx_proxy) - READY TO COMMIT

**Modified Files:**
- `nginx/nginx.conf` - Added stream module for HTTPS passthrough
- `nginx/default.conf.template` - Simplified for ACME challenges & redirects
- `docker-compose.yml` - Updated volume mounts
- `README.md` - Updated architecture documentation

**New Files:**
- `nginx/stream.d/https-passthrough.conf.template` - HTTPS TCP passthrough config
- `DEPLOYMENT_GUIDE.md` - Complete deployment walkthrough
- `QUICK_START.md` - Quick reference guide
- `VPS_SETUP_TLS_IN_CLUSTER.md` - Detailed VPS setup
- `nginx-stream-passthrough.conf` - Reference configuration
- `nginx-tls-in-cluster.conf` - Alternative Layer 7 config

## 📋 Next Steps

### 1. Push Homelab Changes (If Not Done)

```bash
cd w_homelab
git push origin main
```

Wait for Flux to deploy (1-2 minutes):
```bash
flux get all -A | grep -E "cert-manager|website"
kubectl get clusterissuer
```

### 2. Commit VPS Changes

```bash
cd w_nginx_proxy
git add .
git commit -m "feat: Configure NGINX for TLS termination in homelab cluster"
git push origin main
```

### 3. Deploy to VPS

**Create .env file:**
```bash
cd w_nginx_proxy
cp env.template .env
nano .env
```

Update with your homelab WAN IP:
```env
HOMELAB_IP=YOUR_HOMELAB_WAN_IP_OR_DDNS
DOMAIN=wielandtech.com
```

**Upload to VPS:**
```bash
rsync -av --exclude='.git' w_nginx_proxy/ user@YOUR_VPS_IP:~/nginx-proxy/
```

**Deploy on VPS:**
```bash
ssh user@YOUR_VPS_IP
cd ~/nginx-proxy
chmod +x deploy.sh
./deploy.sh
```

### 4. Update DNS

Point domain to VPS:
```
A    wielandtech.com      → YOUR_VPS_IP
A    www.wielandtech.com  → YOUR_VPS_IP
```

### 5. Watch Certificate Creation

After DNS propagates (5-15 minutes):
```bash
kubectl get certificate -n website -w
```

Should go from `False` to `True` in 1-2 minutes.

### 6. Test

```bash
# HTTP → HTTPS redirect
curl -I http://wielandtech.com

# HTTPS access
curl -I https://wielandtech.com

# Visit in browser
open https://wielandtech.com
```

## 🎯 Architecture Summary

```
┌────────────┐
│  Internet  │
└─────┬──────┘
      │
      │ DNS: wielandtech.com → VPS_IP
      │
┌─────▼──────┐
│  VPS NGINX │
│            │
│  Port 80:  │ /.well-known/acme-challenge/ → Homelab
│            │ Everything else → 301 HTTPS
│            │
│  Port 443: │ TCP Passthrough (encrypted)
└─────┬──────┘
      │
      │ WAN
      │
┌─────▼──────────┐
│ Homelab Router │ Port Forward 80/443
└─────┬──────────┘
      │
      │ LAN
      │
┌─────▼────────────────┐
│ Traefik LoadBalancer │ 192.168.70.240
│  TLS Termination     │
│  cert-manager        │
└─────┬────────────────┘
      │
┌─────▼────────┐
│ Website Pod  │ :8000
│ Django App   │
└──────────────┘
```

## 🔑 Key Points

1. **TLS Certificates:** Managed by cert-manager in homelab cluster
2. **Private Keys:** Never leave your homelab (stay in Kubernetes secrets)
3. **ACME Challenges:** VPS forwards HTTP-01 challenges to homelab
4. **HTTPS Traffic:** Passes through VPS encrypted (TCP passthrough)
5. **Automatic Renewal:** cert-manager handles renewal 30 days before expiry

## 📚 Documentation

- **QUICK_START.md** - Quick reference for deployment
- **DEPLOYMENT_GUIDE.md** - Complete step-by-step guide
- **VPS_SETUP_TLS_IN_CLUSTER.md** - Detailed VPS configuration
- **README.md** - Architecture overview

## ⚠️ Important

Before deploying to VPS, ensure:
- [ ] Homelab is accessible from VPS (test with curl http://YOUR_HOMELAB_IP)
- [ ] Router port forwarding is configured (80/443 → 192.168.70.240)
- [ ] DNS nameservers have low TTL (for quick propagation)
- [ ] Firewall allows ports 80/443 on VPS

## 🆘 Troubleshooting

If you encounter issues, check:

1. **Certificate not issuing:** Check ACME challenges can reach homelab
2. **404 errors:** Verify ingress and service in homelab
3. **Connection refused:** Check VPS can reach homelab WAN IP
4. **DNS issues:** Verify DNS propagation with `dig wielandtech.com`

See `QUICK_START.md` for troubleshooting commands.

## ✅ Success Criteria

Your deployment is successful when:
- Certificate shows `Ready: True`
- https://wielandtech.com loads without warnings
- Certificate issuer is "Let's Encrypt"
- Browser shows padlock icon (secure connection)
- HTTP redirects to HTTPS
- www redirects to non-www

Good luck! 🚀

