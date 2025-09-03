#!/bin/bash

# Enhanced RHEL 7/8 Server & Database Monitoring Script
# Collects system, Tomcat, and PostgreSQL usage with background monitoring and HTML reports

#Usage Examples:
#bash# Default: Monitor for 1 hour with 1-minute performance intervals
#./enhanced_monitoring.sh

# Custom duration: Monitor for 2 hours
#./enhanced_monitoring.sh -d 7200

# Custom intervals: 30-minute monitoring with 30s performance, 2s network intervals
#./enhanced_monitoring.sh -d 1800 -p 30 -n 2

# Show help
#./enhanced_monitoring.sh --help

# Set script variables
SCRIPT_DIR="/tmp/server_report_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$SCRIPT_DIR/system_report.log"
HTML_REPORT="$SCRIPT_DIR/server_monitoring_report.html"
TOMCAT_HOME="/opt/tomcat"  # Adjust path as needed
POSTGRES_USER="postgres"   # Adjust as needed

# Background monitoring variables
PERFORMANCE_MONITOR_PID=""
NETWORK_MONITOR_PID=""
MONITORING_DURATION=3600  # Default 1 hour (in seconds)
PERFORMANCE_INTERVAL=60   # Default 1 minute intervals
NETWORK_INTERVAL=5        # Default 5 second intervals

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create report directory
mkdir -p "$SCRIPT_DIR"

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -d, --duration SECONDS    Duration for background monitoring (default: 3600)"
    echo "  -p, --perf-interval SEC   Performance monitoring interval (default: 60)"
    echo "  -n, --net-interval SEC    Network monitoring interval (default: 5)"
    echo "  -h, --help               Show this help message"
    echo
    echo "Examples:"
    echo "  $0                        # Run with default settings (1 hour)"
    echo "  $0 -d 7200               # Monitor for 2 hours"
    echo "  $0 -d 1800 -p 30 -n 2   # Monitor for 30 min, perf every 30s, network every 2s"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--duration)
                MONITORING_DURATION="$2"
                shift 2
                ;;
            -p|--perf-interval)
                PERFORMANCE_INTERVAL="$2"
                shift 2
                ;;
            -n|--net-interval)
                NETWORK_INTERVAL="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to log messages
log_message() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to create section headers
section_header() {
    echo -e "\n${BLUE}=====================================>${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}$1${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}=====================================>${NC}" | tee -a "$LOG_FILE"
}

# Function to execute command safely
safe_execute() {
    local cmd="$1"
    local output_file="$2"

    echo "Executing: $cmd" >> "$LOG_FILE"
    if eval "$cmd" > "$output_file" 2>&1; then
        echo "✓ Success: $cmd" >> "$LOG_FILE"
    else
        echo "✗ Failed: $cmd" >> "$LOG_FILE"
    fi
}

# Function to monitor performance in background
background_performance_monitor() {
    local duration=$1
    local interval=$2
    local perf_dir="$SCRIPT_DIR/performance_monitoring"
    
    mkdir -p "$perf_dir"
    
    local end_time=$(($(date +%s) + duration))
    local counter=1
    
    log_message "Starting background performance monitoring for $duration seconds with $interval second intervals"
    
    while [ $(date +%s) -lt $end_time ]; do
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        
        # CPU, Memory, and Load monitoring
        {
            echo "=== Performance Sample $counter - $(date) ==="
            echo "Load Average: $(cat /proc/loadavg)"
            echo "CPU Usage:"
            top -b -n1 | head -5
            echo "Memory Usage:"
            free -h
            echo "Disk I/O:"
            iostat -x 1 1 | tail -n +4
            echo "VM Stats:"
            vmstat 1 1 | tail -1
            echo "Process Load:"
            ps aux --sort=-%cpu | head -10
            echo "=== End Sample $counter ==="
            echo
        } >> "$perf_dir/performance_${timestamp}.txt"
        
        # System load history
        echo "$(date '+%Y-%m-%d %H:%M:%S'),$(cat /proc/loadavg | cut -d' ' -f1-3),$(free | grep Mem | awk '{printf("%.2f", $3/$2 * 100.0)}')" >> "$perf_dir/load_history.csv"
        
        counter=$((counter + 1))
        sleep $interval
    done
    
    log_message "Background performance monitoring completed"
}

# Function to monitor network usage in background
background_network_monitor() {
    local duration=$1
    local interval=$2
    local network_dir="$SCRIPT_DIR/network_monitoring"
    
    mkdir -p "$network_dir"
    
    local end_time=$(($(date +%s) + duration))
    local counter=1
    
    log_message "Starting background network monitoring for $duration seconds with $interval second intervals"
    
    # Initialize network counters file with headers
    echo "Timestamp,Interface,RX_Bytes,TX_Bytes,RX_Packets,TX_Packets,RX_Speed_Mbps,TX_Speed_Mbps" > "$network_dir/network_usage.csv"
    
    # Get initial network stats
    declare -A prev_rx_bytes prev_tx_bytes
    for interface in $(ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' ' | grep -v lo); do
        if [ -f "/sys/class/net/$interface/statistics/rx_bytes" ]; then
            prev_rx_bytes[$interface]=$(cat /sys/class/net/$interface/statistics/rx_bytes)
            prev_tx_bytes[$interface]=$(cat /sys/class/net/$interface/statistics/tx_bytes)
        fi
    done
    
    sleep $interval
    
    while [ $(date +%s) -lt $end_time ]; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Network interface statistics
        {
            echo "=== Network Sample $counter - $(date) ==="
            echo "Interface Statistics:"
            cat /proc/net/dev
            echo
            echo "Active Connections:"
            netstat -i
            echo
            echo "Socket Statistics:"
            ss -s
            echo "=== End Network Sample $counter ==="
            echo
        } >> "$network_dir/network_${timestamp//[: -]/_}.txt"
        
        # Calculate network speeds
        for interface in $(ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' ' | grep -v lo); do
            if [ -f "/sys/class/net/$interface/statistics/rx_bytes" ]; then
                local curr_rx=$(cat /sys/class/net/$interface/statistics/rx_bytes)
                local curr_tx=$(cat /sys/class/net/$interface/statistics/tx_bytes)
                local curr_rx_packets=$(cat /sys/class/net/$interface/statistics/rx_packets)
                local curr_tx_packets=$(cat /sys/class/net/$interface/statistics/tx_packets)
                
                if [[ -n ${prev_rx_bytes[$interface]} ]]; then
                    local rx_diff=$((curr_rx - prev_rx_bytes[$interface]))
                    local tx_diff=$((curr_tx - prev_tx_bytes[$interface]))
                    local rx_speed_mbps=$(echo "scale=2; $rx_diff * 8 / $interval / 1000000" | bc 2>/dev/null || echo "0")
                    local tx_speed_mbps=$(echo "scale=2; $tx_diff * 8 / $interval / 1000000" | bc 2>/dev/null || echo "0")
                    
                    echo "$timestamp,$interface,$curr_rx,$curr_tx,$curr_rx_packets,$curr_tx_packets,$rx_speed_mbps,$tx_speed_mbps" >> "$network_dir/network_usage.csv"
                fi
                
                prev_rx_bytes[$interface]=$curr_rx
                prev_tx_bytes[$interface]=$curr_tx
            fi
        done
        
        counter=$((counter + 1))
        sleep $interval
    done
    
    log_message "Background network monitoring completed"
}

