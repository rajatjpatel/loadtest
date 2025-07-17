#!/bin/bash
# System Diagnostics Collector for RHEL 7/8 with Tomcat and PostgreSQL
# Run with sudo privileges for complete information

# Configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s)
OUTPUT_DIR="/tmp/${HOSTNAME}_diagnostics_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

# System Information Collection
system_collect() {
    echo "Collecting system information..."
    mkdir -p "$OUTPUT_DIR/system"
    
    # General system info
    uname -a > "$OUTPUT_DIR/system/uname.txt"
    cat /etc/redhat-release > "$OUTPUT_DIR/system/os-release.txt"
    uptime > "$OUTPUT_DIR/system/uptime.txt"
    free -m > "$OUTPUT_DIR/system/memory.txt"
    df -h > "$OUTPUT_DIR/system/disk_usage.txt"
    mount > "$OUTPUT_DIR/system/mounts.txt"
    lscpu > "$OUTPUT_DIR/system/cpu_info.txt"
    top -b -n 1 > "$OUTPUT_DIR/system/top.txt"
    vmstat 1 10 > "$OUTPUT_DIR/system/vmstat.txt"
    netstat -tulpn > "$OUTPUT_DIR/system/netstat.txt"
    ps auxf > "$OUTPUT_DIR/system/processes.txt"
    systemctl list-units > "$OUTPUT_DIR/system/systemd_units.txt"
    sysctl -a > "$OUTPUT_DIR/system/sysctl.txt" 2>/dev/null
    dmesg > "$OUTPUT_DIR/system/dmesg.txt"
    journalctl --since "1 day ago" > "$OUTPUT_DIR/system/journalctl.txt"
}

# Tomcat Information Collection
tomcat_collect() {
    echo "Collecting Tomcat information..."
    mkdir -p "$OUTPUT_DIR/tomcat"
    
    # Find Tomcat installations
    find / -type d -name '*tomcat*' 2>/dev/null | grep -E 'tomcat[0-9]*$' > "$OUTPUT_DIR/tomcat/installations.txt"
    
    # Process-based discovery
    ps aux | grep -E '[t]omcat|[c]atalina' > "$OUTPUT_DIR/tomcat/processes.txt"
    
    # Service discovery
    systemctl list-unit-files | grep -i tomcat > "$OUTPUT_DIR/tomcat/services.txt"
    
    # Collect info for each found Tomcat
    while read -r tomcat_dir; do
        local name=$(basename "$tomcat_dir")
        mkdir -p "$OUTPUT_DIR/tomcat/$name"
        
        # Version info
        "$tomcat_dir/bin/version.sh" > "$OUTPUT_DIR/tomcat/$name/version.txt" 2>&1
        
        # Configuration files
        cp "$tomcat_dir/conf/server.xml" "$OUTPUT_DIR/tomcat/$name/" 2>/dev/null
        cp "$tomcat_dir/conf/context.xml" "$OUTPUT_DIR/tomcat/$name/" 2>/dev/null
        cp "$tomcat_dir/conf/web.xml" "$OUTPUT_DIR/tomcat/$name/" 2>/dev/null
        cp "$tomcat_dir/conf/tomcat-users.xml" "$OUTPUT_DIR/tomcat/$name/" 2>/dev/null
        
        # Logs (last 1000 lines)
        find "$tomcat_dir/logs" -type f -name 'catalina.*.log' -exec tail -n 1000 {} \; > "$OUTPUT_DIR/tomcat/$name/catalina_logs.txt" 2>/dev/null
        find "$tomcat_dir/logs" -type f -name 'localhost_access_log*.txt' -exec tail -n 1000 {} \; > "$OUTPUT_DIR/tomcat/$name/access_logs.txt" 2>/dev/null
        
        # Thread dump
        pgrep -f "$name" | xargs -I {} jstack {} > "$OUTPUT_DIR/tomcat/$name/thread_dump.txt" 2>/dev/null
    done < "$OUTPUT_DIR/tomcat/installations.txt"
}

# PostgreSQL Information Collection
postgres_collect() {
    echo "Collecting PostgreSQL information..."
    mkdir -p "$OUTPUT_DIR/postgresql"
    
    # Find PostgreSQL installations
    find / -type d -name 'pg*' 2>/dev/null | grep -E 'pgsql|postgres' > "$OUTPUT_DIR/postgresql/installations.txt"
    
    # Service discovery
    systemctl list-unit-files | grep -i postgres > "$OUTPUT_DIR/postgresql/services.txt"
    
    # Process discovery
    ps aux | grep -E '[p]ostgres|[p]ostmaster' > "$OUTPUT_DIR/postgresql/processes.txt"
    
    # Find running cluster
    local pg_data=$(ps aux | grep -oP 'postgres.*-D *\K\S+' | head -1)
    
    if [ -n "$pg_data" ]; then
        # Configuration files
        cp "$pg_data"/postgresql.conf "$OUTPUT_DIR/postgresql/" 2>/dev/null
        cp "$pg_data"/pg_hba.conf "$OUTPUT_DIR/postgresql/" 2>/dev/null
        
        # Run as postgres user
        sudo -u postgres psql -l > "$OUTPUT_DIR/postgresql/databases.txt" 2>&1
        sudo -u postgres psql -c "SELECT * FROM pg_settings" > "$OUTPUT_DIR/postgresql/settings.txt" 2>&1
        sudo -u postgres psql -c "SELECT pg_size_pretty(pg_database_size(datname)) as size, datname FROM pg_database" \
            > "$OUTPUT_DIR/postgresql/db_sizes.txt" 2>&1
        sudo -u postgres psql -c "SELECT * FROM pg_stat_activity" > "$OUTPUT_DIR/postgresql/activity.txt" 2>&1
        sudo -u postgres psql -c "SELECT * FROM pg_stat_bgwriter" > "$OUTPUT_DIR/postgresql/bgwriter.txt" 2>&1
        sudo -u postgres psql -c "SELECT * FROM pg_stat_statements" > "$OUTPUT_DIR/postgresql/statements.txt" 2>&1
    fi
}

# Main collection
system_collect
tomcat_collect
postgres_collect

# Create archive
echo "Creating compressed archive..."
tar czf "${OUTPUT_DIR}.tar.gz" -C "${OUTPUT_DIR%/*}" "${HOSTNAME}_diagnostics_${TIMESTAMP}" 2>/dev/null

# Cleanup
rm -rf "$OUTPUT_DIR"

echo "Diagnostics collection complete!"
echo "Download the output file: ${OUTPUT_DIR}.tar.gz"
