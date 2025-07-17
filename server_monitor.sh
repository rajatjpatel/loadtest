#!/bin/bash

# RHEL 7/8 Server & Database Monitoring Script
# Collects system, Tomcat, and PostgreSQL usage and configuration details

# Set script variables
SCRIPT_DIR="/tmp/server_report_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$SCRIPT_DIR/system_report.log"
TOMCAT_HOME="/opt/tomcat"  # Adjust path as needed
POSTGRES_USER="postgres"   # Adjust as needed

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create report directory
mkdir -p "$SCRIPT_DIR"

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

log_message "Starting system monitoring script..."
log_message "Report directory: $SCRIPT_DIR"

# ==========================================
# SYSTEM INFORMATION
# ==========================================
section_header "SYSTEM INFORMATION"

# Basic system info
safe_execute "hostnamectl" "$SCRIPT_DIR/hostnamectl.txt"
safe_execute "uname -a" "$SCRIPT_DIR/kernel_info.txt"
safe_execute "cat /etc/redhat-release" "$SCRIPT_DIR/os_version.txt"
safe_execute "uptime" "$SCRIPT_DIR/uptime.txt"
safe_execute "who" "$SCRIPT_DIR/current_users.txt"
safe_execute "last -10" "$SCRIPT_DIR/last_logins.txt"

# Hardware information
safe_execute "lscpu" "$SCRIPT_DIR/cpu_info.txt"
safe_execute "free -h" "$SCRIPT_DIR/memory_info.txt"
safe_execute "df -h" "$SCRIPT_DIR/disk_usage.txt"
safe_execute "lsblk" "$SCRIPT_DIR/block_devices.txt"
safe_execute "fdisk -l" "$SCRIPT_DIR/disk_partitions.txt"

# Network information
safe_execute "ip addr show" "$SCRIPT_DIR/network_interfaces.txt"
safe_execute "ip route show" "$SCRIPT_DIR/routing_table.txt"
safe_execute "netstat -tuln" "$SCRIPT_DIR/listening_ports.txt"
safe_execute "ss -tuln" "$SCRIPT_DIR/socket_stats.txt"

# ==========================================
# SYSTEM PERFORMANCE & LOAD
# ==========================================
section_header "SYSTEM PERFORMANCE & LOAD"

# Current load and processes
safe_execute "top -b -n 1" "$SCRIPT_DIR/top_snapshot.txt"
safe_execute "ps aux --sort=-%cpu | head -20" "$SCRIPT_DIR/top_cpu_processes.txt"
safe_execute "ps aux --sort=-%mem | head -20" "$SCRIPT_DIR/top_memory_processes.txt"
safe_execute "iostat -x 1 5" "$SCRIPT_DIR/io_stats.txt"
safe_execute "vmstat 1 5" "$SCRIPT_DIR/vm_stats.txt"
safe_execute "sar -u 1 5" "$SCRIPT_DIR/cpu_utilization.txt"

# Load averages and system stats
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

# Find Tomcat processes
TOMCAT_PIDS=$(pgrep -f tomcat)
if [ -n "$TOMCAT_PIDS" ]; then
    echo "Found Tomcat processes: $TOMCAT_PIDS" | tee -a "$LOG_FILE"
    
    # Tomcat process details
    safe_execute "ps -ef | grep tomcat | grep -v grep" "$SCRIPT_DIR/tomcat_processes.txt"
    
    # Java process memory usage
    for pid in $TOMCAT_PIDS; do
        safe_execute "jstat -gc $pid" "$SCRIPT_DIR/tomcat_gc_${pid}.txt"
        safe_execute "jstat -gccapacity $pid" "$SCRIPT_DIR/tomcat_gc_capacity_${pid}.txt"
        safe_execute "jmap -histo $pid | head -30" "$SCRIPT_DIR/tomcat_heap_${pid}.txt"
    done
    
    # Tomcat configuration files
    if [ -d "$TOMCAT_HOME" ]; then
        safe_execute "find $TOMCAT_HOME -name '*.xml' -o -name '*.properties'" "$SCRIPT_DIR/tomcat_config_files.txt"
        safe_execute "cat $TOMCAT_HOME/conf/server.xml" "$SCRIPT_DIR/tomcat_server_xml.txt"
        safe_execute "cat $TOMCAT_HOME/conf/context.xml" "$SCRIPT_DIR/tomcat_context_xml.txt"
    fi
    
    # Tomcat logs
    safe_execute "find /var/log -name '*tomcat*' -type f 2>/dev/null" "$SCRIPT_DIR/tomcat_log_files.txt"
    safe_execute "find $TOMCAT_HOME/logs -name '*.log' 2>/dev/null | head -10" "$SCRIPT_DIR/tomcat_logs_list.txt"
