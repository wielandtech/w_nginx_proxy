# Homelab Ingress Configuration Update

This document provides the exact configuration changes needed in your homelab to accept traffic from the NGINX reverse proxy.

## Required Changes

### 1. Update Website HelmRelease

Edit your website HelmRelease configuration to include the external domain:

**File**: `w_homelab/clusters/prod/apps/website/website-helmrelease.yaml`

```yaml
# Add or update the ingress section
ingress:
  main:
    enabled: true
    className: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
      traefik.ingress.kubernetes.io/router.middlewares: default-headers@kubernetescrd
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      # Keep existing local domain
      - host: wielandtech.k8s.local
        paths:
          - path: /
            pathType: Prefix
            service:
              name: website
              port: 8000
      # Add external domain
      - host: wielandtech.com
        paths:
          - path: /
            pathType: Prefix
            service:
              name: website
              port: 8000
      # Add www variant
      - host: www.wielandtech.com
        paths:
          - path: /
            pathType: Prefix
            service:
              name: website
              port: 8000
    tls:
      - secretName: wielandtech-local-tls
        hosts:
          - wielandtech.k8s.local
      - secretName: wielandtech-com-tls
        hosts:
          - wielandtech.com
          - www.wielandtech.com
```

### 2. Verify Traefik Configuration

Ensure your Traefik configuration can handle external domains and obtain certificates:

**Check Certificate Resolver**:
```yaml
# In your Traefik values or configuration
certificatesResolvers:
  letsencrypt-prod:
    acme:
      email: your-email@wielandtech.com
      storage: /data/acme.json
      httpChallenge:
        entryPoint: web
      # Alternative: DNS challenge for wildcard certs
      # dnsChallenge:
      #   provider: cloudflare
      #   resolvers:
      #     - "1.1.1.1:53"
      #     - "8.8.8.8:53"
```

### 3. Update Kustomization (if needed)

If you're using Kustomization files, ensure the updated HelmRelease is included:

**File**: `w_homelab/clusters/prod/apps/website/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - website-helmrelease.yaml
  - website-secrets-sealed.yaml  # Your sealed secrets
```

## Deployment Commands

After making the configuration changes:

```bash
# Navigate to your homelab repository
cd w_homelab

# Commit the changes
git add clusters/prod/apps/website/
git commit -m "feat(website): Add external domain support for reverse proxy"

# Push to trigger Flux deployment
git push origin main

# Monitor the deployment
flux get all -A | grep website
kubectl get pods -n website
kubectl get ingress -n website
```

## Verification Steps

### 1. Check Ingress Configuration

```bash
# Check if ingress is created with external domains
kubectl get ingress -n website -o yaml

# Verify ingress hosts
kubectl describe ingress -n website
```

### 2. Check Certificate Generation

```bash
# Check certificate requests
kubectl get certificaterequests -n website

# Check certificates
kubectl get certificates -n website

# Check certificate details
kubectl describe certificate wielandtech-com-tls -n website
```

### 3. Test Internal Access

```bash
# Test local domain (should still work)
curl -H "Host: wielandtech.k8s.local" http://192.168.70.240/

# Test external domain through Traefik
curl -H "Host: wielandtech.com" http://192.168.70.240/
curl -H "Host: wielandtech.com" https://192.168.70.240/ -k
```

## Troubleshooting

### Certificate Issues

If certificates aren't being generated:

```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate events
kubectl describe certificate wielandtech-com-tls -n website

# Manual certificate creation (if needed)
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wielandtech-com-tls
  namespace: website
spec:
  secretName: wielandtech-com-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - wielandtech.com
    - www.wielandtech.com
EOF
```

### Ingress Issues

If ingress isn't working:

```bash
# Check Traefik logs
kubectl logs -n traefik deployment/traefik

# Check ingress class
kubectl get ingressclass

# Verify Traefik service
kubectl get svc -n traefik
```

### DNS Resolution

Test DNS resolution from within the cluster:

```bash
# Test from a pod
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup wielandtech.com

# Check CoreDNS
kubectl logs -n kube-system deployment/coredns
```

## Expected Results

After successful configuration:

1. **Ingress Created**: External domains added to ingress
2. **Certificates Issued**: Let's Encrypt certificates for wielandtech.com
3. **Traffic Routing**: External traffic routed to website pods
4. **SSL Termination**: Traefik handles SSL for external domains

## Next Steps

Once homelab configuration is updated:

1. Deploy the NGINX reverse proxy on VPS
2. Test connectivity between VPS and homelab
3. Update DNS to point to VPS
4. Monitor certificate renewal and traffic flow

## Rollback Plan

If issues occur, you can quickly rollback:

```bash
# Remove external domains from ingress
git revert <commit-hash>
git push origin main

# Or manually edit and remove external hosts
kubectl edit ingress -n website
```
