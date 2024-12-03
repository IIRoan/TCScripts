#!/bin/bash
# Configuration
TEAMCITY_SERVER_PATH="/Applications/TeamCity/bin"
BUILDAGENT_PATH="~/Downloads/buildAgentFull/bin"
SERVER_WAIT_TIME=20
AGENT_WAIT_TIME=10
TUNNEL_WAIT_TIME=5
MAX_WAIT_TIME=300  # Maximum time to wait for all services (5 minutes)

check_service() {
    case $1 in
        "server")
            lsof -i :8111 > /dev/null 2>&1
            ;;
        "agent")
            pgrep -f "teamcity-agent" > /dev/null 2>&1
            ;;
        "tunnel")
            pgrep -f "cloudflared tunnel" > /dev/null 2>&1
            ;;
    esac
    return $?
}

check_all_services() {
    for service in "server" "agent" "tunnel"; do
        check_service $service || return 1
    done
    return 0
}

display_status() {
    local service=$1
    local remaining=$2
    
    # Move cursor up 3 lines and clear subsequent lines
    printf "\033[3A\033[J"
    
    if check_service "server"; then
        printf "[✓] TeamCity server is running"
        [ "$service" = "server" ] && printf " (%ds remaining)" "$remaining"
        printf "\n"
    else
        printf "[x] TeamCity server is not running"
        [ "$service" = "server" ] && printf " (%ds remaining)" "$remaining"
        printf "\n"
    fi

    if check_service "agent"; then
        printf "[✓] Build agent is running"
        [ "$service" = "agent" ] && printf " (%ds remaining)" "$remaining"
        printf "\n"
    else
        printf "[x] Build agent is not running"
        [ "$service" = "agent" ] && printf " (%ds remaining)" "$remaining"
        printf "\n"
    fi

    if check_service "tunnel"; then
        printf "[✓] Cloudflare tunnel is running"
        [ "$service" = "tunnel" ] && printf " (%ds remaining)" "$remaining"
        printf "\n"
    else
        printf "[x] Cloudflare tunnel is not running"
        [ "$service" = "tunnel" ] && printf " (%ds remaining)" "$remaining"
        printf "\n"
    fi
}

start_service() {
    local service=$1
    local wait_time=$2
    local command=$3
    
    screen -dmS $service bash -c "$command"
    
    local start_time=$SECONDS
    while (( SECONDS - start_time < wait_time )); do
        display_status "$service" "$((wait_time - (SECONDS - start_time)))"
        sleep 1
    done
}

wait_for_completion() {
    local start_time=$SECONDS
    local elapsed=0
    
    while (( elapsed < MAX_WAIT_TIME )); do
        if check_all_services; then
            printf "\nAll services are up and running!\n"
            return 0
        fi
        
        printf "\rChecking services... (%ds elapsed)" "$elapsed"
        sleep 2
        elapsed=$((SECONDS - start_time))
    done
    
    printf "\nTimeout waiting for services to start!\n"
    return 1
}

main() {
    clear
    printf "%s\n" "===========================================" \
                  " TeamCity Services Startup Script" \
                  "===========================================" ""
    
    printf "Starting services...\n\n"
    # Print initial status placeholders
    printf "Checking service status...\n"
    printf "Checking service status...\n"
    printf "Checking service status...\n"
    
    # Start services
    start_service "teamcity" $SERVER_WAIT_TIME "cd $TEAMCITY_SERVER_PATH && ./teamcity-server.sh run"
    start_service "buildagent" $AGENT_WAIT_TIME "cd $BUILDAGENT_PATH && ./agent.sh run"
    start_service "cloudflared" $TUNNEL_WAIT_TIME "cloudflared tunnel run teamcity"
    
    # Wait for all services to be ready
    if wait_for_completion; then
        # Show running sessions and help
        echo -e "\nRunning screen sessions:"
        screen -ls
        printf "\n%s\n" "----------------------------------------" \
                        "To view services:" \
                        " screen -r teamcity   TeamCity server" \
                        " screen -r buildagent Build agent" \
                        " screen -r cloudflared Cloudflare tunnel" \
                        "----------------------------------------" \
                        "To detach from a screen: Ctrl+A then D" \
                        "========================================="
        exit 0
    else
        echo "Some services failed to start. Please check the logs."
        exit 1
    fi
}

main "$@"'