else
    echo "No Tomcat processes found" | tee -a "$SCRIPT_DIR/tomcat_processes.txt"
fi

# ==========================================
# POSTGRESQL MONITORING
# ==========================================
section_header "POSTGRESQL MONITORING"

# Check if PostgreSQL is running
if systemctl is-active postgresql &>/dev/null || systemctl is-active postgresql-* &>/dev/null; then
    log_message "PostgreSQL service is running"
    
    # PostgreSQL service status
    safe_execute "systemctl status postgresql*" "$SCRIPT_DIR/postgresql_service_status.txt"
    
    # PostgreSQL processes
    safe_execute "ps aux | grep postgres | grep -v grep" "$SCRIPT_DIR/postgresql_processes.txt"
    
    # PostgreSQL configuration
    PG_VERSION=$(sudo -u $POSTGRES_USER psql -t -c "SELECT version();" 2>/dev/null | head -1)
    echo "PostgreSQL Version: $PG_VERSION" > "$SCRIPT_DIR/postgresql_version.txt"
    
    # Database information
    safe_execute "sudo -u $POSTGRES_USER psql -c '\l'" "$SCRIPT_DIR/postgresql_databases.txt"
    safe_execute "sudo -u $POSTGRES_USER psql -c '\du'" "$SCRIPT_DIR/postgresql_users.txt"
    
    # PostgreSQL configuration files
    PG_CONFIG_DIR=$(sudo -u $POSTGRES_USER psql -t -c "SHOW config_file;" 2>/dev/null | tr -d ' ')
    if [ -f "$PG_CONFIG_DIR" ]; then
        safe_execute "cat $PG_CONFIG_DIR" "$SCRIPT_DIR/postgresql_conf.txt"
    fi
    
    # PostgreSQL performance stats
    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT * FROM pg_stat_activity;'" "$SCRIPT_DIR/postgresql_activity.txt"
    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT * FROM pg_stat_database;'" "$SCRIPT_DIR/postgresql_db_stats.txt"
    safe_execute "sudo -u $POSTGRES_USER psql -c 'SELECT * FROM pg_stat_user_tables LIMIT 20;'" "$SCRIPT_DIR/postgresql_table_stats.txt"
    
    # PostgreSQL logs
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
# NETWORK & CONNECTIVITY
# ==========================================
section_header "NETWORK & CONNECTIVITY"

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
# GENERATE SUMMARY REPORT
# ==========================================
section_header "GENERATING SUMMARY REPORT"

SUMMARY_FILE="$SCRIPT_DIR/SUMMARY_REPORT.txt"

{
    echo "======================================"
    echo "SYSTEM MONITORING SUMMARY REPORT"
    echo "Generated: $(date)"
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
    else
        echo "PostgreSQL: NOT RUNNING"
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
    
    echo "NETWORK PORTS:"
    echo "-------------"
    netstat -tuln | grep LISTEN | head -10
    echo
    
    echo "======================================"
    echo "Detailed reports available in: $SCRIPT_DIR"
    echo "======================================"
    
} > "$SUMMARY_FILE"

# ==========================================
# COMPLETION
# ==========================================
log_message "System monitoring completed successfully!"
log_message "Summary report: $SUMMARY_FILE"
log_message "All detailed reports saved in: $SCRIPT_DIR"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}MONITORING SCRIPT COMPLETED${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Summary report:${NC} $SUMMARY_FILE"
echo -e "${YELLOW}Detailed reports:${NC} $SCRIPT_DIR"
echo -e "${YELLOW}Main log file:${NC} $LOG_FILE"
echo -e "${GREEN}========================================${NC}"

# Display summary
cat "$SUMMARY_FILE"
