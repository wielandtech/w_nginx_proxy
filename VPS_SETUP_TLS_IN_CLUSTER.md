# VPS Setup for TLS Termination in Cluster

This guide shows how to configure your VPS to forward traffic to your homelab where TLS termination happens with Traefik and cert-manager.

## Architecture

```
Internet → VPS NGINX → Homelab Router → Traefik LoadBalancer → Website Pod
                         (Port Forward)    (TLS Termination)
```

- **HTTP (Port 80)**: Forwards ACME challenges to homelab, redirects everything else to HTTPS
- **HTTPS (Port 443)**: TCP/TLS passthrough - encrypted traffic goes directly to Traefik
- **TLS Certificates**: Managed by cert-manager in the cluster
- **Let's Encrypt**: Uses HTTP-01 challenge through the VPS

## Prerequisites

- VPS with NGINX installed
- Domain pointing to VPS IP
- Homelab with port forwarding configured:
  - Port 80 → 192.168.70.240:80 (Traefik)
  - Port 443 → 192.168.70.240:443 (Traefik)

## Step 1: Configure NGINX Stream Module

Check if stream module is enabled:

```bash
nginx -V 2>&1 | grep -o with-stream
```

If not enabled, install nginx-full:

```bash
sudo apt install nginx-full -y
```

## Step 2: Configure NGINX Main Config

Edit `/etc/nginx/nginx.conf` and add stream block at the end (outside http block):

```nginx
# At the end of /etc/nginx/nginx.conf, outside the http block
stream {
    upstream homelab_https {
        # Replace with your homelab WAN IP or DDNS hostname
        server YOUR_HOMELAB_IP:443;
    }
    
    # HTTPS passthrough - forwards encrypted traffic directly
    server {
        listen 443;
        listen [::]:443;
        proxy_pass homelab_https;
        
        # TCP proxy settings
        proxy_connect_timeout 5s;
        proxy_timeout 60s;
    }
}
```

## Step 3: Configure HTTP Site

Create `/etc/nginx/sites-available/wielandtech.com`:

```nginx
# HTTP server - handles ACME challenges and redirects to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name wielandtech.com www.wielandtech.com;
    
    # Allow ACME challenges to reach homelab for Let's Encrypt
    location /.well-known/acme-challenge/ {
        proxy_pass http://YOUR_HOMELAB_IP:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
    }
    
    # Redirect everything else to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}
```

## Step 4: Enable Site and Restart NGINX

```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/wielandtech.com /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Restart NGINX (required for stream changes)
sudo systemctl restart nginx

# Check status
sudo systemctl status nginx
```

## Step 5: Configure Firewall

```bash
# Allow HTTP and HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Check status
sudo ufw status
```

## Step 6: Deploy Homelab Configuration

The homelab configuration has been updated with:
- ClusterIssuer for Let's Encrypt
- Ingress with cert-manager annotations
- TLS configuration

Commit and push:

```bash
cd w_homelab
git add .
git commit -m "feat: Add cert-manager ClusterIssuer and configure website TLS"
git push origin main
```

Monitor deployment:

```bash
# Check Flux reconciliation
flux get all -A | grep -E "cert-manager|website"

# Check ClusterIssuer
kubectl get clusterissuer

# Check certificates
kubectl get certificate -n website

# Check certificate details
kubectl describe certificate wielandtech-com-tls -n website

# Watch certificate creation
kubectl get certificaterequest -n website -w
```

## Step 7: Test ACME Challenge

From your local machine or another server:

```bash
# Test HTTP access (should redirect to HTTPS)
curl -I http://wielandtech.com

# Test ACME challenge path (should reach homelab)
curl -I http://wielandtech.com/.well-known/acme-challenge/test

# Test HTTPS after certificate is issued
curl -I https://wielandtech.com
```

## Troubleshooting

### Certificate Not Issuing

Check cert-manager logs:
```bash
kubectl logs -n cert-manager deployment/cert-manager --tail=100
```

Check certificate status:
```bash
kubectl describe certificate wielandtech-com-tls -n website
kubectl get certificaterequest -n website
```

Check ACME challenge:
```bash
kubectl get challenges -n website
kubectl describe challenge <challenge-name> -n website
```

### ACME Challenge Failing

Test if VPS can reach homelab:
```bash
# From VPS
curl -v http://YOUR_HOMELAB_IP:80/.well-known/acme-challenge/test
```

Test if Let's Encrypt can reach your VPS:
```bash
# From external server
curl -v http://wielandtech.com/.well-known/acme-challenge/test
```

### NGINX Errors

Check NGINX logs:
```bash
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

Test configuration:
```bash
sudo nginx -t
```

### Port Forwarding Issues

Check from homelab:
```bash
# Test if ports are forwarded
curl -I http://localhost:80
curl -Ik https://localhost:443
```

From external network:
```bash
# Test WAN IP
curl -I http://YOUR_WAN_IP:80
curl -Ik https://YOUR_WAN_IP:443
```

## Timeline

Let's Encrypt certificate issuance typically takes:
1. Certificate request submitted: ~1 second
2. ACME challenge created: ~5 seconds
3. Challenge verification: ~30-60 seconds
4. Certificate issued: ~5 seconds

Total time: ~1-2 minutes

## Security Considerations

- TLS 1.2+ enforced by Traefik in homelab
- Certificates automatically renewed by cert-manager
- VPS doesn't have access to private keys (they stay in cluster)
- Rate limits on VPS NGINX still apply

## Benefits of This Approach

1. **Security**: Private keys never leave your homelab
2. **Automation**: cert-manager handles renewal automatically
3. **Simplicity**: VPS is just a dumb proxy
4. **Flexibility**: Easy to add more services
5. **Cost**: No need for VPS SSL certificates

## Next Steps

1. Monitor certificate creation (1-2 minutes)
2. Test website access via https://wielandtech.com
3. Verify certificate details in browser
4. Set up monitoring for certificate expiration

