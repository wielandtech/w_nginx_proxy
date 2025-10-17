#!/bin/bash
# NGINX Reverse Proxy Health Check Script

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/health-check.log"
WEBSITE_URL="https://wielandtech.com"
VPS_IP="localhost"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${BLUE}$message${NC}"
    echo "$message" >> "$LOG_FILE"
}

error() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
    echo -e "${RED}$message${NC}" >&2
    echo "$message" >> "$LOG_FILE"
}

success() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1"
    echo -e "${GREEN}$message${NC}"
    echo "$message" >> "$LOG_FILE"
}

warning() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1"
    echo -e "${YELLOW}$message${NC}"
    echo "$message" >> "$LOG_FILE"
}

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Check Docker containers
check_containers() {
    log "Checking Docker containers..."
    
    cd "$SCRIPT_DIR"
    
    # Check if containers are running
    if docker-compose ps | grep -q "Up"; then
        success "NGINX container is running"
        return 0
    else
        error "NGINX container is not running"
        docker-compose ps
        return 1
    fi
}

# Check NGINX configuration
check_nginx_config() {
    log "Checking NGINX configuration..."
    
    if docker-compose exec -T nginx nginx -t 2>/dev/null; then
        success "NGINX configuration is valid"
        return 0
    else
        error "NGINX configuration has errors"
        return 1
    fi
}

# Check local health endpoint
check_local_health() {
    log "Checking local health endpoint..."
    
    local response
    local http_code
    
    # Test HTTP health endpoint
    if response=$(curl -s -w "%{http_code}" -H "Host: wielandtech.com" "http://$VPS_IP/nginx-health" 2>/dev/null); then
        http_code="${response: -3}"
        if [[ "$http_code" == "200" ]]; then
            success "Local health endpoint is responding (HTTP 200)"
            return 0
        else
            warning "Local health endpoint returned HTTP $http_code"
            return 1
        fi
    else
        error "Failed to connect to local health endpoint"
        return 1
    fi
}

# Check homelab connectivity
check_homelab_connectivity() {
    log "Checking homelab connectivity..."
    
    # Source environment variables
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        source "$SCRIPT_DIR/.env"
    else
        error ".env file not found"
        return 1
    fi
    
    if [[ -z "$HOMELAB_IP" ]]; then
        error "HOMELAB_IP not set in .env"
        return 1
    fi
    
    # Test HTTP connectivity to homelab
    if curl -s --connect-timeout 10 --max-time 30 "http://$HOMELAB_IP:80" > /dev/null 2>&1; then
        success "Homelab HTTP connectivity OK ($HOMELAB_IP:80)"
    else
        error "Cannot connect to homelab HTTP ($HOMELAB_IP:80)"
        return 1
    fi
    
    # Test HTTPS connectivity to homelab
    if curl -s --connect-timeout 10 --max-time 30 -k "https://$HOMELAB_IP:443" > /dev/null 2>&1; then
        success "Homelab HTTPS connectivity OK ($HOMELAB_IP:443)"
    else
        error "Cannot connect to homelab HTTPS ($HOMELAB_IP:443)"
        return 1
    fi
    
    return 0
}

# Check external website access (if DNS is already pointed to VPS)
check_external_access() {
    log "Checking external website access..."
    
    local response
    local http_code
    
    # Test HTTPS access to the actual domain
    if response=$(curl -s -w "%{http_code}" --connect-timeout 10 --max-time 30 "$WEBSITE_URL" 2>/dev/null); then
        http_code="${response: -3}"
        if [[ "$http_code" =~ ^[23] ]]; then
            success "External HTTPS access OK (HTTP $http_code)"
            return 0
        else
            warning "External HTTPS returned HTTP $http_code"
            return 1
        fi
    else
        warning "Cannot access external HTTPS (DNS may not be pointed to VPS yet)"
        return 1
    fi
}

