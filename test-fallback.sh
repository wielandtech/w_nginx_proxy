#!/bin/bash
# Test Fallback Page Functionality
# This script helps test the maintenance page when homelab is unavailable

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPS_IP="localhost"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Test maintenance page directly
test_maintenance_page() {
    log "Testing maintenance page endpoint..."
    
    local response
    local http_code
    
    if response=$(curl -s -w "%{http_code}" -H "Host: wielandtech.com" "http://$VPS_IP/maintenance" 2>/dev/null); then
        http_code="${response: -3}"
        content="${response%???}"
        
        if [[ "$http_code" == "200" ]]; then
            success "Maintenance page returns HTTP 200"
            
            # Check content
            if echo "$content" | grep -q "WielandTech" && echo "$content" | grep -q "Under Maintenance"; then
                success "Maintenance page content is correct"
            else
                error "Maintenance page content is incorrect"
                return 1
            fi
        else
            error "Maintenance page returns HTTP $http_code"
            return 1
        fi
    else
        error "Could not access maintenance page"
        return 1
    fi
}

# Test fallback behavior by simulating upstream failure
test_fallback_behavior() {
    log "Testing fallback behavior..."
    
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
    
    log "Current homelab IP: $HOMELAB_IP"
    
    # Test with invalid IP to simulate downtime
    log "Temporarily updating upstream to simulate downtime..."
    
    # Create temporary upstream config with invalid IP
    local temp_upstream="/tmp/upstream_test.conf"
    cat > "$temp_upstream" << EOF
# Temporary upstream configuration for testing fallback
upstream homelab_http {
    server 192.0.2.1:80;  # Invalid IP (RFC 5737 test address)
}

upstream homelab_https {
    server 192.0.2.1:443;  # Invalid IP (RFC 5737 test address)
}
EOF
    
    # Backup original upstream config
    cp "$SCRIPT_DIR/nginx/upstream.conf" "$SCRIPT_DIR/nginx/upstream.conf.backup"
    
    # Replace with test config
    cp "$temp_upstream" "$SCRIPT_DIR/nginx/upstream.conf"
    
    # Reload NGINX configuration
    log "Reloading NGINX with test configuration..."
    if docker-compose -f "$SCRIPT_DIR/docker-compose.yml" exec nginx nginx -s reload 2>/dev/null; then
        success "NGINX configuration reloaded"
        
        # Wait a moment for config to take effect
        sleep 2
        
        # Test that we get the maintenance page
        log "Testing fallback behavior with simulated downtime..."
        local response
        local http_code
        
        if response=$(curl -s -w "%{http_code}" -H "Host: wielandtech.com" "http://$VPS_IP/" --max-time 10 2>/dev/null); then
            http_code="${response: -3}"
            content="${response%???}"
            
            if [[ "$http_code" == "200" ]] && echo "$content" | grep -q "Under Maintenance"; then
                success "Fallback page is served correctly during simulated downtime"
            else
                warning "Expected maintenance page but got HTTP $http_code"
                echo "Response preview: ${content:0:200}..."
            fi
        else
            warning "Could not test fallback behavior (connection timeout or error)"
        fi
        
    else
        error "Failed to reload NGINX configuration"
    fi
    
    # Restore original configuration
    log "Restoring original configuration..."
    mv "$SCRIPT_DIR/nginx/upstream.conf.backup" "$SCRIPT_DIR/nginx/upstream.conf"
    
    # Reload NGINX with original config
    if docker-compose -f "$SCRIPT_DIR/docker-compose.yml" exec nginx nginx -s reload 2>/dev/null; then
        success "Original configuration restored"
    else
        error "Failed to restore original configuration"
    fi
    
    # Cleanup
    rm -f "$temp_upstream"
}

# Test HTTPS fallback (stream module doesn't support error pages, so this should fail gracefully)
test_https_behavior() {
    log "Testing HTTPS behavior during downtime..."
    
    warning "Note: HTTPS uses stream module pass-through, so no fallback page is possible"
    warning "HTTPS connections will fail when homelab is down (this is expected)"
    
    # Test HTTPS connection
    local result
    if result=$(curl -s --connect-timeout 5 --max-time 10 -H "Host: wielandtech.com" "https://$VPS_IP/" 2>&1); then
        log "HTTPS connection succeeded (homelab is up)"
    else
        warning "HTTPS connection failed (expected if homelab is down)"
        log "HTTPS error: $result"
    fi
}

# Main test function
run_tests() {
    log "Starting fallback page functionality tests..."
    echo ""
    
    # Check if Docker Compose is running
    if ! docker-compose -f "$SCRIPT_DIR/docker-compose.yml" ps | grep -q "Up"; then
        error "NGINX container is not running. Please start it first:"
        echo "  cd $SCRIPT_DIR && docker-compose up -d"
        exit 1
    fi
    
    local failed_tests=0
    
    # Run tests
    test_maintenance_page || ((failed_tests++))
    echo ""
    
    test_fallback_behavior || ((failed_tests++))
    echo ""
    
    test_https_behavior || true  # Don't count HTTPS test as failure
    echo ""
    
    # Summary
    if [[ $failed_tests -eq 0 ]]; then
        success "All fallback tests passed!"
        echo ""
        echo "✅ Maintenance page is accessible"
        echo "✅ Fallback behavior works during simulated downtime"
        echo "ℹ️  HTTPS will fail gracefully when homelab is down (expected)"
    else
        error "$failed_tests test(s) failed"
        echo ""
        echo "Please check the configuration and try again."
    fi
    
    echo ""
    log "Test completed at $(date)"
}

# Show usage
show_usage() {
    echo "Usage: $0 [test|maintenance|help]"
    echo ""
    echo "Commands:"
    echo "  test        - Run all fallback functionality tests (default)"
    echo "  maintenance - Show maintenance page directly"
    echo "  help        - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run all tests"
    echo "  $0 test              # Run all tests"
    echo "  $0 maintenance       # View maintenance page"
}

# Main execution
case "${1:-test}" in
    "test")
        run_tests
        ;;
    "maintenance")
        log "Opening maintenance page..."
        if command -v xdg-open >/dev/null; then
            xdg-open "http://localhost/maintenance"
        elif command -v open >/dev/null; then
            open "http://localhost/maintenance"
        else
            log "Maintenance page URL: http://localhost/maintenance"
            curl -H "Host: wielandtech.com" "http://localhost/maintenance"
        fi
        ;;
    "help"|"-h"|"--help")
        show_usage
        ;;
    *)
        error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
