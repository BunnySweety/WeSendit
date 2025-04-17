#!/bin/bash
# Script: WeSendit Node Port & Requirements Checker
# Description: Checks necessary network ports and system requirements
#              for a WeSendit node, including Docker container status.
# Author: BunnySweety
# Version: 2.3 (Added --test option)

# --- Default Configuration ---
MASTER_TCP_PORT=41631
STORAGE_TCP_PORT=41630

# --- Options & Flags ---
VERBOSE=false
LOG_FILE=""
INTERVAL=0
COLOR=true
CHECK_FIREWALL=true
CHECK_MASTER_INTERNET=true
CHECK_STORAGE_LOCAL=true
TEST_LATENCY=false
CHECK_REQUIREMENTS=true
OUTPUT_FORMAT="human" # human or json
SPECIFIC_TEST="" # Nom du test spécifique à lancer

# --- Requirement Thresholds ---
MIN_CPU_CORES=2; MIN_CPU_SPEED=1.5; MIN_STORAGE=10
MIN_BANDWIDTH_UP=10; MIN_BANDWIDTH_DOWN=10; MIN_UPTIME=95; MAX_PING=150
REC_CPU_CORES=2; REC_CPU_SPEED=1.5; REC_STORAGE=1024
REC_BANDWIDTH_UP=100; REC_BANDWIDTH_DOWN=100; REC_UPTIME=99; REC_PING=50

# --- Status Constants ---
STATUS_OPTIMAL="OPTIMAL"; STATUS_ADEQUATE="ADEQUATE"; STATUS_FAILED="FAILED"
STATUS_RUNNING="RUNNING"; STATUS_STOPPED="STOPPED"; STATUS_NOT_FOUND="NOT FOUND"
STATUS_WARNING="WARNING"; STATUS_OPEN="OPEN"; STATUS_CLOSED="CLOSED"
STATUS_UNKNOWN="UNKNOWN"; STATUS_SKIPPED="SKIPPED"; STATUS_OK="OK"

# --- Global Variables ---
declare -A RESULTS # Associative array to store all results

# --- Color Definitions ---
if [ "$COLOR" = true ]; then RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m';
else RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''; fi

# --- Initialize RESULTS array ---
# Done in main() after parsing args

# --- Utility Functions ---
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -m, --master PORT    Specify Master node port (default: ${MASTER_TCP_PORT})"
    echo "  -s, --storage PORT   Specify Storage node port (default: ${STORAGE_TCP_PORT})"
    echo "  -i, --interval SEC   Run test every SEC seconds"
    echo "  -l, --log FILE       Log results to FILE"
    echo "  -v, --verbose        Show verbose output"
    echo "  -q, --quiet          Minimal output (errors and summary)"
    echo "  --format FMT       Output format: human (default) or json"
    echo "  --no-color           Disable colored output"
    echo "  --no-master          Skip Master node internet check"
    echo "  --no-storage         Skip Storage node local check"
    echo "  --no-firewall        Skip firewall check"
    echo "  --latency            Test connection latency"
    echo "  --no-requirements    Skip system requirements check"
    echo "  -t, --test TEST      Run only a specific TEST (e.g., cpu, storage, bandwidth, docker, ping, master-port, storage-port, firewall)"
    echo "  -h, --help           Show this help"
    echo ""
    exit 1
}
check_root() { if [ "$EUID" -ne 0 ]; then log_result "${YELLOW}Warning: Recommend running with sudo for full functionality (Docker, Speedtest).${NC}"; sleep 1; fi; }
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -m|--master) MASTER_TCP_PORT="$2"; shift ;;
            -s|--storage) STORAGE_TCP_PORT="$2"; shift ;;
            -i|--interval) INTERVAL="$2"; shift ;;
            -l|--log) LOG_FILE="$2"; shift ;;
            -v|--verbose) VERBOSE=true ;;
            -q|--quiet) VERBOSE=false ;;
            --format) OUTPUT_FORMAT="$2"; shift ;;
            --no-color) COLOR=false ;;
            --no-master) CHECK_MASTER_INTERNET=false ;;
            --no-storage) CHECK_STORAGE_LOCAL=false ;;
            --no-firewall) CHECK_FIREWALL=false ;;
            --latency) TEST_LATENCY=true ;;
            --no-requirements) CHECK_REQUIREMENTS=false ;;
            -t|--test) SPECIFIC_TEST="$2"; shift ;;
            -h|--help) usage ;;
            *) echo "Unknown parameter: $1"; usage ;;
        esac
        shift
    done
    # --- Validation de l'option --test ---
    if [ -n "$SPECIFIC_TEST" ]; then
         case "$SPECIFIC_TEST" in
             cpu|storage|bandwidth|docker|ping|master-port|storage-port|firewall) ;; # Noms de tests valides
             *) echo "${RED}Error: Invalid test name specified: '$SPECIFIC_TEST'.${NC}" >&2;
                echo "Valid names are: cpu, storage, bandwidth, docker, ping, master-port, storage-port, firewall" >&2;
                exit 1 ;;
         esac
     fi
     # --- Fin de la validation ---
    if [[ "$OUTPUT_FORMAT" != "human" && "$OUTPUT_FORMAT" != "json" ]]; then echo "Error: Invalid output format '$OUTPUT_FORMAT'. Use 'human' or 'json'." >&2; exit 1; fi
    if [ "$COLOR" = false ]; then RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''; fi
}
log_msg() { local msg="$1"; local is_error=false; [[ "$msg" == "${RED}"* || "$msg" == "${YELLOW}"* ]] && is_error=true; if [ "$VERBOSE" = true ] || [ "$is_error" = true ]; then printf "%b\n" "$msg"; fi; if [ -n "$LOG_FILE" ]; then printf "%s\n" "$msg" | sed 's/\x1B\[[0-9;]*[JKmsu]//g' >> "$LOG_FILE"; fi; }
log_msg_n() { local msg="$1"; local is_error=false; [[ "$msg" == "${RED}"* || "$msg" == "${YELLOW}"* ]] && is_error=true; if [ "$VERBOSE" = true ] || [ "$is_error" = true ]; then printf "%b" "$msg"; fi; if [ -n "$LOG_FILE" ]; then printf "%s" "$msg" | sed 's/\x1B\[[0-9;]*[JKmsu]//g' >> "$LOG_FILE"; fi; }
log_hdr() { if [ "$VERBOSE" = true ]; then printf "%b\n" "$1"; fi; if [ -n "$LOG_FILE" ] && [ "$VERBOSE" = true ]; then printf "%s\n" "$1" | sed 's/\x1B\[[0-9;]*[JKmsu]//g' >> "$LOG_FILE"; fi; }
log_result() { printf "%b\n" "$1"; if [ -n "$LOG_FILE" ]; then printf "%s\n" "$1" | sed 's/\x1B\[[0-9;]*[JKmsu]//g' >> "$LOG_FILE"; fi; }