# Check SSL certificate (if applicable)
check_ssl_certificate() {
    log "Checking SSL certificate..."
    
    # Only check if the domain resolves to this server
    local domain_ip
    if domain_ip=$(dig +short wielandtech.com 2>/dev/null); then
        if [[ -n "$domain_ip" ]]; then
            # Check certificate expiration
            local cert_info
            if cert_info=$(echo | openssl s_client -servername wielandtech.com -connect wielandtech.com:443 2>/dev/null | openssl x509 -noout -dates 2>/dev/null); then
                success "SSL certificate is accessible"
                log "Certificate info: $cert_info"
                return 0
            else
                warning "SSL certificate check failed (may be handled by Traefik)"
                return 1
            fi
        fi
    fi
    
    warning "Skipping SSL certificate check (domain not resolved or not pointing to VPS)"
    return 0
}

# Check fallback page functionality
check_fallback_page() {
    log "Checking fallback page functionality..."
    
    # Test maintenance page endpoint
    if curl -s -H "Host: wielandtech.com" "http://$VPS_IP/maintenance" | grep -q "Under Maintenance"; then
        success "Maintenance page is accessible"
    else
        warning "Maintenance page is not accessible"
        return 1
    fi
    
    # Test fallback page content
    local response
    if response=$(curl -s -H "Host: wielandtech.com" "http://$VPS_IP/maintenance"); then
        if echo "$response" | grep -q "WielandTech" && echo "$response" | grep -q "Under Maintenance"; then
            success "Fallback page content is correct"
        else
            warning "Fallback page content may be incorrect"
            return 1
        fi
    else
        error "Could not retrieve fallback page"
        return 1
    fi
    
    return 0
}

# Check resource usage
check_resources() {
    log "Checking resource usage..."
    
    # Check container resource usage
    local stats
    if stats=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | grep nginx-reverse-proxy); then
        success "Container resource usage: $stats"
    else
        warning "Could not get container resource usage"
    fi
    
    # Check disk usage
    local disk_usage
    if disk_usage=$(df -h "$SCRIPT_DIR" | tail -1 | awk '{print $5}'); then
        success "Disk usage: $disk_usage"
    fi
    
    return 0
}

# Generate health report
generate_report() {
    local overall_status="HEALTHY"
    local failed_checks=0
    
    log "=== NGINX Reverse Proxy Health Check Report ==="
    
    # Run all checks
    check_containers || ((failed_checks++))
    check_nginx_config || ((failed_checks++))
    check_local_health || ((failed_checks++))
    check_homelab_connectivity || ((failed_checks++))
    check_external_access || ((failed_checks++))
    check_fallback_page || true  # Don't count fallback check as critical
    check_ssl_certificate || true  # Don't count SSL check as critical
    check_resources || true  # Don't count resource check as critical
    
    # Determine overall status
    if [[ $failed_checks -eq 0 ]]; then
        overall_status="HEALTHY"
        success "=== Overall Status: $overall_status ==="
    elif [[ $failed_checks -le 2 ]]; then
        overall_status="WARNING"
        warning "=== Overall Status: $overall_status ($failed_checks issues) ==="
    else
        overall_status="CRITICAL"
        error "=== Overall Status: $overall_status ($failed_checks issues) ==="
    fi
    
    log "Health check completed at $(date)"
    echo ""
    
    return $failed_checks
}

# Show recent logs
show_recent_logs() {
    log "Recent NGINX logs:"
    cd "$SCRIPT_DIR"
    docker-compose logs --tail=10 2>/dev/null || true
}

# Main function
main() {
    case "${1:-check}" in
        "check")
            generate_report
            ;;
        "logs")
            show_recent_logs
            ;;
        "monitor")
            log "Starting continuous monitoring (Ctrl+C to stop)..."
            while true; do
                generate_report
                sleep 300  # Check every 5 minutes
            done
            ;;
        *)
            echo "Usage: $0 [check|logs|monitor]"
            echo "  check   - Run health checks once (default)"
            echo "  logs    - Show recent logs"
            echo "  monitor - Run continuous monitoring"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
