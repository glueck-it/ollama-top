#!/usr/bin/env bash
# ==============================================================================
# ollama-top (otop) — Linux / macOS CLI Live Monitor for Ollama, GPUs & Databases
# Zero-dependency Bash implementation
# Author: Frank Glück (Glück IT) — https://dozent.net
# License: MIT
# ==============================================================================

set -u

# --- Config & Defaults ---
REFRESH_SEC=1.2
TOTAL_ITEMS=0
JOB_TITLE="Batch Job"
WATCH_PORTS=()
OLLAMA_PORTS=(11434 11435 8000)
WIDTH=108

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--total)
            TOTAL_ITEMS="$2"
            shift 2
            ;;
        -j|--title)
            JOB_TITLE="$2"
            shift 2
            ;;
        -r|--refresh)
            REFRESH_SEC="$2"
            shift 2
            ;;
        -w|--width)
            WIDTH="$2"
            shift 2
            ;;
        -p|--ports)
            IFS=',' read -r -a WATCH_PORTS <<< "$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -t, --total NUM      Total items in batch job"
            echo "  -j, --title TITLE    Batch job title"
            echo "  -r, --refresh SEC    Refresh interval in seconds (default: 1.2)"
            echo "  -p, --ports 1521,3306 Custom database/service ports to monitor"
            echo "  -w, --width NUM      Terminal dashboard width (default: 108)"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# --- Colors ---
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_GRAY=$'\033[90m'
C_RED=$'\033[91m'
C_GREEN=$'\033[92m'
C_YELLOW=$'\033[93m'
C_BLUE=$'\033[94m'
C_MAGENTA=$'\033[95m'
C_CYAN=$'\033[96m'
C_WHITE=$'\033[97m'
C_DGRAY=$'\033[38;5;240m'
C_DCYAN=$'\033[36m'
C_DYELLOW=$'\033[33m'

# --- Seamless Box Drawing Characters ---
CH_FULL="█"
CH_HBAR="─"
CH_DBAR="═"

# Generate separators of exact width
SEP_SUB=$(printf '%*s' "$WIDTH" '' | tr ' ' "$CH_HBAR")
SEP_MAIN=$(printf '%*s' "$WIDTH" '' | tr ' ' "$CH_DBAR")

# State tracking
START_TIME=$(date +%s)
PREV_RX=0
PREV_TX=0
SESSION_RX=0
SESSION_TX=0
PREV_TIME=$(date +%s%N)
FIRST_NET=1

format_bytes() {
    local b=$1
    if (( b >= 1073741824 )); then
        awk -v b="$b" 'BEGIN { printf "%.2f GB", b/1073741824 }'
    elif (( b >= 1048576 )); then
        awk -v b="$b" 'BEGIN { printf "%.2f MB", b/1048576 }'
    elif (( b >= 1024 )); then
        awk -v b="$b" 'BEGIN { printf "%.1f KB", b/1024 }'
    else
        printf "%d B" "$b"
    fi
}

format_bar() {
    local pct=$1
    local width=${2:-18}
    local filled=$(awk -v p="$pct" -v w="$width" 'BEGIN { v=int(p*w); if(v>w)v=w; if(v<0)v=0; print v }')
    local empty=$(( width - filled ))
    printf "%s%s" "$(printf '%*s' "$filled" '' | tr ' ' "$CH_FULL")" "$(printf '%*s' "$empty" '')"
}

get_service_name() {
    local port=$1
    case "$port" in
        1521|1522|1523|1524|1525|2483|2484) echo "Oracle DB" ;;
        1433|1434) echo "Microsoft SQL Server" ;;
        50000|50001|60000) echo "IBM DB2" ;;
        9088|9089|1526|1527) echo "IBM Informix" ;;
        30013|30015|30215|39013|39015|39017) echo "SAP HANA" ;;
        5432|5433|5434|5435|5436|5437|5438|5439) echo "PostgreSQL" ;;
        6432) echo "PgBouncer" ;;
        3306|3307) echo "MySQL / MariaDB" ;;
        33060) echo "MySQL (X-Protocol)" ;;
        5000|4100) echo "Sybase / SAP ASE" ;;
        1025) echo "Teradata" ;;
        27017|27018|27019) echo "MongoDB" ;;
        6379|6380) echo "Redis / Valkey Cache" ;;
        9042|9160) echo "Apache Cassandra" ;;
        8123) echo "ClickHouse (HTTP)" ;;
        9000) echo "ClickHouse (Native)" ;;
        9200|9300) echo "Elasticsearch" ;;
        7474|7687) echo "Neo4j" ;;
        9092|9093) echo "Apache Kafka" ;;
        5672|15672) echo "RabbitMQ" ;;
        11434) echo "Ollama (Primary)" ;;
        11435) echo "Ollama (Secondary)" ;;
        8000|8080) echo "HTTP API / vLLM" ;;
        *) echo "TCP Service" ;;
    esac
}