# Displays a spinner animation
show_spinner() {
    local pid=$1; local delay=0.1; local spinstr='|/-\'
    # Suppression de la condition VERBOSE=false pour toujours afficher le spinner
    # if [ "$VERBOSE" = false ]; then return; fi

    if [ "$COLOR" = true ]; then
        while ps -p $pid > /dev/null; do local temp=${spinstr#?}; printf " [%c]  " "$spinstr"; local spinstr=$temp${spinstr%"$temp"}; sleep $delay; printf "\b\b\b\b\b\b"; done
    else
        while ps -p $pid > /dev/null; do local temp=${spinstr#?}; printf " [%c]  " "$spinstr"; local spinstr=$temp${spinstr%"$temp"}; sleep $delay; printf "\b\b\b\b\b\b"; done
    fi
    printf "    \b\b\b\b"
}

# Checks for required and optional dependencies
check_dependencies() { log_hdr "${BLUE}Checking dependencies...${NC}"; local missing_count=0; require_command() { local cmd="$1" pkg_debian="$2" pkg_rhel="$3" reason="$4"; if ! command -v "$cmd" &> /dev/null; then log_result "${RED}Error: Required command '${cmd}' not found.${NC} ${reason}"; if [ -n "$pkg_debian" ]; then log_result "  Debian/Ubuntu: sudo apt-get update && sudo apt-get install -y ${pkg_debian}"; fi; if [ -n "$pkg_rhel" ]; then log_result "  CentOS/RHEL:   sudo yum install -y ${pkg_rhel}"; fi; ((missing_count++)); return 1; fi; return 0; }; check_optional_command() { local cmd="$1" reason="$2"; if ! command -v "$cmd" &> /dev/null; then log_msg "${YELLOW}Warning: Optional command '${cmd}' not found. ${reason}${NC}"; return 1; fi; return 0; }; require_command "curl" "curl" "curl" "(Needed for external checks)"; require_command "nc" "netcat" "nc" "(Needed for local port check)"; require_command "grep" "grep" "grep" "(Needed for text processing)"; require_command "timeout" "coreutils" "coreutils" "(Needed to prevent hangs)"; require_command "sed" "sed" "sed" "(Needed for text processing)"; require_command "awk" "gawk" "gawk" "(Needed for text processing)"; require_command "bc" "bc" "bc" "(Needed for calculations)"; require_command "lscpu" "util-linux" "util-linux" "(Needed for CPU info)"; require_command "docker" "docker.io" "docker-ce" "(Needed for WeSendit node check)"; require_command "jq" "jq" "jq" "(Needed for bandwidth test parsing and JSON output)"; check_optional_command "ping" "Ping tests will be skipped." || true; if [ "$CHECK_REQUIREMENTS" = true ]; then check_optional_command "speedtest" "Ookla speedtest recommended for accurate bandwidth tests." || true ; fi; if [ "$CHECK_FIREWALL" = true ]; then if ! command -v iptables &> /dev/null && ! command -v ufw &> /dev/null && ! command -v firewall-cmd &> /dev/null; then log_msg "${YELLOW}Warning: No supported firewall tool found. Firewall checks skipped.${NC}"; CHECK_FIREWALL=false; fi; fi; if [ "$missing_count" -gt 0 ]; then log_result "\n${RED}Please install missing critical dependencies and try again.${NC}"; exit 1; fi; log_hdr "${GREEN}Dependencies check passed.${NC}\n"; }

# --- Evaluation Functions ---
evaluate_status() { local current_val="$1" min_val="$2" rec_val="$3" lower_is_better="${4:-false}"; local status="$STATUS_FAILED"; if ! [[ "$current_val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then echo "$STATUS_FAILED"; return; fi; local min_met=false rec_met=false; if [ "$lower_is_better" = false ]; then if (( $(echo "$current_val >= $min_val" | bc -l 2>/dev/null) )); then min_met=true; fi; if (( $(echo "$current_val >= $rec_val" | bc -l 2>/dev/null) )); then rec_met=true; fi; else if (( $(echo "$current_val <= $min_val" | bc -l 2>/dev/null) )); then min_met=true; fi; if (( $(echo "$current_val <= $rec_val" | bc -l 2>/dev/null) )); then rec_met=true; fi; fi; if [ "$min_met" = true ]; then if [ "$rec_met" = true ]; then status="$STATUS_OPTIMAL"; else status="$STATUS_ADEQUATE"; fi; else status="$STATUS_FAILED"; fi; echo "$status"; }

# --- Specific Check Functions ---
check_cpu_requirements() { log_hdr "${BLUE}Checking CPU requirements...${NC}"; local lscpu_output cpu_model cpu_cores cpu_speed cpu_arch arch_status cores_ok speed_ok arch_ok status_text="$STATUS_FAILED" cores_status speed_status; lscpu_output=$(lscpu 2>/dev/null); local exit_code=$?; if [ $exit_code -ne 0 ] || [ -z "$lscpu_output" ]; then log_result "${RED}Error: Failed to execute lscpu command.${NC}"; RESULTS[cpu_status]="$STATUS_FAILED"; RESULTS[cpu_error]="lscpu_failed"; return 1; fi; cpu_model=$(printf "%s" "$lscpu_output" | grep "^Model name:" | sed 's/Model name:\s*//'); cpu_cores=$(printf "%s" "$lscpu_output" | grep "^CPU(s):" | awk '{print $2}'); cpu_speed=$(printf "%s" "$lscpu_output" | grep "CPU max MHz" | awk '{printf "%.1f", $4/1000}'); if [ -z "$cpu_speed" ] || [ "$cpu_speed" == "0.0" ]; then cpu_speed=$(printf "%s" "$lscpu_output" | grep "CPU MHz" | awk '{printf "%.1f", $3/1000}'); fi; if [ -z "$cpu_speed" ] || [ "$cpu_speed" == "0.0" ]; then cpu_speed=$(grep -m 1 "cpu MHz" /proc/cpuinfo | cut -d ':' -f 2 | sed 's/^[ \t]*//' | awk '{printf "%.1f", $1/1000}'); fi; cpu_arch=$(uname -m); arch_status="$STATUS_FAILED"; arch_ok=false; if [[ "$cpu_arch" == "x86_64" ]]; then arch_status="PASSED"; arch_ok=true; elif [[ "$cpu_arch" == "i686" || "$cpu_arch" == "i386" ]]; then arch_status="COMPATIBLE (Warning: 32-bit)"; arch_ok=true; fi; log_msg "CPU Model: ${cpu_model:-N/A}"; log_msg "CPU Cores: $cpu_cores (Minimum: $MIN_CPU_CORES, Recommended: $REC_CPU_CORES)"; log_msg "CPU Speed: ${cpu_speed:-N/A}GHz (Minimum: ${MIN_CPU_SPEED}GHz, Recommended: ${REC_CPU_SPEED}GHz)"; log_msg "CPU Architecture: $cpu_arch - ${arch_status}"; RESULTS[cpu_model]="${cpu_model:-N/A}"; RESULTS[cpu_cores]="$cpu_cores"; RESULTS[cpu_speed_ghz]="${cpu_speed:-N/A}"; RESULTS[cpu_arch]="$cpu_arch"; cores_status=$(evaluate_status "$cpu_cores" "$MIN_CPU_CORES" "$REC_CPU_CORES"); speed_status=$(evaluate_status "$cpu_speed" "$MIN_CPU_SPEED" "$REC_CPU_SPEED"); if [ "$cores_status" = "$STATUS_OPTIMAL" ]; then log_result "${GREEN}✅ CPU cores meet recommended specs${NC}"; elif [ "$cores_status" = "$STATUS_ADEQUATE" ]; then log_result "${YELLOW}⚠️ CPU cores meet minimum but not recommended specs${NC}"; else log_result "${RED}❌ CPU cores below minimum requirement${NC}"; fi; if [ "$speed_status" = "$STATUS_OPTIMAL" ]; then log_result "${GREEN}✅ CPU speed meets recommended specs${NC}"; elif [ "$speed_status" = "$STATUS_ADEQUATE" ]; then log_result "${YELLOW}⚠️ CPU speed meets minimum but not recommended specs${NC}"; else log_result "${RED}❌ CPU speed below minimum requirement${NC}"; fi; if [ "$arch_ok" = false ]; then log_result "${RED}❌ CPU architecture not compatible${NC}"; fi; if [ "$cores_status" = "$STATUS_FAILED" ] || [ "$speed_status" = "$STATUS_FAILED" ] || [ "$arch_ok" = false ]; then status_text="$STATUS_FAILED"; elif [ "$cores_status" = "$STATUS_ADEQUATE" ] || [ "$speed_status" = "$STATUS_ADEQUATE" ] || [[ "$cpu_arch" == "i686" || "$cpu_arch" == "i386" ]]; then status_text="$STATUS_ADEQUATE"; if [[ "$cpu_arch" == "i686" || "$cpu_arch" == "i386" ]]; then log_result "${YELLOW}⚠️ 32-bit architecture may have limitations.${NC}"; fi; else status_text="$STATUS_OPTIMAL"; fi; RESULTS[cpu_status]="$status_text"; log_hdr ""; }
check_storage_requirements() { log_hdr "${BLUE}Checking storage requirements...${NC}"; local avail_space status_text="$STATUS_FAILED" df_output; RESULTS[storage_status]="$STATUS_UNKNOWN"; RESULTS[storage_available_gb]="N/A"; df_output=$(df -BG / 2>/dev/null); local exit_code=$?; if [ $exit_code -ne 0 ]; then log_result "${RED}Error: Failed to execute df command.${NC}"; RESULTS[storage_status]="$STATUS_FAILED"; RESULTS[storage_error]="df_failed"; return 1; fi; avail_space=$(echo "$df_output" | awk 'NR==2 {print $4}' | sed 's/G//'); RESULTS[storage_available_gb]="${avail_space:-N/A}"; log_msg "Available Storage: ${avail_space:-N/A}GB (Minimum: ${MIN_STORAGE}GB, Recommended: ${REC_STORAGE}GB)"; status_text=$(evaluate_status "$avail_space" "$MIN_STORAGE" "$REC_STORAGE"); if [ "$status_text" = "$STATUS_OPTIMAL" ]; then log_result "${GREEN}✅ Available storage meets recommended specs${NC}"; elif [ "$status_text" = "$STATUS_ADEQUATE" ]; then log_result "${YELLOW}⚠️ Available storage meets minimum but not recommended specs${NC}"; else log_result "${RED}❌ Available storage below minimum requirement${NC}"; fi; RESULTS[storage_status]="$status_text"; log_hdr ""; }
check_bandwidth_requirements() { log_hdr "${BLUE}Checking bandwidth requirements...${NC}"; local speedtest_cmd speedtest_output download_speed upload_speed down_ok up_ok spinner_pid exit_code down_bw up_bw status_text="$STATUS_FAILED"; RESULTS[bandwidth_down_mbps]="N/A"; RESULTS[bandwidth_up_mbps]="N/A"; RESULTS[bandwidth_status]="$STATUS_UNKNOWN"; if ! command -v jq &> /dev/null; then log_result "${RED}Error: 'jq' not installed. Cannot parse bandwidth.${NC}"; RESULTS[bandwidth_status]="$STATUS_FAILED"; RESULTS[bandwidth_error]="jq_missing"; return 1; fi; if command -v speedtest &> /dev/null; then speedtest_cmd="speedtest --accept-license --accept-gdpr --progress=no --format=json"; log_msg "Using Ookla speedtest..."; else log_msg "${YELLOW}Ookla 'speedtest' not found. Skipping bandwidth test.${NC}"; RESULTS[bandwidth_status]="$STATUS_SKIPPED"; return; fi; log_msg_n "Running bandwidth test (this may take a moment)..."; show_spinner $$ & spinner_pid=$!; speedtest_output=$(timeout 120 $speedtest_cmd 2>&1); exit_code=$?; kill $spinner_pid >/dev/null 2>&1; wait $spinner_pid 2>/dev/null; printf "\r%*s\r" "$(tput cols)" "" ; if [ $exit_code -ne 0 ]; then if echo "$speedtest_output" | grep -q "type YES to accept"; then log_result "${RED}Speedtest license acceptance failed. Run script with sudo.${NC}"; RESULTS[bandwidth_error]="license_error"; else log_result "${RED}Speedtest command failed or timed out (Exit code: $exit_code).${NC}"; if [ "$VERBOSE" = true ]; then log_msg "Output: $speedtest_output"; fi; RESULTS[bandwidth_error]="speedtest_failed"; fi; RESULTS[bandwidth_status]="$STATUS_FAILED"; return 1; fi; download_speed="N/A"; upload_speed="N/A"; if printf "%s" "$speedtest_output" | jq empty 2>/dev/null; then down_bw=$(printf "%s" "$speedtest_output" | jq '.download.bandwidth // 0'); up_bw=$(printf "%s" "$speedtest_output" | jq '.upload.bandwidth // 0'); if [[ "$down_bw" =~ ^[0-9]+(\.[0-9]+)?$ && "$down_bw" != "0" ]]; then download_speed=$(echo "scale=2; $down_bw / 125000" | bc); else download_speed="0.00"; fi; if [[ "$up_bw" =~ ^[0-9]+(\.[0-9]+)?$ && "$up_bw" != "0" ]]; then upload_speed=$(echo "scale=2; $up_bw / 125000" | bc); else upload_speed="0.00"; fi; else log_result "${RED}Speedtest output was not valid JSON.${NC}"; if [ "$VERBOSE" = true ]; then log_msg "Output: $speedtest_output"; fi; RESULTS[bandwidth_error]="invalid_json"; RESULTS[bandwidth_status]="$STATUS_FAILED"; return 1; fi; RESULTS[bandwidth_down_mbps]="$download_speed"; RESULTS[bandwidth_up_mbps]="$upload_speed"; if [ "$download_speed" = "N/A" ] || [ "$upload_speed" = "N/A" ]; then log_result "${RED}Failed to parse speedtest results using jq.${NC}"; RESULTS[bandwidth_error]="jq_parse_failed"; RESULTS[bandwidth_status]="$STATUS_FAILED"; return 1; fi; log_msg "Download Speed: ${download_speed} Mbps (Min: ${MIN_BANDWIDTH_DOWN}, Rec: ${REC_BANDWIDTH_DOWN})"; log_msg "Upload Speed:   ${upload_speed} Mbps (Min: ${MIN_BANDWIDTH_UP}, Rec: ${REC_BANDWIDTH_UP})"; local down_status=$(evaluate_status "$download_speed" "$MIN_BANDWIDTH_DOWN" "$REC_BANDWIDTH_DOWN"); local up_status=$(evaluate_status "$upload_speed" "$MIN_BANDWIDTH_UP" "$REC_BANDWIDTH_UP"); if [ "$down_status" = "$STATUS_OPTIMAL" ]; then log_result "${GREEN}✅ Download speed meets recommended specs${NC}"; elif [ "$down_status" = "$STATUS_ADEQUATE" ]; then log_result "${YELLOW}⚠️ Download speed meets minimum but not recommended specs${NC}"; else log_result "${RED}❌ Download speed below minimum requirement${NC}"; fi; if [ "$up_status" = "$STATUS_OPTIMAL" ]; then log_result "${GREEN}✅ Upload speed meets recommended specs${NC}"; elif [ "$up_status" = "$STATUS_ADEQUATE" ]; then log_result "${YELLOW}⚠️ Upload speed meets minimum but not recommended specs${NC}"; else log_result "${RED}❌ Upload speed below minimum requirement${NC}"; fi; if [ "$down_status" = "$STATUS_FAILED" ] || [ "$up_status" = "$STATUS_FAILED" ]; then status_text="$STATUS_FAILED"; elif [ "$down_status" = "$STATUS_ADEQUATE" ] || [ "$up_status" = "$STATUS_ADEQUATE" ]; then status_text="$STATUS_ADEQUATE"; else status_text="$STATUS_OPTIMAL"; fi; RESULTS[bandwidth_status]="$status_text"; log_hdr ""; }
check_docker_wesendit_node() { log_hdr "${BLUE}Checking WeSendit Node Docker status...${NC}"; local container_status container_info container_id running_for restarts status_text="$STATUS_FAILED" container_name="wesendit-node"; RESULTS[docker_status]="$STATUS_UNKNOWN"; RESULTS[docker_running_for]="N/A"; RESULTS[docker_restarts]="N/A"; if ! command -v docker &> /dev/null; then log_result "${RED}Error: Docker command not found.${NC}"; RESULTS[docker_status]="$STATUS_FAILED"; RESULTS[docker_error]="docker_missing"; return 1; fi; container_id=$(docker ps -a --filter "name=^/${container_name}$" --format "{{.ID}}" --no-trunc | head -n 1); local exit_code=$?; if [ $exit_code -ne 0 ]; then log_result "${RED}Error running 'docker ps'. Check Docker daemon?${NC}"; RESULTS[docker_status]="$STATUS_FAILED"; RESULTS[docker_error]="docker_ps_failed"; return 1; fi; if [ -z "$container_id" ]; then log_result "${RED}❌ WeSendit Node container '${container_name}' NOT FOUND${NC}"; RESULTS[docker_status]="$STATUS_NOT_FOUND"; else container_status=$(docker ps -a --filter "id=${container_id}" --format "{{.Status}}" | head -n 1); running_for=$(docker ps --filter "id=${container_id}" --format "{{.RunningFor}}" | head -n 1); restarts=$(docker inspect --format '{{.RestartCount}}' "$container_id" 2>/dev/null); local inspect_exit_code=$?; if [ $inspect_exit_code -ne 0 ]; then restarts="N/A"; log_msg "${YELLOW}Warning: Could not inspect container restart count.${NC}"; RESULTS[docker_error]="inspect_failed"; fi; RESULTS[docker_status_raw]="$container_status"; RESULTS[docker_restarts]="${restarts:-N/A}"; RESULTS[docker_running_for]="${running_for:-N/A}"; if [[ "$container_status" == "Up "* ]]; then log_result "${GREEN}✅ WeSendit Node container '${container_name}' is RUNNING${NC} (For: ${running_for:-N/A}, Restarts: ${restarts:-N/A})"; status_text="$STATUS_RUNNING"; if [[ "$restarts" =~ ^[0-9]+$ ]] && [ "$restarts" -gt 5 ]; then log_result "${YELLOW}⚠️ High restart count (${restarts}) detected.${NC}"; status_text="$STATUS_WARNING"; RESULTS[docker_warning]="high_restarts"; fi; else log_result "${YELLOW}⚠️ WeSendit Node container '${container_name}' exists but is STOPPED${NC} (Status: ${container_status}, Restarts: ${restarts:-N/A})"; status_text="$STATUS_STOPPED"; fi; RESULTS[docker_status]="$status_text"; fi; log_hdr ""; }
ping_test() { log_hdr "${BLUE}Performing ping test...${NC}"; local host=$1; local count=$2; local ping_cmd ping_output avg_rtt times spinner_pid exit_code status_text="$STATUS_FAILED"; RESULTS[ping_status]="$STATUS_UNKNOWN"; RESULTS[ping_latency_ms]="N/A"; if ! command -v ping &> /dev/null; then log_msg "${YELLOW}Warning: 'ping' command not found. Skipping.${NC}"; RESULTS[ping_status]="$STATUS_SKIPPED"; return 1; fi; ping_cmd="ping -c $count $host"; log_msg "Pinging ${host} (${count} times)..."; if ! host "$host" > /dev/null 2>&1 && ! nslookup "$host" > /dev/null 2>&1 && ! getent hosts "$host" > /dev/null 2>&1; then log_result "${RED}Error: Could not resolve hostname ${host}${NC}"; RESULTS[ping_status]="$STATUS_FAILED"; RESULTS[ping_error]="dns_error"; return 1; fi; log_msg_n "Pinging..."; show_spinner $$ & spinner_pid=$!; ping_output=$(timeout 30 $ping_cmd 2>&1); exit_code=$?; kill $spinner_pid >/dev/null 2>&1; wait $spinner_pid 2>/dev/null; printf "\r%*s\r" "$(tput cols)" "" ; if [ $exit_code -ne 0 ] && [ $exit_code -ne 1 ] && [ $exit_code -ne 2 ]; then log_result "${RED}Ping command failed or timed out (Exit code: $exit_code)${NC}"; RESULTS[ping_status]="$STATUS_FAILED"; RESULTS[ping_error]="ping_timeout_error"; return 1; fi; if echo "$ping_output" | grep -q "100% packet loss"; then log_result "${RED}Ping test failed: 100% packet loss${NC}"; RESULTS[ping_status]="$STATUS_FAILED"; RESULTS[ping_error]="packet_loss"; return 1; fi; avg_rtt=$(echo "$ping_output" | grep -oP 'min/avg/max[^=]*= \K[0-9.]+/[0-9.]+/\K[0-9.]+' 2>/dev/null); if [ -z "$avg_rtt" ]; then avg_rtt=$(echo "$ping_output" | grep -oP 'rtt min/avg/max.*?=.*?/([0-9.]+)/.* ms' | sed 's|.*/\([0-9.]\+\)/.*|\1|'); fi; if [ -z "$avg_rtt" ]; then avg_rtt=$(echo "$ping_output" | awk -F '/' '/round-trip min\/avg\/max/ { print $5 }'); fi; if [ -z "$avg_rtt" ]; then times=$(echo "$ping_output" | grep -oP 'time=\K[0-9.]+' 2>/dev/null); if [ -n "$times" ]; then avg_rtt=$(echo "$times" | awk '{ sum += $1; n++ } END { if (n > 0) printf "%.3f", sum / n; else print ""; }'); fi; fi; if [ -n "$avg_rtt" ]; then log_msg "Average ping latency to ${host}: ${YELLOW}${avg_rtt}ms${NC}"; RESULTS[ping_latency_ms]="$avg_rtt"; if [ "$CHECK_REQUIREMENTS" = true ]; then log_msg "Ping latency requirements: Minimum: <${MAX_PING}ms, Recommended: <${REC_PING}ms"; status_text=$(evaluate_status "$avg_rtt" "$MAX_PING" "$REC_PING" true); if [ "$status_text" = "$STATUS_OPTIMAL" ]; then log_result "${GREEN}✅ Ping latency meets recommended specs${NC}"; elif [ "$status_text" = "$STATUS_ADEQUATE" ]; then log_result "${YELLOW}⚠️ Ping latency meets minimum but not recommended specs${NC}"; else log_result "${RED}❌ Ping latency above maximum threshold${NC}"; fi; else status_text="$STATUS_OK"; fi; RESULTS[ping_status]="$status_text"; log_hdr ""; return 0; else log_result "${RED}Ping test to ${host} failed: Could not parse average RTT.${NC}"; if [ "$VERBOSE" = true ]; then log_msg "Output: $ping_output"; fi; RESULTS[ping_status]="$STATUS_FAILED"; RESULTS[ping_error]="parse_error"; log_hdr ""; return 1; fi; }
measure_tcp_latency() { local host=$1; local port=$2; local type=$3; local start_time status end_time latency rounded_latency; if [ "$TEST_LATENCY" != true ]; then return; fi; log_hdr "${BLUE}Measuring ${type} TCP connection latency to ${host}:${port}...${NC}"; start_time=$(date +%s.%N); timeout 2 bash -c "true &> /dev/tcp/${host}/${port}" 2>/dev/null; status=$?; end_time=$(date +%s.%N); if [ $status -eq 0 ]; then latency=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null); rounded_latency=$(printf "%.3f" "$latency" 2>/dev/null); log_msg "${BLUE}${type^} TCP connection latency: ${YELLOW}${rounded_latency}ms${NC}"; else log_msg "${YELLOW}Could not measure ${type} TCP latency (connection failed or timed out)${NC}"; fi; }
check_internet_port() { local port=$1; local description=$2; local public_ip test_url result spinner_pid status_text="$STATUS_UNKNOWN" curl_output exit_code; RESULTS[master_port_status]="$STATUS_UNKNOWN"; if [ "$VERBOSE" = true ]; then log_hdr "${BLUE}Testing TCP Port $port ($description) from Internet...${NC}"; fi; public_ip=$(curl -s -m 10 https://api.ipify.org); exit_code=$?; if [ $exit_code -ne 0 ] || [ -z "$public_ip" ]; then log_result "TCP Port $port ($description) from Internet: ${RED}❌ FAILED (Could not get Public IP)${NC}"; RESULTS[master_port_status]="$STATUS_FAILED"; RESULTS[master_port_error]="ip_lookup_failed"; return 1; fi; log_msg_n "Checking port ${port} via external service (canyouseeme.org)... "; show_spinner $$ & spinner_pid=$!; curl_output=$(curl -s -X POST "https://canyouseeme.org/" -H "User-Agent: Mozilla/5.0 (compatible; PortCheckerScript/1.0)" -H "Content-Type: application/x-www-form-urlencoded" --data-urlencode "port=${port}" --data-urlencode "IP=${public_ip}" -m 30); exit_code=$?; kill $spinner_pid >/dev/null 2>&1; wait $spinner_pid 2>/dev/null; printf "\r%*s\r" "$(tput cols)" "" ; if [ $exit_code -ne 0 ]; then log_result "TCP Port $port ($description) from Internet: ${RED}❌ FAILED (Error connecting to canyouseeme.org)${NC}"; RESULTS[master_port_status]="$STATUS_FAILED"; RESULTS[master_port_error]="cysmo_connect_failed"; return 1; fi; result=$(echo "$curl_output" | grep -Eo 'Success:|Error:'); if echo "$result" | grep -q 'Success:'; then log_result "TCP Port $port ($description) from Internet: ${GREEN}✅ OPEN${NC}"; status_text="$STATUS_OPEN"; MASTER_PORT_OPEN=true; if [ "$TEST_LATENCY" = true ]; then measure_tcp_latency "$public_ip" "$port" "internet"; fi; elif echo "$result" | grep -q 'Error:'; then log_result "TCP Port $port ($description) from Internet: ${RED}❌ CLOSED/Error${NC}"; status_text="$STATUS_CLOSED"; MASTER_PORT_OPEN=false; if [ "$VERBOSE" = true ]; then reason=$(echo "$curl_output" | grep -oP '(?<=Error: ).*?(?=<)'); log_msg "   Reason: ${reason:-Unknown}"; fi; else log_result "TCP Port $port ($description) from Internet: ${YELLOW}⚠️ UNKNOWN (Could not parse service response)${NC}"; status_text="$STATUS_UNKNOWN"; MASTER_PORT_OPEN=false; RESULTS[master_port_error]="cysmo_parse_failed"; if [ "$VERBOSE" = true ]; then log_msg "Debug raw response: $curl_output"; fi; fi; RESULTS[master_port_status]="$status_text"; log_hdr ""; return $([ "$status_text" = "$STATUS_OPEN" ] && echo 0 || echo 1); }
check_local_port() { local port=$1; local description=$2; local result_stderr nc_exit_code status_text="$STATUS_UNKNOWN"; local result_stdout=""; RESULTS[storage_port_status]="$STATUS_UNKNOWN"; if [ "$VERBOSE" = true ]; then log_hdr "${BLUE}Testing TCP Port $port ($description) locally...${NC}"; fi; { result_stderr=$(nc -z -v -w 5 localhost $port 2>&1 >&3 3>&-); nc_exit_code=$?; } 3>&1; if [ $nc_exit_code -eq 0 ]; then log_result "TCP Port $port ($description) locally: ${GREEN}✅ OPEN${NC}"; status_text="$STATUS_OPEN"; STORAGE_PORT_OPEN=true; if [ "$TEST_LATENCY" = true ]; then measure_tcp_latency "localhost" "$port" "local"; fi; else log_result "TCP Port $port ($description) locally: ${RED}❌ CLOSED${NC}"; status_text="$STATUS_CLOSED"; STORAGE_PORT_OPEN=false; if [ "$VERBOSE" = true ]; then log_msg "Debug output: $result_stderr"; fi; fi; RESULTS[storage_port_status]="$status_text"; log_hdr ""; return $nc_exit_code; }
check_firewall_status() { local port=$1; local direction=$2; local tool_found=false; if [ "$VERBOSE" = true ]; then log_hdr "${BLUE}Checking firewall status for port $port ($direction)...${NC}"; fi; if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then tool_found=true; if ufw status | grep -q "$port[/ ]*tcp" | grep -iq "ALLOW"; then log_msg "Firewall (ufw):   ${GREEN}Port $port/tcp seems ALLOWED${NC}"; elif ufw status | grep -q "$port[/ ]*tcp" | grep -iq "DENY"; then log_msg "Firewall (ufw):   ${RED}Port $port/tcp seems DENIED${NC}"; else log_msg "Firewall (ufw):   ${YELLOW}Port $port/tcp rule not found or inactive${NC}"; if [ "$direction" = "in" ]; then ufw status | grep -iq "Default: deny (incoming)" && log_msg "Firewall (ufw):   ${YELLOW}Default incoming policy is DENY${NC}"; else ufw status | grep -iq "Default: deny (outgoing)" && log_msg "Firewall (ufw):   ${YELLOW}Default outgoing policy is DENY${NC}"; fi; fi; fi; if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then tool_found=true; if firewall-cmd --list-ports --permanent | grep -q "$port/tcp"; then log_msg "Firewall (firewalld): ${GREEN}Port $port/tcp allowed in default zone (permanent)${NC}"; else log_msg "Firewall (firewalld): ${YELLOW}Port $port/tcp not found in default zone permanent rules${NC}"; fi; fi; if command -v iptables &> /dev/null; then tool_found=true; local chain="INPUT"; [ "$direction" = "out" ] && chain="OUTPUT"; if iptables -S "$chain" 2>/dev/null | grep -q -- "-p tcp .*--dport $port -j ACCEPT"; then log_msg "Firewall (iptables): ${GREEN}Found ACCEPT rule for $port/tcp in $chain chain${NC}"; else log_msg "Firewall (iptables): ${YELLOW}No simple ACCEPT rule found for $port/tcp in $chain chain${NC}"; fi; fi; if [ "$tool_found" = false ] && [ "$VERBOSE" = true ]; then log_msg "No supported firewall tool detected or active."; fi; }

# --- Core Logic Functions ---
check_system_requirements() { log_hdr "\n${BLUE}=== System Requirements Check ===${NC}\n"; check_cpu_requirements; check_storage_requirements; check_bandwidth_requirements; check_docker_wesendit_node; log_hdr "${BLUE}=== System Requirements Check Completed ===${NC}\n"; }

# Generates the human-readable summary report
generate_summary() {
    # Always use printf for summary output components
    printf "\n%b\n" "${BLUE}=== SUMMARY REPORT ===${NC}"
    local cpu_status_text=${RESULTS[cpu_status]:-$STATUS_UNKNOWN}; local storage_req_status_text=${RESULTS[storage_status]:-$STATUS_UNKNOWN}; local ping_status_text=${RESULTS[ping_status]:-$STATUS_UNKNOWN}; local docker_status_text=${RESULTS[docker_status]:-$STATUS_UNKNOWN}
    local master_port_status_text=${RESULTS[master_port_status]:-$STATUS_UNKNOWN}; local storage_port_status_text=${RESULTS[storage_port_status]:-$STATUS_UNKNOWN}
    local cpu_cores_det=${RESULTS[cpu_cores]:-N/A}; local storage_avail_det=${RESULTS[storage_available_gb]:-N/A}; local ping_latency_det=${RESULTS[ping_latency_ms]:-N/A}; local docker_detail=""
    if [ "$docker_status_text" == "$STATUS_RUNNING" ]; then docker_detail="${RESULTS[docker_running_for]}"; elif [ "$docker_status_text" == "$STATUS_WARNING" ]; then docker_detail="Restarts: ${RESULTS[docker_restarts]}"; elif [ "$docker_status_text" == "$STATUS_STOPPED" ]; then docker_detail="${RESULTS[docker_status_raw]}"; fi
    local cpu_color=${YELLOW}; if [ "$cpu_status_text" = "$STATUS_OPTIMAL" ]; then cpu_color=$GREEN; elif [ "$cpu_status_text" = "$STATUS_FAILED" ]; then cpu_color=$RED; fi
    local storage_color=${YELLOW}; if [ "$storage_req_status_text" = "$STATUS_OPTIMAL" ]; then storage_color=$GREEN; elif [ "$storage_req_status_text" = "$STATUS_FAILED" ]; then storage_color=$RED; fi
    local ping_color=${YELLOW}; if [ "$ping_status_text" = "$STATUS_OPTIMAL" ]; then ping_color=$GREEN; elif [ "$ping_status_text" = "$STATUS_FAILED" ]; then ping_color=$RED; fi
    local docker_color=${YELLOW}; if [ "$docker_status_text" = "$STATUS_RUNNING" ]; then docker_color=$GREEN; elif [[ "$docker_status_text" = "$STATUS_FAILED"* || "$docker_status_text" = "$STATUS_NOT_FOUND" ]]; then docker_color=$RED; fi
    local master_color=${YELLOW}; if [ "$master_port_status_text" = "$STATUS_OPEN" ]; then master_color=$GREEN; elif [ "$master_port_status_text" = "$STATUS_CLOSED" ]; then master_color=$RED; fi
    local storage_port_color=${YELLOW}; if [ "$storage_port_status_text" = "$STATUS_OPEN" ]; then storage_port_color=$GREEN; elif [ "$storage_port_status_text" = "$STATUS_CLOSED" ]; then storage_port_color=$RED; fi
    local col1_width=20; local col2_width=13; local col3_width=16; local border_line="+----------------------+---------------+------------------+"
    local bw_status_text=${RESULTS[bandwidth_status]:-$STATUS_UNKNOWN}
    local bw_color=${YELLOW}; if [ "$bw_status_text" = "$STATUS_OPTIMAL" ]; then bw_color=$GREEN; elif [[ "$bw_status_text" = "$STATUS_FAILED"* ]]; then bw_color=$RED; fi

    printf "%s\n" "$border_line"; printf "| %-*s | %-*s | %-*s |\n" "$col1_width" "Component" "$col2_width" "Status" "$col3_width" "Details"; printf "%s\n" "$border_line"
    if [ "$CHECK_REQUIREMENTS" = true ]; then
      printf "| %-*s | %b%-*s%b | %*s |\n" "$col1_width" "CPU" "$cpu_color" "$col2_width" "$cpu_status_text" "$NC" "$col3_width" "${cpu_cores_det} cores"
      printf "| %-*s | %b%-*s%b | %*s |\n" "$col1_width" "Storage" "$storage_color" "$col2_width" "$storage_req_status_text" "$NC" "$col3_width" "${storage_avail_det}GB available"
      printf "| %-*s | %b%-*s%b | %*s |\n" "$col1_width" "Network Latency" "$ping_color" "$col2_width" "$ping_status_text" "$NC" "$col3_width" "${ping_latency_det}ms"
      printf "| %-*s | %b%-*s%b | %*s |\n" "$col1_width" "WeSendit Node Docker" "$docker_color" "$col2_width" "$docker_status_text" "$NC" "$col3_width" "$docker_detail"
    fi
    if [ "$CHECK_MASTER_INTERNET" = true ]; then
        printf "| %-*s | %b%-*s%b | %-*s |\n" "$col1_width" "Master Port ($MASTER_TCP_PORT)" "$master_color" "$col2_width" "$master_port_status_text" "$NC" "$col3_width" ""
    fi
    if [ "$CHECK_STORAGE_LOCAL" = true ]; then
        printf "| %-*s | %b%-*s%b | %-*s |\n" "$col1_width" "Storage Port ($STORAGE_TCP_PORT)" "$storage_port_color" "$col2_width" "$storage_port_status_text" "$NC" "$col3_width" ""
    fi
    printf "%s\n" "$border_line"

    if [ "$CHECK_REQUIREMENTS" = true ] && [[ "$bw_status_text" != "$STATUS_FAILED"* ]] && [ "$bw_status_text" != "$STATUS_SKIPPED" ] && [ "$bw_status_text" != "" ] && [ "$bw_status_text" != "$STATUS_UNKNOWN" ]; then printf "%b\n" "${BLUE}Measured Bandwidth: ${RESULTS[bandwidth_down_mbps]:-N/A}↓ / ${RESULTS[bandwidth_up_mbps]:-N/A}↑ Mbps${NC}"; fi

    printf "\n%b\n" "${BLUE}RECOMMENDATION:${NC}"; local has_failed=false; local is_optimal=true; local failed_components="" non_optimal_components=""
    if [ "$CHECK_REQUIREMENTS" = true ]; then
        [[ "${RESULTS[cpu_status]}" == "$STATUS_FAILED" ]] && { has_failed=true; failed_components+=" ${cpu_color}CPU(F)${NC}"; }; [[ "${RESULTS[cpu_status]}" == "$STATUS_ADEQUATE" ]] && { is_optimal=false; non_optimal_components+=" ${cpu_color}CPU(A)${NC}"; }
        [[ "${RESULTS[storage_status]}" == "$STATUS_FAILED" ]] && { has_failed=true; failed_components+=" ${storage_color}Storage(F)${NC}"; }; [[ "${RESULTS[storage_status]}" == "$STATUS_ADEQUATE" ]] && { is_optimal=false; non_optimal_components+=" ${storage_color}Storage(A)${NC}"; }
        [[ "${RESULTS[ping_status]}" == "$STATUS_FAILED" ]] && { has_failed=true; failed_components+=" ${ping_color}Latency(F)${NC}"; }; [[ "${RESULTS[ping_status]}" == "$STATUS_ADEQUATE" ]] && { is_optimal=false; non_optimal_components+=" ${ping_color}Latency(A)${NC}"; }
        [[ "${RESULTS[bandwidth_status]}" == "$STATUS_FAILED"* ]] && { has_failed=true; failed_components+=" ${bw_color}Bandwidth(F)${NC}"; }; [[ "${RESULTS[bandwidth_status]}" == "$STATUS_ADEQUATE" ]] && { is_optimal=false; non_optimal_components+=" ${bw_color}Bandwidth(A)${NC}"; }
        [[ "${RESULTS[docker_status]}" == "$STATUS_FAILED"* || "${RESULTS[docker_status]}" == "$STATUS_NOT_FOUND" ]] && { has_failed=true; failed_components+=" ${docker_color}Docker(F)${NC}"; }
        [[ "${RESULTS[docker_status]}" == "$STATUS_STOPPED" || "${RESULTS[docker_status]}" == "$STATUS_WARNING" ]] && { is_optimal=false; non_optimal_components+=" ${docker_color}Docker(${RESULTS[docker_status]:0:1})${NC}"; }
    fi
    if [ "$CHECK_MASTER_INTERNET" = true ]; then
        [[ "${RESULTS[master_port_status]}" == "$STATUS_CLOSED" ]] && { has_failed=true; failed_components+=" ${master_color}MasterPort(C)${NC}"; }; [[ "${RESULTS[master_port_status]}" != "$STATUS_OPEN" ]] && is_optimal=false
    fi
    if [ "$CHECK_STORAGE_LOCAL" = true ]; then
        [[ "${RESULTS[storage_port_status]}" == "$STATUS_CLOSED" ]] && { has_failed=true; failed_components+=" ${storage_port_color}StoragePort(C)${NC}"; }; [[ "${RESULTS[storage_port_status]}" != "$STATUS_OPEN" ]] && is_optimal=false
    fi

    # Determine overall optimality only if requirements were checked
    if [ "$CHECK_REQUIREMENTS" = true ]; then
        if [ "$has_failed" = false ]; then
            if [[ "${RESULTS[cpu_status]}" != "$STATUS_OPTIMAL" || \
                  "${RESULTS[storage_status]}" != "$STATUS_OPTIMAL" || \
                  "${RESULTS[ping_status]}" != "$STATUS_OPTIMAL" || \
                  "${RESULTS[docker_status]}" != "$STATUS_RUNNING" || \
                  ("${RESULTS[bandwidth_status]}" != "$STATUS_OPTIMAL" && "${RESULTS[bandwidth_status]}" != "$STATUS_SKIPPED") ]]; then
                is_optimal=false
            fi
        else
            is_optimal=false
        fi
    fi
     # Also consider port checks for overall optimality if they were performed
    if [ "$CHECK_MASTER_INTERNET" = true ] && [[ "${RESULTS[master_port_status]}" != "$STATUS_OPEN" ]]; then is_optimal=false; fi
    if [ "$CHECK_STORAGE_LOCAL" = true ] && [[ "${RESULTS[storage_port_status]}" != "$STATUS_OPEN" ]]; then is_optimal=false; fi


    if [ "$has_failed" = true ]; then printf "%b\n" "${RED}❌ Checks FAILED:${failed_components}${NC}"; printf "%b\n" "${RED}   Please address FAILED (F), CLOSED (C), or NOT FOUND issues.${NC}";
    elif [ "$is_optimal" = false ] || [ -n "$non_optimal_components" ]; then printf "%b\n" "${YELLOW}⚠️ Meets minimums, but not optimal:${non_optimal_components}${NC}"; printf "%b\n" "${YELLOW}   Consider addressing ADEQUATE (A), STOPPED (S), WARNING (W) or other non-optimal components.${NC}";
    else printf "%b\n" "${GREEN}✅ All checks passed and meet recommended requirements.${NC}"; printf "%b\n" "${GREEN}   System appears ready.${NC}"; fi

    if [ "${RESULTS[bandwidth_error]}" == "jq_missing" ]; then printf "%b\n" "${YELLOW}   Note: Bandwidth check requires 'jq' to be installed.${NC}"; fi
    if [ "${RESULTS[docker_error]}" == "docker_missing" ]; then printf "%b\n" "${YELLOW}   Note: Docker check requires 'docker' to be installed.${NC}"; fi
    if [[ "${RESULTS[bandwidth_error]}" == "speedtest_failed" || "${RESULTS[bandwidth_error]}" == "invalid_json" || "${RESULTS[bandwidth_error]}" == "jq_parse_failed" ]]; then printf "%b\n" "${RED}   Note: Bandwidth test failed to provide results.${NC}"; fi
    if [ "${RESULTS[bandwidth_status]}" == "$STATUS_SKIPPED" ]; then printf "%b\n" "${BLUE}   Note: Bandwidth test was skipped (tool not found).${NC}"; fi
    printf "\n"
}

# Generates JSON output
generate_json_output() {
    local kv_pairs=""; local key value exit_code
    local keys_order=("timestamp" "public_ip" "cpu_status" "cpu_cores" "cpu_speed_ghz" "cpu_arch" "cpu_model" "cpu_error" "storage_status" "storage_available_gb" "storage_error" "bandwidth_status" "bandwidth_down_mbps" "bandwidth_up_mbps" "bandwidth_error" "ping_status" "ping_latency_ms" "ping_error" "docker_status" "docker_running_for" "docker_restarts" "docker_status_raw" "docker_error" "docker_warning" "master_port_status" "master_port_error" "storage_port_status" "storage_port_error")
    for key in "${keys_order[@]}"; do if [[ -v RESULTS[$key] && -n "${RESULTS[$key]}" ]]; then value="${RESULTS[$key]}"; value=${value//\\/\\\\}; value=${value//\"/\\\"}; value=${value//$'\n'/\\n}; value=${value//$'\r'/\\r}; value=${value//$'\t'/\\t}; kv_pairs+=$(printf '"%s":"%s",' "$key" "$value"); fi; done
    printf "{%s}" "${kv_pairs%,}" | jq '.' ; exit_code=$?; if [ $exit_code -ne 0 ]; then echo "Error: Failed to generate valid JSON output with jq." >&2; if [ "$VERBOSE" = true ]; then printf "%s\n" "$kv_pairs"; fi; return 1; fi
    return 0
}

# Runs the sequence of tests (when not running a specific test)
run_tests() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S'); log_hdr "\n${BLUE}=== Node Port Configuration Check - $timestamp ===${NC}\n"
    RESULTS=( [timestamp]="$timestamp" ); local public_ip=$(curl -s -m 10 https://api.ipify.org || echo "N/A"); local exit_code=$?
    if [ "$public_ip" != "N/A" ] && [ $exit_code -eq 0 ]; then log_msg "Public IP: ${YELLOW}${public_ip}${NC}"; RESULTS[public_ip]="$public_ip"; else log_result "${RED}Warning: Could not determine public IP address.${NC}"; RESULTS[public_ip]="ERROR"; fi; log_hdr ""
    if [ "$CHECK_REQUIREMENTS" = true ]; then check_system_requirements; fi
    log_hdr "${BLUE}NETWORK LATENCY TEST${NC}"; log_hdr "Testing connection to network server (e.g., mst-eu1.wsi-sns.network)..."; ping_test "mst-eu1.wsi-sns.network" 5; log_hdr ""
    if [ "$CHECK_MASTER_INTERNET" = true ]; then log_hdr "${BLUE}MASTER NODE PORT (TCP $MASTER_TCP_PORT)${NC}"; log_hdr "Status: Must be open externally for Master Node connection."; log_hdr ""; if [ "$CHECK_FIREWALL" = true ]; then check_firewall_status $MASTER_TCP_PORT "in"; fi; check_internet_port $MASTER_TCP_PORT "Master node"; log_hdr ""; fi
    if [ "$CHECK_STORAGE_LOCAL" = true ]; then log_hdr "${BLUE}STORAGE NODE PORT (TCP $STORAGE_TCP_PORT)${NC}"; log_hdr "Status: Local connection check for dashboard/onboarding."; log_hdr ""; if [ "$CHECK_FIREWALL" = true ]; then check_firewall_status $STORAGE_TCP_PORT "in"; fi; check_local_port $STORAGE_TCP_PORT "Storage node"; log_hdr ""; fi
    log_hdr "${BLUE}=== Tests completed ===${NC}"
}

# Initializes the log file
init_log_file() { if [ -n "$LOG_FILE" ]; then if touch "$LOG_FILE" 2>/dev/null; then echo "# Node Port Check Log - Started $(date)" > "$LOG_FILE"; echo "# Script version: $(basename "$0") v2.3" >> "$LOG_FILE"; echo "# System: $(uname -a)" >> "$LOG_FILE"; echo "" >> "$LOG_FILE"; else log_result "${RED}Error: Cannot write to log file: $LOG_FILE${NC}"; LOG_FILE=""; fi; fi; }

# Main execution logic
main() {
    export LC_ALL=C
    parse_args "$@"

    # Initialize RESULTS array *after* parsing args, so colors are set correctly
     declare -A RESULTS=(
        [cpu_status]="${YELLOW}UNKNOWN${NC}" [cpu_cores]="N/A" [cpu_speed_ghz]="N/A" [cpu_arch]="N/A" [cpu_model]="N/A" [cpu_error]=""
        [storage_status]="${YELLOW}UNKNOWN${NC}" [storage_available_gb]="N/A" [storage_error]=""
        [bandwidth_status]="${YELLOW}UNKNOWN${NC}" [bandwidth_down_mbps]="N/A" [bandwidth_up_mbps]="N/A" [bandwidth_error]=""
        [ping_status]="${YELLOW}UNKNOWN${NC}" [ping_latency_ms]="N/A" [ping_error]=""
        [docker_status]="${YELLOW}UNKNOWN${NC}" [docker_running_for]="N/A" [docker_restarts]="N/A" [docker_status_raw]="N/A" [docker_error]="" [docker_warning]=""
        [master_port_status]="${YELLOW}UNKNOWN${NC}" [master_port_error]=""
        [storage_port_status]="${YELLOW}UNKNOWN${NC}" [storage_port_error]=""
        [public_ip]="N/A" [timestamp]=""
    )

    init_log_file
    check_root
    check_dependencies # Check dependencies regardless of specific test

    # --- Execute specific test OR full sequence ---
    if [ -n "$SPECIFIC_TEST" ]; then
        # --- Run a Single Specified Test ---
        log_hdr "\n${BLUE}=== Running Specific Test: $SPECIFIC_TEST ===${NC}\n"
        case "$SPECIFIC_TEST" in
            cpu) check_cpu_requirements ;;
            storage) check_storage_requirements ;;
            bandwidth) check_bandwidth_requirements ;;
            docker) check_docker_wesendit_node ;;
            ping) ping_test "mst-eu1.wsi-sns.network" 5 ;;
            master-port) check_internet_port $MASTER_TCP_PORT "Master node" ;;
            storage-port) check_local_port $STORAGE_TCP_PORT "Storage node" ;;
            firewall)
                log_msg "Checking firewall status for Master ($MASTER_TCP_PORT/tcp) and Storage ($STORAGE_TCP_PORT/tcp) ports..."
                check_firewall_status $MASTER_TCP_PORT "in"
                check_firewall_status $STORAGE_TCP_PORT "in"
                ;;
            # No *) case needed due to validation in parse_args
        esac
        log_hdr "${BLUE}=== Specific Test ($SPECIFIC_TEST) Completed ===${NC}\n"
        # Output for specific tests relies on the individual check functions' logging.
        # No summary or JSON generation for single tests in this version.

    elif [ "$INTERVAL" -gt 0 ]; then
        # --- Run All Tests Periodically ---
        log_msg "Running all tests every $INTERVAL seconds. Press Ctrl+C to stop."
        while true; do
            run_tests # Calls the function that runs everything enabled
            if [ "$OUTPUT_FORMAT" = "json" ]; then generate_json_output
            # Generate summary only if some checks were actually supposed to run
            elif [ "$CHECK_REQUIREMENTS" = true ] || [ "$CHECK_MASTER_INTERNET" = true ] || [ "$CHECK_STORAGE_LOCAL" = true ]; then generate_summary
            fi
            if [ "$OUTPUT_FORMAT" = "human" ]; then log_msg "Waiting for $INTERVAL seconds..."; fi
            sleep $INTERVAL
        done
    else
        # --- Run All Tests Once ---
        run_tests # Calls the function that runs everything enabled
        if [ "$OUTPUT_FORMAT" = "json" ]; then generate_json_output
        # Generate summary only if some checks were actually supposed to run
        elif [ "$CHECK_REQUIREMENTS" = true ] || [ "$CHECK_MASTER_INTERNET" = true ] || [ "$CHECK_STORAGE_LOCAL" = true ]; then generate_summary
        else
            # If all major checks were disabled via flags, inform the user
            if [ "$OUTPUT_FORMAT" = "human" ]; then printf "\n%b\n" "${BLUE}No summary generated as requirements and port checks were disabled.${NC}"; fi
        fi
    fi
}

# --- Script Start ---
main "$@"