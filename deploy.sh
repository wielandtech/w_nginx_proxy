#!/bin/bash
# NGINX Reverse Proxy Deployment Script

set -e  # Exit on error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="nginx-reverse-proxy"
ENV_FILE="$SCRIPT_DIR/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if .env file exists
    if [[ ! -f "$ENV_FILE" ]]; then
        error ".env file not found. Please copy env.template to .env and configure it."
        echo "Run: cp env.template .env"
        echo "Then edit .env with your homelab IP and other settings."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Validate configuration
validate_config() {
    log "Validating NGINX configuration..."
    
    # Test NGINX configuration syntax
    if docker run --rm -v "$SCRIPT_DIR/nginx:/etc/nginx:ro" nginx:alpine nginx -t; then
        success "NGINX configuration is valid"
    else
        error "NGINX configuration has errors. Please fix them before deploying."
        exit 1
    fi
}

# Create necessary directories
setup_directories() {
    log "Setting up directories..."
    
    mkdir -p "$SCRIPT_DIR/logs"
    chmod 755 "$SCRIPT_DIR/logs"
    
    success "Directories created"
}

# Process configuration templates
process_templates() {
    log "Processing configuration templates..."
    
    # Source environment variables
    source "$ENV_FILE"
    
    # Check required variables
    if [[ -z "$HOMELAB_IP" ]]; then
        error "HOMELAB_IP is not set in .env file"
        exit 1
    fi
    
    # Replace variables in configuration files
    for conf_file in nginx/upstream.conf nginx/stream.conf; do
        if [[ -f "$SCRIPT_DIR/$conf_file" ]]; then
            sed -i.bak "s/\${HOMELAB_IP}/$HOMELAB_IP/g" "$SCRIPT_DIR/$conf_file"
            log "Processed $conf_file"
        fi
    done
    
    success "Configuration templates processed"
}

# Deploy the stack
deploy_stack() {
    log "Deploying NGINX reverse proxy stack..."
    
    cd "$SCRIPT_DIR"
    
    # Pull latest images
    docker-compose pull
    
    # Stop existing containers
    docker-compose down --remove-orphans
    
    # Start the stack
    docker-compose up -d
    
    success "Stack deployed successfully"
}

# Wait for services to be healthy
wait_for_health() {
    log "Waiting for services to become healthy..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if docker-compose ps | grep -q "healthy\|Up"; then
            success "Services are healthy"
            return 0
        fi
        
        log "Attempt $attempt/$max_attempts - waiting for services..."
        sleep 10
        ((attempt++))
    done
    
    error "Services did not become healthy within expected time"
    docker-compose logs
    exit 1
}

# Test the deployment
test_deployment() {
    log "Testing deployment..."
    
    # Test health endpoint
    if curl -f -s http://localhost/nginx-health > /dev/null; then
        success "Health endpoint is responding"
    else
        warning "Health endpoint is not responding (this may be normal if using HTTPS redirect)"
    fi
    
    # Show container status
    log "Container status:"
    docker-compose ps
    
    # Show recent logs
    log "Recent logs:"
    docker-compose logs --tail=20
}

# Restore configuration backups
restore_configs() {
    log "Restoring configuration backups..."
    
    for conf_file in nginx/upstream.conf nginx/stream.conf; do
        if [[ -f "$SCRIPT_DIR/$conf_file.bak" ]]; then
            mv "$SCRIPT_DIR/$conf_file.bak" "$SCRIPT_DIR/$conf_file"
            log "Restored $conf_file"
        fi
    done
}

# Cleanup function
cleanup() {
    log "Cleaning up..."
    restore_configs
}

# Set trap for cleanup
trap cleanup EXIT

# Main deployment process
main() {
    log "Starting NGINX reverse proxy deployment..."
    
    check_prerequisites
    setup_directories
    process_templates
    validate_config
    deploy_stack
    wait_for_health
    test_deployment
    
    success "Deployment completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Test HTTP access: curl -H 'Host: wielandtech.com' http://your-vps-ip/"
    echo "2. Test HTTPS access: curl -H 'Host: wielandtech.com' https://your-vps-ip/ -k"
    echo "3. Update DNS to point wielandtech.com to this VPS IP"
    echo "4. Monitor logs: docker-compose logs -f"
}

# Run main function
main "$@"