get_network_scope() {
    local ip=$1
    if [[ "$ip" =~ ^127\. || "$ip" == "::1" || "$ip" == "localhost" ]]; then
        echo "Localhost IPC (Loopback)"
    elif [[ "$ip" =~ ^10\. || "$ip" =~ ^192\.168\. || "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        echo "Local LAN / On-Premise"
    else
        echo "Remote WAN / Cloud"
    fi
}

render() {
    clear
    local now=$(date +"%H:%M:%S")
    local host_name=$(hostname 2>/dev/null || echo "LinuxHost")

    echo ""
    echo "${C_CYAN}${SEP_MAIN}${C_RESET}"
    printf "  ${C_YELLOW}OLLAMA-TOP: AI, DATABASE & HARDWARE MONITOR${C_RESET}  |  ${C_GRAY}%s  |  Host: %s${C_RESET}\n" "$now" "$host_name"
    printf "  ${C_DCYAN}Author: Frank Glück (Glück IT)  |  Web: https://dozent.net  |  GitHub: https://github.com/glueck-it/ollama-top${C_RESET}\n"
    echo "${C_DCYAN}${SEP_SUB}${C_RESET}"

    # 1. NVIDIA GPU Sensors (if nvidia-smi available)
    if command -v nvidia-smi &>/dev/null; then
        local smi_out
        smi_out=$(nvidia-smi --query-gpu=name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw,clocks.current.graphics,clocks.current.memory --format=csv,noheader,nounits 2>/dev/null | head -n 1)
        if [[ -n "$smi_out" ]]; then
            IFS=',' read -r g_name g_util g_bus g_vram_used g_vram_tot g_temp g_pwr g_cclk g_mclk <<< "$smi_out"
            g_name=$(echo "$g_name" | sed 's/NVIDIA //g; s/^[ \t]*//; s/[ \t]*$//')
            g_util=$(echo "$g_util" | tr -d ' ')
            g_bus=$(echo "$g_bus" | tr -d ' ')
            g_vram_used=$(awk -v v="$g_vram_used" 'BEGIN { printf "%.1f", v/1024 }')
            g_vram_tot=$(awk -v v="$g_vram_tot" 'BEGIN { printf "%.1f", v/1024 }')
            g_temp=$(echo "$g_temp" | tr -d ' ')
            g_pwr=$(echo "$g_pwr" | tr -d ' ')
            g_cclk=$(echo "$g_cclk" | tr -d ' ')
            g_mclk=$(echo "$g_mclk" | tr -d ' ')

            local vram_pct=$(awk -v u="$g_vram_used" -v t="$g_vram_tot" 'BEGIN { if(t>0) printf "%.2f", u/t; else print 0 }')
            local g_util_pct=$(awk -v u="$g_util" 'BEGIN { printf "%.2f", u/100 }')
            local g_bus_pct=$(awk -v b="$g_bus" 'BEGIN { printf "%.2f", b/100 }')

            echo "  ${C_WHITE}NVIDIA GPU SENSORS (${g_name}):${C_RESET}"
            printf "  ${C_GRAY}GPU Core Load:   ${C_CYAN}[%s] ${C_YELLOW}%3d%%${C_GRAY}  | Clock: ${C_WHITE}%4d MHz${C_GRAY}  | Temp: ${C_GREEN}%d° C${C_RESET}\n" "$(format_bar "$g_util_pct" 18)" "$g_util" "$g_cclk" "$g_temp"
            printf "  ${C_GRAY}GPU Memory Bus:  ${C_CYAN}[%s] ${C_YELLOW}%3d%%${C_GRAY}  | Clock: ${C_WHITE}%4d MHz${C_GRAY}  | Power: ${C_WHITE}%5.1f W${C_RESET}\n" "$(format_bar "$g_bus_pct" 18)" "$g_bus" "$g_mclk" "$g_pwr"
            printf "  ${C_GRAY}VRAM Belegung:   ${C_MAGENTA}[%s] ${C_WHITE}%4.1f / %4.1f GB (${C_WHITE}%.0f%%)${C_RESET}\n" "$(format_bar "$vram_pct" 18)" "$g_vram_used" "$g_vram_tot" "$(awk -v p="$vram_pct" 'BEGIN { print p*100 }')"
            echo ""
        fi
    fi

    # 2. Host CPU & System RAM
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//; s/(R)//g; s/(TM)//g' || echo "Host CPU")
    local cpu_cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "1")
    local load_1m=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0")
    local cpu_pct=$(awk -v l="$load_1m" -v c="$cpu_cores" 'BEGIN { p=int((l/c)*100); if(p>100)p=100; print p }')
    local cpu_pct_norm=$(awk -v p="$cpu_pct" 'BEGIN { printf "%.2f", p/100 }')

    local ram_tot_kb=$(grep -m1 "MemTotal:" /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
    local ram_free_kb=$(grep -m1 "MemAvailable:" /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
    local ram_used_kb=$(( ram_tot_kb - ram_free_kb ))
    local ram_tot_gb=$(awk -v k="$ram_tot_kb" 'BEGIN { printf "%.1f", k/1048576 }')
    local ram_used_gb=$(awk -v k="$ram_used_kb" 'BEGIN { printf "%.1f", k/1048576 }')
    local ram_pct=$(awk -v u="$ram_used_kb" -v t="$ram_tot_kb" 'BEGIN { if(t>0) printf "%.2f", u/t; else print 0 }')

    echo "  ${C_WHITE}HOST CPU & SYSTEM (${cpu_model} - ${cpu_cores} Cores):${C_RESET}"
    printf "  ${C_GRAY}CPU Auslastung:  ${C_GREEN}[%s] ${C_YELLOW}%3d%%${C_GRAY}  | Load 1m: ${C_WHITE}%s${C_RESET}\n" "$(format_bar "$cpu_pct_norm" 18)" "$cpu_pct" "$load_1m"
    printf "  ${C_GRAY}System RAM:      ${C_BLUE}[%s] ${C_WHITE}%4.1f / %4.1f GB (${C_WHITE}%.0f%%)${C_RESET}\n" "$(format_bar "$ram_pct" 18)" "$ram_used_gb" "$ram_tot_gb" "$(awk -v p="$ram_pct" 'BEGIN { print p*100 }')"

    # 3. Network Traffic (/proc/net/dev)
    local cur_rx=0
    local cur_tx=0
    local primary_nic=""
    while read -r line; do
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_-]+):[[:space:]]*([0-9]+)[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+([0-9]+) ]]; then
            local iface="${BASH_REMATCH[1]}"
            local rx="${BASH_REMATCH[2]}"
            local tx="${BASH_REMATCH[3]}"
            if [[ "$iface" != "lo" && ! "$iface" =~ (veth|docker|br-|virbr) ]]; then
                cur_rx=$(( cur_rx + rx ))
                cur_tx=$(( cur_tx + tx ))
                if [[ -z "$primary_nic" ]]; then primary_nic="$iface"; fi
            fi
        fi
    done < /proc/net/dev 2>/dev/null

    local now_ns=$(date +%s%N)
    local dt_sec=$(awk -v t1="$PREV_TIME" -v t2="$now_ns" 'BEGIN { d=(t2-t1)/1000000000; if(d<=0)d=1; printf "%.2f", d }')
    local rx_speed=0
    local tx_speed=0

    if (( FIRST_NET == 1 )); then
        FIRST_NET=0
    else
        local d_rx=$(( cur_rx - PREV_RX ))
        local d_tx=$(( cur_tx - PREV_TX ))
        if (( d_rx < 0 )); then d_rx=0; fi
        if (( d_tx < 0 )); then d_tx=0; fi
        rx_speed=$(awk -v d="$d_rx" -v t="$dt_sec" 'BEGIN { printf "%.0f", d/t }')
        tx_speed=$(awk -v d="$d_tx" -v t="$dt_sec" 'BEGIN { printf "%.0f", d/t }')
        SESSION_RX=$(( SESSION_RX + d_rx ))
        SESSION_TX=$(( SESSION_TX + d_tx ))
    fi
    PREV_RX=$cur_rx
    PREV_TX=$cur_tx
    PREV_TIME=$now_ns

    echo ""
    local nic_str=""
    if [[ -n "$primary_nic" ]]; then nic_str=" ($primary_nic)"; fi
    echo "  ${C_WHITE}NETWORK TRAFFIC & ADAPTER${nic_str}:${C_RESET}"
    printf "  ${C_GRAY}Gesamt Live:     ${C_CYAN}[In / Download] ${C_WHITE}%-12s ${C_YELLOW}[Out / Upload] ${C_WHITE}%-12s ${C_GRAY}| Session: ${C_DCYAN}In %s / Out %s${C_RESET}\n" \
        "$(format_bytes "$rx_speed")/s" "$(format_bytes "$tx_speed")/s" "$(format_bytes "$SESSION_RX")" "$(format_bytes "$SESSION_TX")"

    # 4. ACTIVE SERVICES & ENDPOINTS (via ss or netstat)
    local all_mon_ports=("${OLLAMA_PORTS[@]}" "${WATCH_PORTS[@]}" 1521 1433 50000 9088 30015 39015 5432 5437 3306 27017 6379 8123 9000 9200)
    local port_regex
    port_regex=$(IFS=\|; echo "${all_mon_ports[*]}")

    declare -A port_counts=()
    declare -A port_remotes=()
    declare -A client_pids=()

    if command -v ss &>/dev/null; then
        while read -r line; do
            # Format: ESTAB ... local_ip:local_port remote_ip:remote_port users:((name,pid=...,fd=...))
            if [[ "$line" =~ :([0-9]+)[[:space:]]+([0-9a-fA-F.:]+):([0-9]+) ]]; then
                local lport="${BASH_REMATCH[1]}"
                local rip="${BASH_REMATCH[2]}"
                local rport="${BASH_REMATCH[3]}"

                if [[ "$rport" =~ ^($port_regex)$ ]]; then
                    port_counts["$rport"]=$(( ${port_counts["$rport"]:-0} + 1 ))
                    port_remotes["$rport"]="$rip"
                    if [[ "$line" =~ pid=([0-9]+) ]]; then
                        client_pids["${BASH_REMATCH[1]}"]="$rport"
                    fi
                elif [[ "$lport" =~ ^($port_regex)$ ]]; then
                    port_counts["$lport"]=$(( ${port_counts["$lport"]:-0} + 1 ))
                    port_remotes["$lport"]="$rip"
                fi
            fi
        done < <(ss -tanp state established 2>/dev/null)
    fi

    if (( ${#port_counts[@]} > 0 )); then
        echo ""
        echo "  ${C_WHITE}ACTIVE SERVICES & ENDPOINTS (Database, Cache & AI):${C_RESET}"
        printf "  ${C_GRAY}%-8s%-24s%-32s%-14s%-28s${C_RESET}\n" "PORT" "SERVICE" "ENDPOINT / TARGET" "SOCKETS" "SCOPE / NETWORK"
        echo "${C_DGRAY}${SEP_SUB}${C_RESET}"

        for p in "${!port_counts[@]}"; do
            local svc=$(get_service_name "$p")
            local rem="${port_remotes[$p]:-127.0.0.1}"
            local scope=$(get_network_scope "$rem")
            local target_str="$rem:$p"
            if (( p == 11434 )); then target_str+=" (Ollama 1)"; fi
            if (( p == 11435 )); then target_str+=" (Ollama 2)"; fi

            printf "  ${C_YELLOW}%-8s${C_WHITE}%-24s${C_CYAN}%-32s${C_GREEN}%-14s${C_GRAY}%-28s${C_RESET}\n" \
                "$p" "$svc" "$target_str" "${port_counts[$p]} aktiv" "$scope"
        done
    fi

    # 5. LLM ENGINES & MODEL INFERENCE (Ollama REST API)
    local has_ollama=0
    for op in "${OLLAMA_PORTS[@]}"; do
        local ps_json
        ps_json=$(curl -s --max-time 1 "http://127.0.0.1:$op/api/ps" 2>/dev/null || echo "")
        if [[ -n "$ps_json" && "$ps_json" =~ \"name\": ]]; then
            if (( has_ollama == 0 )); then
                echo ""
                echo "  ${C_WHITE}LLM ENGINES & INFERENCE SPEED:${C_RESET}"
                printf "  ${C_GRAY}%-8s%-24s%-12s%-12s%-26s%-24s${C_RESET}\n" "PORT" "MODEL / ENGINE" "CONTEXT" "VRAM/RAM" "TOKENS IN (INPUT)" "TOKENS OUT (GEN)"
                echo "${C_DGRAY}${SEP_SUB}${C_RESET}"
                has_ollama=1
            fi
            local m_name=$(echo "$ps_json" | grep -o '"name":"[^"]*"' | head -n1 | cut -d'"' -f4)
            local m_vram=$(echo "$ps_json" | grep -o '"size_vram":[0-9]*' | head -n1 | cut -d: -f2)
            local vram_gb=$(awk -v b="${m_vram:-0}" 'BEGIN { printf "%.2f GB", b/1073741824 }')
            
            # Read speeds from server.log if available
            local p_speed="-"
            local g_speed="-"
            local o_log="$HOME/.ollama/server.log"
            if [[ -f "$o_log" ]]; then
                local last_eval=$(grep "eval time" "$o_log" 2>/dev/null | tail -n 2)
                if [[ "$last_eval" =~ prompt\ eval\ time.*?([0-9.]+)\ tokens\ per\ second ]]; then
                    p_speed="$(printf "%.0f Tok/s" "${BASH_REMATCH[1]}")"
                fi
                if [[ "$last_eval" =~ (?<!prompt\ )eval\ time.*?([0-9.]+)\ tokens\ per\ second ]]; then
                    g_speed="$(printf "%.1f Tok/s" "${BASH_REMATCH[1]}")"
                fi
            fi

            printf "  ${C_YELLOW}%-8s${C_WHITE}%-24s${C_GRAY}%-12s${C_MAGENTA}%-12s${C_DYELLOW}%-26s${C_CYAN}%-24s${C_RESET}\n" \
                "$op" "$m_name" "Active" "$vram_gb" "$p_speed" "$g_speed"
        fi
    done

    # 6. ACTIVE PARALLEL CLIENTS & WORKERS
    local client_count=${#client_pids[@]}
    echo ""
    printf "  ${C_WHITE}ACTIVE CLIENTS & PARALLEL WORKERS: ${C_YELLOW}[%d parallel verbunden]${C_RESET}\n" "$client_count"
    printf "  ${C_GRAY}%-9s%-16s%-32s%-14s%-18s%-17s${C_RESET}\n" "PID" "CLIENT" "TARGET ENDPOINT" "LOCAL PORT" "MEMORY" "CPU TIME"
    echo "${C_DGRAY}${SEP_SUB}${C_RESET}"

    if (( client_count == 0 )); then
        echo "  ${C_DGRAY}[Keine aktiven Client-Sockets auf den ueberwachten Ports]${C_RESET}"
    else
        for pid in "${!client_pids[@]}"; do
            if [[ -d "/proc/$pid" ]]; then
                local p_name=$(cut -d$'\0' -f1 "/proc/$pid/cmdline" 2>/dev/null | xargs basename 2>/dev/null || cat "/proc/$pid/comm" 2>/dev/null || echo "proc")
                local rss_kb=$(grep -m1 "VmRSS:" "/proc/$pid/status" 2>/dev/null | awk '{print $2}' || echo "0")
                local rss_mb=$(awk -v k="$rss_kb" 'BEGIN { printf "%.1f MB", k/1024 }')
                local target="Port ${client_pids[$pid]}"

                printf "  ${C_WHITE}%-9s${C_CYAN}%-16s${C_YELLOW}%-32s${C_GRAY}%-14s${C_WHITE}%-18s${C_GRAY}%-17s${C_RESET}\n" \
                    "$pid" "$p_name" "$target" "-" "$rss_mb" "-"
            fi
        done
    fi

    echo "${C_CYAN}${SEP_MAIN}${C_RESET}"
    printf "  ${C_DGRAY}Refresh: %.1fs  |  https://dozent.net  |  https://github.com/glueck-it/ollama-top${C_RESET}\n" "$REFRESH_SEC"
}

# --- Main Loop ---
while true; do
    render
    sleep "$REFRESH_SEC"
done