# Function to generate HTML report
generate_html_report() {
    log_message "Generating HTML report..."
    
    cat > "$HTML_REPORT" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Server Monitoring Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
            color: #333;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background-color: white;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 2.5em;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .header p {
            margin: 10px 0 0 0;
            font-size: 1.2em;
            opacity: 0.9;
        }
        .nav {
            background-color: #2c3e50;
            padding: 0;
        }
        .nav ul {
            list-style: none;
            margin: 0;
            padding: 0;
            display: flex;
            flex-wrap: wrap;
        }
        .nav li {
            flex: 1;
            min-width: 120px;
        }
        .nav a {
            display: block;
            color: white;
            text-decoration: none;
            padding: 15px 20px;
            transition: background-color 0.3s;
            text-align: center;
        }
        .nav a:hover {
            background-color: #34495e;
        }
        .content {
            padding: 30px;
        }
        .section {
            margin-bottom: 40px;
            border-left: 5px solid #3498db;
            padding-left: 20px;
        }
        .section h2 {
            color: #2c3e50;
            border-bottom: 2px solid #ecf0f1;
            padding-bottom: 10px;
            margin-top: 0;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        .card {
            background-color: #f8f9fa;
            border-radius: 8px;
            padding: 20px;
            border: 1px solid #dee2e6;
            transition: transform 0.3s, box-shadow 0.3s;
        }
        .card:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
        }
        .card h3 {
            margin-top: 0;
            color: #495057;
            border-bottom: 1px solid #dee2e6;
            padding-bottom: 8px;
        }
        .metric {
            display: flex;
            justify-content: space-between;
            margin: 10px 0;
            padding: 8px;
            background-color: white;
            border-radius: 4px;
            border-left: 3px solid #28a745;
        }
        .metric.warning {
            border-left-color: #ffc107;
        }
        .metric.danger {
            border-left-color: #dc3545;
        }
        .metric-label {
            font-weight: 600;
        }
        .metric-value {
            font-family: 'Courier New', monospace;
            color: #6c757d;
        }
        .status {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: 600;
            text-transform: uppercase;
        }
        .status.running {
            background-color: #d4edda;
            color: #155724;
        }
        .status.stopped {
            background-color: #f8d7da;
            color: #721c24;
        }
        .process-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
            background-color: white;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .process-table th,
        .process-table td {
            text-align: left;
            padding: 12px;
            border-bottom: 1px solid #dee2e6;
        }
        .process-table th {
            background-color: #e9ecef;
            font-weight: 600;
            color: #495057;
        }
        .process-table tr:hover {
            background-color: #f8f9fa;
        }
        .log-container {
            background-color: #2d3748;
            color: #e2e8f0;
            padding: 20px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            max-height: 400px;
            overflow-y: auto;
            margin: 15px 0;
        }
        .chart-container {
            background-color: white;
            border-radius: 8px;
            padding: 20px;
            margin: 20px 0;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .footer {
            background-color: #2c3e50;
            color: white;
            text-align: center;
            padding: 20px;
            margin-top: 40px;
        }
        @media (max-width: 768px) {
            .nav ul {
                flex-direction: column;
            }
            .grid {
                grid-template-columns: 1fr;
            }
            .content {
                padding: 15px;
            }
        }
    </style>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.9.1/chart.min.js"></script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🖥️ Server Monitoring Report</h1>
            <p>Generated on: REPORT_TIMESTAMP</p>
            <p>Hostname: SERVER_HOSTNAME</p>
        </div>
        
        <nav class="nav">
            <ul>
                <li><a href="#overview">Overview</a></li>
                <li><a href="#performance">Performance</a></li>
                <li><a href="#services">Services</a></li>
                <li><a href="#network">Network</a></li>
                <li><a href="#database">Database</a></li>
                <li><a href="#logs">Logs</a></li>
            </ul>
        </nav>

        <div class="content">
            <!-- Overview Section -->
            <section id="overview" class="section">
                <h2>📊 System Overview</h2>
                <div class="grid">
                    <div class="card">
                        <h3>System Information</h3>
                        <div class="metric">
                            <span class="metric-label">Operating System:</span>
                            <span class="metric-value">OS_VERSION</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Kernel:</span>
                            <span class="metric-value">KERNEL_VERSION</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Uptime:</span>
                            <span class="metric-value">SYSTEM_UPTIME</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Architecture:</span>
                            <span class="metric-value">SYSTEM_ARCH</span>
                        </div>
                    </div>
                    
                    <div class="card">
                        <h3>Hardware Information</h3>
                        <div class="metric">
                            <span class="metric-label">CPU Model:</span>
                            <span class="metric-value">CPU_MODEL</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">CPU Cores:</span>
                            <span class="metric-value">CPU_CORES</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Total Memory:</span>
                            <span class="metric-value">TOTAL_MEMORY</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Total Disk:</span>
                            <span class="metric-value">TOTAL_DISK</span>
                        </div>
                    </div>
                    
                    <div class="card">
                        <h3>Current Load</h3>
                        <div class="metric LOAD_CLASS">
                            <span class="metric-label">Load Average:</span>
                            <span class="metric-value">LOAD_AVERAGE</span>
                        </div>
                        <div class="metric MEMORY_CLASS">
                            <span class="metric-label">Memory Usage:</span>
                            <span class="metric-value">MEMORY_USAGE</span>
                        </div>
                        <div class="metric DISK_CLASS">
                            <span class="metric-label">Disk Usage:</span>
                            <span class="metric-value">DISK_USAGE</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Active Users:</span>
                            <span class="metric-value">ACTIVE_USERS</span>
                        </div>
                    </div>
                </div>
            </section>

            <!-- Performance Section -->
            <section id="performance" class="section">
                <h2>⚡ Performance Monitoring</h2>
                <div class="chart-container">
                    <h3>System Load Over Time</h3>
                    <canvas id="loadChart" width="400" height="200"></canvas>
                </div>
                <div class="grid">
                    <div class="card">
                        <h3>Top CPU Processes</h3>
                        <table class="process-table">
                            <thead>
                                <tr><th>PID</th><th>User</th><th>CPU%</th><th>Command</th></tr>
                            </thead>
                            <tbody id="cpu-processes">
                                TOP_CPU_PROCESSES
                            </tbody>
                        </table>
                    </div>
                    <div class="card">
                        <h3>Top Memory Processes</h3>
                        <table class="process-table">
                            <thead>
                                <tr><th>PID</th><th>User</th><th>MEM%</th><th>Command</th></tr>
                            </thead>
                            <tbody id="memory-processes">
                                TOP_MEMORY_PROCESSES
                            </tbody>
                        </table>
                    </div>
                </div>
            </section>

            <!-- Services Section -->
            <section id="services" class="section">
                <h2>🔧 Services Status</h2>
                <div class="grid">
                    <div class="card">
                        <h3>Application Services</h3>
                        <div class="metric">
                            <span class="metric-label">Tomcat Status:</span>
                            <span class="status TOMCAT_STATUS_CLASS">TOMCAT_STATUS</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">PostgreSQL Status:</span>
                            <span class="status POSTGRESQL_STATUS_CLASS">POSTGRESQL_STATUS</span>
                        </div>
                        SERVICE_DETAILS
                    </div>
                </div>
            </section>

            <!-- Network Section -->
            <section id="network" class="section">
                <h2>🌐 Network & Connectivity</h2>
                <div class="chart-container">
                    <h3>Network Traffic Over Time</h3>
                    <canvas id="networkChart" width="400" height="200"></canvas>
                </div>
                <div class="grid">
                    <div class="card">
                        <h3>Network Interfaces</h3>
                        NETWORK_INTERFACES
                    </div>
                    <div class="card">
                        <h3>Active Connections</h3>
                        <div class="log-container" style="max-height: 200px;">
                            ACTIVE_CONNECTIONS
                        </div>
                    </div>
                </div>
            </section>

            <!-- Database Section -->
            <section id="database" class="section">
                <h2>🗄️ PostgreSQL Database</h2>
                <div class="grid">
                    <div class="card">
                        <h3>Connection Statistics</h3>
                        POSTGRESQL_CONNECTIONS
                    </div>
                    <div class="card">
                        <h3>Database Performance</h3>
                        POSTGRESQL_PERFORMANCE
                    </div>
                </div>
            </section>

            <!-- Logs Section -->
            <section id="logs" class="section">
                <h2>📋 System Logs</h2>
                <div class="card">
                    <h3>Recent System Messages</h3>
                    <div class="log-container">
                        RECENT_LOGS
                    </div>
                </div>
            </section>
        </div>

        <div class="footer">
            <p>&copy; 2024 Server Monitoring System | Generated by Enhanced Monitoring Script</p>
        </div>
    </div>

    <script>
        // Load Chart
        const loadCtx = document.getElementById('loadChart').getContext('2d');
        const loadChart = new Chart(loadCtx, {
            type: 'line',
            data: {
                labels: LOAD_CHART_LABELS,
                datasets: [{
                    label: 'Load Average',
                    data: LOAD_CHART_DATA,
                    borderColor: 'rgb(75, 192, 192)',
                    backgroundColor: 'rgba(75, 192, 192, 0.2)',
                    tension: 0.1
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    title: {
                        display: true,
                        text: 'System Load Average Over Time'
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true
                    }
                }
            }
        });

        // Network Chart
        const networkCtx = document.getElementById('networkChart').getContext('2d');
        const networkChart = new Chart(networkCtx, {
            type: 'line',
            data: {
                labels: NETWORK_CHART_LABELS,
                datasets: [
                    {
                        label: 'RX (Mbps)',
                        data: NETWORK_RX_DATA,
                        borderColor: 'rgb(54, 162, 235)',
                        backgroundColor: 'rgba(54, 162, 235, 0.2)',
                        tension: 0.1
                    },
                    {
                        label: 'TX (Mbps)',
                        data: NETWORK_TX_DATA,
                        borderColor: 'rgb(255, 99, 132)',
                        backgroundColor: 'rgba(255, 99, 132, 0.2)',
                        tension: 0.1
                    }
                ]
            },
            options: {
                responsive: true,
                plugins: {
                    title: {
                        display: true,
                        text: 'Network Traffic (RX/TX) Over Time'
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true
                    }
                }
            }
        });

        // Smooth scrolling for navigation
        document.querySelectorAll('.nav a').forEach(anchor => {
            anchor.addEventListener('click', function (e) {
                e.preventDefault();
                document.querySelector(this.getAttribute('href')).scrollIntoView({
                    behavior: 'smooth'
                });
            });
        });
    </script>
</body>
</html>
EOF

    # Replace placeholders with actual data
    sed -i "s/REPORT_TIMESTAMP/$(date)/" "$HTML_REPORT"
    sed -i "s/SERVER_HOSTNAME/$(hostname)/" "$HTML_REPORT"
    sed -i "s/OS_VERSION/$(cat /etc/redhat-release 2>/dev/null | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g')/" "$HTML_REPORT"
    sed -i "s/KERNEL_VERSION/$(uname -r)/" "$HTML_REPORT"
    sed -i "s/SYSTEM_UPTIME/$(uptime | cut -d',' -f1 | cut -d' ' -f4-)/" "$HTML_REPORT"
    sed -i "s/SYSTEM_ARCH/$(uname -m)/" "$HTML_REPORT"
    sed -i "s/CPU_MODEL/$(lscpu | grep 'Model name' | cut -d':' -f2 | sed 's/^[ \t]*//' | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g')/" "$HTML_REPORT"
    sed -i "s/CPU_CORES/$(nproc)/" "$HTML_REPORT"
    sed -i "s/TOTAL_MEMORY/$(free -h | grep '^Mem' | awk '{print $2}')/" "$HTML_REPORT"
    sed -i "s/TOTAL_DISK/$(df -h / | tail -1 | awk '{print $2}')/" "$HTML_REPORT"
    
    # System load and usage
    local load_avg=$(cat /proc/loadavg | cut -d' ' -f1-3)
    local memory_usage=$(free | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}')
    local active_users=$(who | wc -l)
    
    sed -i "s/LOAD_AVERAGE/$load_avg/" "$HTML_REPORT"
    sed -i "s/MEMORY_USAGE/$memory_usage/" "$HTML_REPORT"
    sed -i "s/DISK_USAGE/$disk_usage/" "$HTML_REPORT"
    sed -i "s/ACTIVE_USERS/$active_users/" "$HTML_REPORT"
    
    # Add CSS classes based on load
    local load_class="metric"
    local memory_class="metric"
    local disk_class="metric"
    
    # Warning thresholds
    if (( $(echo "$memory_usage" | cut -d'%' -f1 | cut -d'.' -f1) > 80 )); then
        memory_class="metric warning"
    fi
    if (( $(echo "$disk_usage" | cut -d'%' -f1) > 80 )); then
        disk_class="metric warning"
    fi
    
    sed -i "s/LOAD_CLASS/$load_class/" "$HTML_REPORT"
    sed -i "s/MEMORY_CLASS/$memory_class/" "$HTML_REPORT"
    sed -i "s/DISK_CLASS/$disk_class/" "$HTML_REPORT"
    
    # Service status
    local tomcat_status="STOPPED"
    local tomcat_status_class="stopped"
    local postgresql_status="STOPPED"
    local postgresql_status_class="stopped"
    
    if pgrep -f tomcat >/dev/null; then
        tomcat_status="RUNNING"
        tomcat_status_class="running"
    fi
    
    if systemctl is-active postgresql* &>/dev/null; then
        postgresql_status="RUNNING"
        postgresql_status_class="running"
    fi
    
    sed -i "s/TOMCAT_STATUS/$tomcat_status/" "$HTML_REPORT"
    sed -i "s/TOMCAT_STATUS_CLASS/$tomcat_status_class/" "$HTML_REPORT"
    sed -i "s/POSTGRESQL_STATUS/$postgresql_status/" "$HTML_REPORT"
    sed -i "s/POSTGRESQL_STATUS_CLASS/$postgresql_status_class/" "$HTML_REPORT"
    
    # Generate process tables
    local cpu_processes=""
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*[0-9]+ ]]; then
            local pid=$(echo $line | awk '{print $2}')
            local user=$(echo $line | awk '{print $1}')
            local cpu=$(echo $line | awk '{print $3}')
            local cmd=$(echo $line | awk '{print $11}' | cut -c1-30)
            cpu_processes+="<tr><td>$pid</td><td>$user</td><td>$cpu%</td><td>$cmd</td></tr>"
        fi
    done < <(ps aux --sort=-%cpu | head -6 | tail -5)
    
    local memory_processes=""
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*[0-9]+ ]]; then
            local pid=$(echo $line | awk '{print $2}')
            local user=$(echo $line | awk '{print $1}')
            local mem=$(echo $line | awk '{print $4}')
            local cmd=$(echo $line | awk '{print $11}' | cut -c1-30)
            memory_processes+="<tr><td>$pid</td><td>$user</td><td>$mem%</td><td>$cmd</td></tr>"
        fi
    done < <(ps aux --sort=-%mem | head -6 | tail -5)
    
    sed -i "s|TOP_CPU_PROCESSES|$cpu_processes|" "$HTML_REPORT"
    sed -i "s|TOP_MEMORY_PROCESSES|$memory_processes|" "$HTML_REPORT"
    
    # Generate chart data from monitoring files
    local chart_labels="[]"
    local load_data="[]"
    local network_labels="[]"
    local network_rx_data="[]"
    local network_tx_data="[]"
    
    # Load chart data
    if [ -f "$SCRIPT_DIR/performance_monitoring/load_history.csv" ]; then
        local labels_array=""
        local data_array=""
        while IFS=',' read -r timestamp load1 load5 load15 mem_usage; do
            if [[ $timestamp != "Timestamp" ]]; then
                local time_only=$(echo $timestamp | cut -d' ' -f2 | cut -d':' -f1,2)
                labels_array+="\"$time_only\","
                data_array+="$load1,"
            fi
        done < "$SCRIPT_DIR/performance_monitoring/load_history.csv"
        
        labels_array=${labels_array%,}
        data_array=${data_array%,}
        chart_labels="[$labels_array]"
        load_data="[$data_array]"
    fi
    
    # Network chart data
    if [ -f "$SCRIPT_DIR/network_monitoring/network_usage.csv" ]; then
        local net_labels_array=""
        local rx_data_array=""
        local tx_data_array=""
        local interface_name=""
        
        while IFS=',' read -r timestamp interface rx_bytes tx_bytes rx_packets tx_packets rx_speed tx_speed; do
            if [[ $timestamp != "Timestamp" && $interface != "lo" ]]; then
                if [[ -z $interface_name ]]; then
                    interface_name=$interface
                fi
                if [[ $interface == $interface_name ]]; then
                    local time_only=$(echo $timestamp | cut -d' ' -f2 | cut -d':' -f1,2)
                    net_labels_array+="\"$time_only\","
                    rx_data_array+="$rx_speed,"
                    tx_data_array+="$tx_speed,"
                fi
            fi
        done < "$SCRIPT_DIR/network_monitoring/network_usage.csv"
        
        net_labels_array=${net_labels_array%,}
        rx_data_array=${rx_data_array%,}
        tx_data_array=${tx_data_array%,}
        network_labels="[$net_labels_array]"
        network_rx_data="[$rx_data_array]"
        network_tx_data="[$tx_data_array]"
    fi
    
    sed -i "s|LOAD_CHART_LABELS|$chart_labels|" "$HTML_REPORT"
    sed -i "s|LOAD_CHART_DATA|$load_data|" "$HTML_REPORT"
    sed -i "s|NETWORK_CHART_LABELS|$network_labels|" "$HTML_REPORT"
    sed -i "s|NETWORK_RX_DATA|$network_rx_data|" "$HTML_REPORT"
    sed -i "s|NETWORK_TX_DATA|$network_tx_data|" "$HTML_REPORT"
    
    # Network interfaces info
    local network_interfaces=""
    while IFS= read -r line; do
        if [[ $line =~ ^[0-9]+: ]]; then
            local interface=$(echo $line | cut -d':' -f2 | awk '{print $1}')
            if [[ $interface != "lo" ]]; then
                local status=$(ip link show $interface | grep -o "state [A-Z]*" | cut -d' ' -f2)
                local ip_addr=$(ip addr show $interface | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
                network_interfaces+="<div class=\"metric\"><span class=\"metric-label\">$interface ($status):</span><span class=\"metric-value\">$ip_addr</span></div>"
            fi
        fi
    done < <(ip link show)
    
    sed -i "s|NETWORK_INTERFACES|$network_interfaces|" "$HTML_REPORT"
    
    # Active connections
    local active_connections=$(netstat -tuln | grep LISTEN | head -10 | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g' | sed 's/$/\<br\>/')
    sed -i "s|ACTIVE_CONNECTIONS|$active_connections|" "$HTML_REPORT"
    
    # PostgreSQL information
    local pg_connections=""
    local pg_performance=""
    
    if systemctl is-active postgresql* &>/dev/null; then
        local total_conn=$(sudo -u $POSTGRES_USER psql -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')
        local active_conn=$(sudo -u $POSTGRES_USER psql -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null | tr -d ' ')
        
        pg_connections+="<div class=\"metric\"><span class=\"metric-label\">Total Connections:</span><span class=\"metric-value\">${total_conn:-0}</span></div>"
        pg_connections+="<div class=\"metric\"><span class=\"metric-label\">Active Connections:</span><span class=\"metric-value\">${active_conn:-0}</span></div>"
        
        local db_count=$(sudo -u $POSTGRES_USER psql -t -c "SELECT count(*) FROM pg_database WHERE datistemplate = false;" 2>/dev/null | tr -d ' ')
        pg_performance+="<div class=\"metric\"><span class=\"metric-label\">Databases:</span><span class=\"metric-value\">${db_count:-0}</span></div>"
    else
        pg_connections="<div class=\"metric\"><span class=\"metric-label\">Status:</span><span class=\"metric-value\">Not Running</span></div>"
        pg_performance="<div class=\"metric\"><span class=\"metric-label\">Status:</span><span class=\"metric-value\">Service Stopped</span></div>"
    fi
    
    sed -i "s|POSTGRESQL_CONNECTIONS|$pg_connections|" "$HTML_REPORT"
    sed -i "s|POSTGRESQL_PERFORMANCE|$pg_performance|" "$HTML_REPORT"
    
    # Service details
    local service_details=""
    if pgrep -f tomcat >/dev/null; then
        local tomcat_pids=$(pgrep -f tomcat | tr '\n' ' ')
        service_details+="<div class=\"metric\"><span class=\"metric-label\">Tomcat PIDs:</span><span class=\"metric-value\">$tomcat_pids</span></div>"
    fi
    sed -i "s|SERVICE_DETAILS|$service_details|" "$HTML_REPORT"
    
    # Recent logs
    local recent_logs=$(journalctl --no-pager -n 20 | tail -10 | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g' | sed 's/$/\<br\>/')
    sed -i "s|RECENT_LOGS|$recent_logs|" "$HTML_REPORT"
    
    log_message "HTML report generated successfully: $HTML_REPORT"
}

# Function to stop background monitors
stop_background_monitors() {
    if [ -n "$PERFORMANCE_MONITOR_PID" ] && kill -0 "$PERFORMANCE_MONITOR_PID" 2>/dev/null; then
        kill "$PERFORMANCE_MONITOR_PID"
        log_message "Stopped performance monitor (PID: $PERFORMANCE_MONITOR_PID)"
    fi
    
    if [ -n "$NETWORK_MONITOR_PID" ] && kill -0 "$NETWORK_MONITOR_PID" 2>/dev/null; then
        kill "$NETWORK_MONITOR_PID"
        log_message "Stopped network monitor (PID: $NETWORK_MONITOR_PID)"
    fi
}

# Cleanup function
cleanup() {
    log_message "Cleaning up background processes..."
    stop_background_monitors
    wait
    log_message "Cleanup completed"
}

# Trap cleanup on exit
trap cleanup EXIT INT TERM

# Main execution starts here
parse_arguments "$@"

log_message "Starting enhanced system monitoring script..."
log_message "Report directory: $SCRIPT_DIR"
log_message "Monitoring duration: $MONITORING_DURATION seconds"
log_message "Performance interval: $PERFORMANCE_INTERVAL seconds"
log_message "Network interval: $NETWORK_INTERVAL seconds"

# Start background monitoring
section_header "STARTING BACKGROUND MONITORING"
background_performance_monitor $MONITORING_DURATION $PERFORMANCE_INTERVAL &
PERFORMANCE_MONITOR_PID=$!

background_network_monitor $MONITORING_DURATION $NETWORK_INTERVAL &
NETWORK_MONITOR_PID=$!

log_message "Background monitors started - Performance PID: $PERFORMANCE_MONITOR_PID, Network PID: $NETWORK_MONITOR_PID"

# ==========================================
# SYSTEM INFORMATION (Original functionality)
# ==========================================
section_header "SYSTEM INFORMATION"

safe_execute "hostnamectl" "$SCRIPT_DIR/hostnamectl.txt"
safe_execute "uname -a" "$SCRIPT_DIR/kernel_info.txt"
safe_execute "cat /etc/redhat-release" "$SCRIPT_DIR/os_version.txt"
safe_execute "uptime" "$SCRIPT_DIR/uptime.txt"
safe_execute "who" "$SCRIPT_DIR/current_users.txt"
safe_execute "last -10" "$SCRIPT_DIR/last_logins.txt"

safe_execute "lscpu" "$SCRIPT_DIR/cpu_info.txt"
safe_execute "free -h" "$SCRIPT_DIR/memory_info.txt"
safe_execute "df -h" "$SCRIPT_DIR/disk_usage.txt"
safe_execute "lsblk" "$SCRIPT_DIR/block_devices.txt"
safe_execute "fdisk -l" "$SCRIPT_DIR/disk_partitions.txt"

safe_execute "ip addr show" "$SCRIPT_DIR/network_interfaces.txt"
safe_execute "ip route show" "$SCRIPT_DIR/routing_table.txt"
safe_execute "netstat -tuln" "$SCRIPT_DIR/listening_ports.txt"
safe_execute "ss -tuln" "$SCRIPT_DIR/socket_stats.txt"

# ==========================================
# INITIAL PERFORMANCE SNAPSHOT
# ==========================================
section_header "INITIAL PERFORMANCE SNAPSHOT"

safe_execute "top -b -n 1" "$SCRIPT_DIR/top_snapshot.txt"
safe_execute "ps aux --sort=-%cpu | head -20" "$SCRIPT_DIR/top_cpu_processes.txt"
safe_execute "ps aux --sort=-%mem | head -20" "$SCRIPT_DIR/top_memory_processes.txt"
safe_execute "iostat -x 1 5" "$SCRIPT_DIR/io_stats.txt"
safe_execute "vmstat 1 5" "$SCRIPT_DIR/vm_stats.txt"
safe_execute "sar -u 1 5" "$SCRIPT_DIR/cpu_utilization.txt"

safe_execute "cat /proc/loadavg" "$SCRIPT_DIR/load_average.txt"
safe_execute "cat /proc/meminfo" "$SCRIPT_DIR/detailed_memory.txt"
safe_execute "cat /proc/cpuinfo" "$SCRIPT_DIR/detailed_cpu.txt"

# ==========================================
# SERVICES & SYSTEMD
# ==========================================
section_header "SERVICES & SYSTEMD"

safe_execute "systemctl status" "$SCRIPT_DIR/systemctl_status.txt"
safe_execute "systemctl list-units --type=service --state=running" "$SCRIPT_DIR/running_services.txt"
safe_execute "systemctl list-units --type=service --state=failed" "$SCRIPT_DIR/failed_services.txt"

# ==========================================
# TOMCAT MONITORING
# ==========================================
section_header "TOMCAT MONITORING"

TOMCAT_PIDS=$(pgrep -f tomcat)
if [ -n "$TOMCAT_PIDS" ]; then
    echo "Found Tomcat processes: $TOMCAT_PIDS" | tee -a "$LOG_FILE"

    safe_execute "ps -ef | grep tomcat | grep -v grep" "$SCRIPT_DIR/tomcat_processes.txt"

    for pid in $TOMCAT_PIDS; do
        safe_execute "jstat -gc $pid" "$SCRIPT_DIR/tomcat_gc_${pid}.txt"
        safe_execute "jstat -gccapacity $pid" "$SCRIPT_DIR/tomcat_gc_capacity_${pid}.txt"
        safe_execute "jmap -histo $pid | head -30" "$SCRIPT_DIR/tomcat_heap_${pid}.txt"
    done

    if [ -d "$TOMCAT_HOME" ]; then
        safe_execute "find $TOMCAT_HOME -name '*.xml' -o -name '*.properties'" "$SCRIPT_DIR/tomcat_config_files.txt"
        safe_execute "cat $TOMCAT_HOME/conf/server.xml" "$SCRIPT_DIR/tomcat_server_xml.txt"
        safe_execute "cat $TOMCAT_HOME/conf/context.xml" "$SCRIPT_DIR/tomcat_context_xml.txt"
    fi

    safe_execute "find /var/log -name '*tomcat*' -type f 2>/dev/null" "$SCRIPT_DIR/tomcat_log_files.txt"
    safe_execute "find $TOMCAT_HOME/logs -name '*.log' 2>/dev/null | head -10" "$SCRIPT_DIR/tomcat_logs_list.txt"
else
    echo "No Tomcat processes found" | tee -a "$SCRIPT_DIR/tomcat_processes.txt"
fi

# ==========================================
# POSTGRESQL MONITORING
# ==========================================
section_header "POSTGRESQL MONITORING"

if systemctl is-active postgresql &>/dev/null || systemctl is-active postgresql-* &>/dev/null; then
    log_message "PostgreSQL service is running"

    safe_execute "systemctl status postgresql*" "$SCRIPT_DIR/postgresql_service_status.txt"
    safe_execute "ps aux | grep postgres | grep -v grep" "$SCRIPT_DIR/postgresql_processes.txt"

    PG_VERSION=$(sudo -u $POSTGRES_USER psql -t -c "SELECT version();" 2>/dev/null | head -1)
    echo "PostgreSQL Version: $PG_VERSION" > "$SCRIPT_DIR/postgresql_version.txt"

    safe_execute "sudo -u $POSTGRES_USER psql -c '\l'" "$SCRIPT_DIR/postgresql_databases.txt"
    safe_execute "sudo -u $POSTGRES_USER psql -c '\du'" "$SCRIPT_DIR/postgresql_users.txt"

    PG_CONFIG_DIR=$(sudo -u $POSTGRES_USER psql -t -c "SHOW config_file;" 2>/dev/null | tr -d ' ')
    if [ -f "$PG_CONFIG_DIR" ]; then
        safe_execute "cat $PG_CONFIG_DIR" "$SCRIPT_DIR/postgresql_conf.txt"
    fi

    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT * FROM pg_stat_activity;'" "$SCRIPT_DIR/postgresql_activity.txt"
    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT * FROM pg_stat_database;'" "$SCRIPT_DIR/postgresql_db_stats.txt"
    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT * FROM pg_stat_user_tables LIMIT 20;'" "$SCRIPT_DIR/postgresql_table_stats.txt"

    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT count(*) as total_connections FROM pg_stat_activity;'" "$SCRIPT_DIR/postgresql_total_connections.txt"
    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT usename, count(*) as connections FROM pg_stat_activity WHERE state = '\''active'\'' GROUP BY usename ORDER BY connections DESC;'" "$SCRIPT_DIR/postgresql_active_users.txt"
    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT usename, count(*) as connections FROM pg_stat_activity GROUP BY usename ORDER BY connections DESC;'" "$SCRIPT_DIR/postgresql_all_user_connections.txt"
    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT usename, datname, client_addr, client_port, backend_start, state, query_start, query FROM pg_stat_activity WHERE state IS NOT NULL ORDER BY backend_start;'" "$SCRIPT_DIR/postgresql_detailed_connections.txt"
    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT datname, count(*) as connections FROM pg_stat_activity GROUP BY datname ORDER BY connections DESC;'" "$SCRIPT_DIR/postgresql_connections_per_database.txt"
    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT client_addr, count(*) as connections FROM pg_stat_activity WHERE client_addr IS NOT NULL GROUP BY client_addr ORDER BY connections DESC;'" "$SCRIPT_DIR/postgresql_connections_per_ip.txt"
    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT state, count(*) as connections FROM pg_stat_activity GROUP BY state ORDER BY connections DESC;'" "$SCRIPT_DIR/postgresql_connections_by_state.txt"

    safe_execute "find /var/log -name '*postgres*' -type f 2>/dev/null" "$SCRIPT_DIR/postgresql_log_files.txt"
else
    echo "PostgreSQL service is not running" | tee -a "$SCRIPT_DIR/postgresql_service_status.txt"
fi

# ==========================================
# LOGS & SYSTEM MESSAGES
# ==========================================
section_header "LOGS & SYSTEM MESSAGES"

safe_execute "journalctl --no-pager -n 100" "$SCRIPT_DIR/recent_journal_logs.txt"
safe_execute "tail -100 /var/log/messages" "$SCRIPT_DIR/system_messages.txt"
safe_execute "tail -100 /var/log/secure" "$SCRIPT_DIR/security_logs.txt"
safe_execute "dmesg | tail -50" "$SCRIPT_DIR/kernel_messages.txt"

# ==========================================
# INITIAL NETWORK & CONNECTIVITY
# ==========================================
section_header "INITIAL NETWORK & CONNECTIVITY"

safe_execute "netstat -i" "$SCRIPT_DIR/network_interface_stats.txt"
safe_execute "netstat -rn" "$SCRIPT_DIR/routing_table_numeric.txt"
safe_execute "iptables -L -n" "$SCRIPT_DIR/firewall_rules.txt"
safe_execute "firewall-cmd --list-all 2>/dev/null" "$SCRIPT_DIR/firewalld_config.txt"

# ==========================================
# PACKAGE INFORMATION
# ==========================================
section_header "PACKAGE INFORMATION"

safe_execute "rpm -qa | sort" "$SCRIPT_DIR/installed_packages.txt"
safe_execute "yum history | head -20" "$SCRIPT_DIR/yum_history.txt"
safe_execute "rpm -qa | grep -E '(tomcat|postgresql|java)'" "$SCRIPT_DIR/relevant_packages.txt"

# ==========================================
# WAIT FOR BACKGROUND MONITORING TO COMPLETE
# ==========================================
section_header "WAITING FOR BACKGROUND MONITORING TO COMPLETE"

log_message "Waiting for background monitoring to complete ($MONITORING_DURATION seconds)..."
log_message "Performance monitoring running with PID: $PERFORMANCE_MONITOR_PID"
log_message "Network monitoring running with PID: $NETWORK_MONITOR_PID"

# Wait for background processes
wait $PERFORMANCE_MONITOR_PID
wait $NETWORK_MONITOR_PID

log_message "Background monitoring completed successfully"

# ==========================================
# GENERATE SUMMARY REPORT
# ==========================================
section_header "GENERATING SUMMARY REPORT"

SUMMARY_FILE="$SCRIPT_DIR/SUMMARY_REPORT.txt"

{
    echo "======================================"
    echo "ENHANCED SYSTEM MONITORING SUMMARY REPORT"
    echo "Generated: $(date)"
    echo "Monitoring Duration: $MONITORING_DURATION seconds"
    echo "======================================"
    echo

    echo "SYSTEM INFORMATION:"
    echo "-------------------"
    echo "Hostname: $(hostname)"
    echo "OS Version: $(cat /etc/redhat-release 2>/dev/null || echo 'Unknown')"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime | cut -d',' -f1 | cut -d' ' -f4-)"
    echo

    echo "HARDWARE SUMMARY:"
    echo "----------------"
    echo "CPU: $(lscpu | grep 'Model name' | cut -d':' -f2 | sed 's/^[ \t]*//')"
    echo "CPU Cores: $(nproc)"
    echo "Memory: $(free -h | grep '^Mem' | awk '{print $2}')"
    echo "Disk Usage: $(df -h / | tail -1 | awk '{print $5}') of $(df -h / | tail -1 | awk '{print $2}')"
    echo

    echo "CURRENT LOAD:"
    echo "-------------"
    echo "Load Average: $(cat /proc/loadavg)"
    echo "CPU Usage: $(top -b -n1 | grep "Cpu(s)" | cut -d',' -f1 | cut -d':' -f2)"
    echo "Memory Usage: $(free | grep Mem | awk '{printf(\"%.2f%%\", $3/$2 * 100.0)}')"
    echo

    echo "SERVICES STATUS:"
    echo "---------------"
    if pgrep -f tomcat >/dev/null; then
        echo "Tomcat: RUNNING (PID: $(pgrep -f tomcat | tr '\n' ' '))"
    else
        echo "Tomcat: NOT RUNNING"
    fi

    if systemctl is-active postgresql* &>/dev/null; then
        echo "PostgreSQL: RUNNING"
        TOTAL_CONNECTIONS=$(sudo -u $POSTGRES_USER psql -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')
        ACTIVE_CONNECTIONS=$(sudo -u $POSTGRES_USER psql -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null | tr -d ' ')
        UNIQUE_USERS=$(sudo -u $POSTGRES_USER psql -t -c "SELECT count(DISTINCT usename) FROM pg_stat_activity WHERE usename IS NOT NULL;" 2>/dev/null | tr -d ' ')

        echo "  - Total Connections: ${TOTAL_CONNECTIONS:-0}"
        echo "  - Active Connections: ${ACTIVE_CONNECTIONS:-0}"
        echo "  - Unique Users Connected: ${UNIQUE_USERS:-0}"
    else
        echo "PostgreSQL: NOT RUNNING"
    fi
    echo

    echo "BACKGROUND MONITORING SUMMARY:"
    echo "-----------------------------"
    if [ -f "$SCRIPT_DIR/performance_monitoring/load_history.csv" ]; then
        local sample_count=$(tail -n +2 "$SCRIPT_DIR/performance_monitoring/load_history.csv" | wc -l)
        echo "Performance samples collected: $sample_count"
        echo "Average load during monitoring: $(tail -n +2 "$SCRIPT_DIR/performance_monitoring/load_history.csv" | awk -F',' '{sum+=$2; count++} END {if(count>0) printf("%.2f", sum/count); else print "0"}')"
    fi
    
    if [ -f "$SCRIPT_DIR/network_monitoring/network_usage.csv" ]; then
        local network_samples=$(tail -n +2 "$SCRIPT_DIR/network_monitoring/network_usage.csv" | wc -l)
        echo "Network samples collected: $network_samples"
        echo "Peak RX speed: $(tail -n +2 "$SCRIPT_DIR/network_monitoring/network_usage.csv" | awk -F',' 'BEGIN{max=0} {if($7>max) max=$7} END {printf("%.2f Mbps", max)}')"
        echo "Peak TX speed: $(tail -n +2 "$SCRIPT_DIR/network_monitoring/network_usage.csv" | awk -F',' 'BEGIN{max=0} {if($8>max) max=$8} END {printf("%.2f Mbps", max)}')"
    fi
    echo

    echo "TOP PROCESSES BY CPU:"
    echo "--------------------"
    ps aux --sort=-%cpu | head -6 | tail -5
    echo

    echo "TOP PROCESSES BY MEMORY:"
    echo "-----------------------"
    ps aux --sort=-%mem | head -6 | tail -5
    echo

    echo "DISK USAGE:"
    echo "----------"
    df -h | grep -E '^/dev'
    echo

    echo "NETWORK INTERFACES:"
    echo "-------------------"
    ip addr show | grep -E '^[0-9]+:|inet ' | grep -v '127.0.0.1'
    echo

    echo "======================================"
    echo "Detailed reports available in: $SCRIPT_DIR"
    echo "HTML report available at: $HTML_REPORT"
    echo "Performance monitoring data: $SCRIPT_DIR/performance_monitoring/"
    echo "Network monitoring data: $SCRIPT_DIR/network_monitoring/"
    echo "======================================"

} > "$SUMMARY_FILE"

# ==========================================
# GENERATE HTML REPORT
# ==========================================
section_header "GENERATING HTML REPORT"
generate_html_report

# ==========================================
# COMPLETION
# ==========================================
log_message "Enhanced system monitoring completed successfully!"
log_message "Summary report: $SUMMARY_FILE"
log_message "HTML report: $HTML_REPORT"
log_message "All detailed reports saved in: $SCRIPT_DIR"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}ENHANCED MONITORING SCRIPT COMPLETED${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Summary report:${NC} $SUMMARY_FILE"
echo -e "${YELLOW}HTML report:${NC} $HTML_REPORT"
echo -e "${YELLOW}Performance monitoring:${NC} $SCRIPT_DIR/performance_monitoring/"
echo -e "${YELLOW}Network monitoring:${NC} $SCRIPT_DIR/network_monitoring/"
echo -e "${YELLOW}Detailed reports:${NC} $SCRIPT_DIR"
echo -e "${YELLOW}Main log file:${NC} $LOG_FILE"
echo -e "${GREEN}========================================${NC}"

# Display summary
cat "$SUMMARY_FILE"

echo -e "\n${BLUE}To view the HTML report in a browser:${NC}"
echo -e "${YELLOW}firefox $HTML_REPORT${NC}"
echo -e "${YELLOW}# or copy the file to a web server${NC}"
