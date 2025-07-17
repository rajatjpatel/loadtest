#!/bin/bash

# This script collects system, Tomcat, and PostgreSQL usage and configuration
# details on RHEL 7/8 systems. It aims to provide a comprehensive overview
# similar to an sosreport, focusing on key performance and configuration aspects.
#
# Usage: sudo ./generate_report.sh
#
# The output will be saved to a file named 'server_db_report_YYYYMMDD_HHMMSS.txt'
# in the directory where the script is executed.

# --- Configuration Variables ---
# Define the output file name with a timestamp
REPORT_FILE="server_db_report_$(date +%Y%m%d_%H%M%S).txt"

# Default paths for Tomcat and PostgreSQL. Adjust if your installations differ.
TOMCAT_HOME="/opt/tomcat" # Common Tomcat installation path
POSTGRES_DATA_DIR="/var/lib/pgsql/data" # Common PostgreSQL data directory
POSTGRES_USER="postgres" # Default PostgreSQL superuser

# --- Helper Functions ---

# Function to print a section header to the report file
print_header() {
    echo -e "\n================================================================================" | tee -a "$REPORT_FILE"
    echo -e ">>> $1 <<<" | tee -a "$REPORT_FILE"
    echo -e "================================================================================\n" | tee -a "$REPORT_FILE"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --- Collection Functions ---

# 1. System Information
collect_system_info() {
    print_header "SYSTEM INFORMATION"

    echo "Hostname:" | tee -a "$REPORT_FILE"
    hostname -f | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    echo "OS Release Information:" | tee -a "$REPORT_FILE"
    if [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release | tee -a "$REPORT_FILE"
    else
        echo "Could not find /etc/redhat-release" | tee -a "$REPORT_FILE"
    fi
    echo "" | tee -a "$REPORT_FILE"

    echo "Kernel Version:" | tee -a "$REPORT_FILE"
    uname -a | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    echo "System Uptime:" | tee -a "$REPORT_FILE"
    uptime | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    echo "CPU Information (lscpu):" | tee -a "$REPORT_FILE"
    if command_exists lscpu; then
        lscpu | tee -a "$REPORT_FILE"
    else
        echo "lscpu command not found." | tee -a "$REPORT_FILE"
        cat /proc/cpuinfo | grep -E 'model name|cpu cores|processor' | sort -u | tee -a "$REPORT_FILE"
    fi
    echo "" | tee -a "$REPORT_FILE"

    echo "Memory Information (free -h):" | tee -a "$REPORT_FILE"
    free -h | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    echo "Disk Usage (df -h):" | tee -a "$REPORT_FILE"
    df -h | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    echo "Disk I/O Statistics (iostat -xz 1 2 - if available):" | tee -a "$REPORT_FILE"
    if command_exists iostat; then
        iostat -xz 1 2 | tee -a "$REPORT_FILE"
    else
        echo "iostat command not found. Install 'sysstat' package for this." | tee -a "$REPORT_FILE"
    fi
    echo "" | tee -a "$REPORT_FILE"

    echo "Network Interfaces (ip a):" | tee -a "$REPORT_FILE"
    ip a | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    echo "Network Statistics (netstat -s - if available):" | tee -a "$REPORT_FILE"
    if command_exists netstat; then
        netstat -s | tee -a "$REPORT_FILE"
    else
        echo "netstat command not found. Install 'net-tools' package for this." | tee -a "$REPORT_FILE"
    fi
    echo "" | tee -a "$REPORT_FILE"

    echo "Top 10 Processes by CPU (ps aux --sort=-%cpu | head -n 11):" | tee -a "$REPORT_FILE"
    ps aux --sort=-%cpu | head -n 11 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    echo "Top 10 Processes by Memory (ps aux --sort=-%mem | head -n 11):" | tee -a "$REPORT_FILE"
    ps aux --sort=-%mem | head -n 11 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    echo "Last 50 lines of /var/log/messages:" | tee -a "$REPORT_FILE"
    if [ -f /var/log/messages ]; then
        tail -n 50 /var/log/messages | tee -a "$REPORT_FILE"
    else
        echo "File /var/log/messages not found." | tee -a "$REPORT_FILE"
    fi
    echo "" | tee -a "$REPORT_FILE"

    echo "Last 50 lines of dmesg:" | tee -a "$REPORT_FILE"
    dmesg | tail -n 50 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    echo "Relevant Installed Packages (grep -E 'tomcat|postgresql|java|httpd|nginx|mariadb|kernel' /var/log/yum.log | tail -n 50):" | tee -a "$REPORT_FILE"
    if [ -f /var/log/yum.log ]; then
        grep -E 'tomcat|postgresql|java|httpd|nginx|mariadb|kernel' /var/log/yum.log | tail -n 50 | tee -a "$REPORT_FILE"
    else
        echo "File /var/log/yum.log not found." | tee -a "$REPORT_FILE"
        echo "Listing installed packages for Tomcat, PostgreSQL, Java:" | tee -a "$REPORT_FILE"
        rpm -qa | grep -E 'tomcat|postgresql|java' | tee -a "$REPORT_FILE"
    fi
    echo "" | tee -a "$REPORT_FILE"

    echo "Sysctl Parameters (sysctl -a):" | tee -a "$REPORT_FILE"
    sysctl -a | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
}

# 2. Tomcat Information
collect_tomcat_info() {
    print_header "TOMCAT INFORMATION"

    echo "Checking for Tomcat process..." | tee -a "$REPORT_FILE"
    TOMCAT_PID=$(pgrep -f "org.apache.catalina.startup.Bootstrap start")
    if [ -n "$TOMCAT_PID" ]; then
        echo "Tomcat is running with PID: $TOMCAT_PID" | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"

        echo "Tomcat Process Details (ps -fp $TOMCAT_PID):" | tee -a "$REPORT_FILE"
        ps -fp "$TOMCAT_PID" | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"

        echo "Tomcat Command Line (cat /proc/$TOMCAT_PID/cmdline):" | tee -a "$REPORT_FILE"
        cat /proc/"$TOMCAT_PID"/cmdline | tr '\0' ' ' | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"

        echo "Tomcat Open Files (lsof -p $TOMCAT_PID | head -n 50):" | tee -a "$REPORT_FILE"
        if command_exists lsof; then
            lsof -p "$TOMCAT_PID" | head -n 50 | tee -a "$REPORT_FILE"
        else
            echo "lsof command not found. Install 'lsof' package for this." | tee -a "$REPORT_FILE"
        fi
        echo "" | tee -a "$REPORT_FILE"

        echo "Java Version used by Tomcat:" | tee -a "$REPORT_FILE"
        # Find Java executable path from Tomcat process
        JAVA_HOME_PATH=$(readlink -f /proc/"$TOMCAT_PID"/exe | sed 's/\/bin\/java//')
        if [ -n "$JAVA_HOME_PATH" ]; then
            "$JAVA_HOME_PATH"/bin/java -version 2>&1 | tee -a "$REPORT_FILE"
        else
            echo "Could not determine Java HOME for Tomcat process." | tee -a "$REPORT_FILE"
        fi
        echo "" | tee -a "$REPORT_FILE"

        echo "Tomcat Home Directory (inferred from process or config):" | tee -a "$REPORT_FILE"
        if [ -d "$TOMCAT_HOME" ]; then
            echo "$TOMCAT_HOME" | tee -a "$REPORT_FILE"
        else
            echo "Tomcat home not found at $TOMCAT_HOME. Attempting to find via process." | tee -a "$REPORT_FILE"
            # Try to find CATALINA_HOME from process environment
            TOMCAT_HOME_INFERRED=$(strings /proc/"$TOMCAT_PID"/environ | grep "CATALINA_HOME=" | cut -d'=' -f2)
            if [ -n "$TOMCAT_HOME_INFERRED" ] && [ -d "$TOMCAT_HOME_INFERRED" ]; then
                TOMCAT_HOME="$TOMCAT_HOME_INFERRED"
                echo "Inferred Tomcat Home: $TOMCAT_HOME" | tee -a "$REPORT_FILE"
            else
                echo "Could not infer Tomcat Home from process environment." | tee -a "$REPORT_FILE"
            fi
        fi
        echo "" | tee -a "$REPORT_FILE"

        if [ -d "$TOMCAT_HOME" ]; then
            echo "Tomcat Version (from $TOMCAT_HOME/bin/version.sh):" | tee -a "$REPORT_FILE"
            if [ -x "$TOMCAT_HOME/bin/version.sh" ]; then
                "$TOMCAT_HOME/bin/version.sh" | tee -a "$REPORT_FILE"
            else
                echo "Tomcat version.sh script not found or not executable." | tee -a "$REPORT_FILE"
            fi
            echo "" | tee -a "$REPORT_FILE"

            echo "Tomcat Configuration Files (first 20 lines):" | tee -a "$REPORT_FILE"
            echo "--- $TOMCAT_HOME/conf/server.xml ---" | tee -a "$REPORT_FILE"
            if [ -f "$TOMCAT_HOME/conf/server.xml" ]; then
                head -n 20 "$TOMCAT_HOME/conf/server.xml" | tee -a "$REPORT_FILE"
            else
                echo "File not found: $TOMCAT_HOME/conf/server.xml" | tee -a "$REPORT_FILE"
            fi
            echo "" | tee -a "$REPORT_FILE"

            echo "--- $TOMCAT_HOME/conf/context.xml ---" | tee -a "$REPORT_FILE"
            if [ -f "$TOMCAT_HOME/conf/context.xml" ]; then
                head -n 20 "$TOMCAT_HOME/conf/context.xml" | tee -a "$REPORT_FILE"
            else
                echo "File not found: $TOMCAT_HOME/conf/context.xml" | tee -a "$REPORT_FILE"
            fi
            echo "" | tee -a "$REPORT_FILE"

            echo "--- $TOMCAT_HOME/conf/web.xml ---" | tee -a "$REPORT_FILE"
            if [ -f "$TOMCAT_HOME/conf/web.xml" ]; then
                head -n 20 "$TOMCAT_HOME/conf/web.xml" | tee -a "$REPORT_FILE"
            else
                echo "File not found: $TOMCAT_HOME/conf/web.xml" | tee -a "$REPORT_FILE"
            fi
            echo "" | tee -a "$REPORT_FILE"

            echo "Last 50 lines of Tomcat catalina.out (from $TOMCAT_HOME/logs/catalina.out):" | tee -a "$REPORT_FILE"
            if [ -f "$TOMCAT_HOME/logs/catalina.out" ]; then
                tail -n 50 "$TOMCAT_HOME/logs/catalina.out" | tee -a "$REPORT_FILE"
            else
                echo "File not found: $TOMCAT_HOME/logs/catalina.out" | tee -a "$REPORT_FILE"
            fi
            echo "" | tee -a "$REPORT_FILE"

            echo "Last 50 lines of Tomcat localhost_access_log (from $TOMCAT_HOME/logs/localhost_access_log.*.txt):" | tee -a "$REPORT_FILE"
            LATEST_ACCESS_LOG=$(ls -t "$TOMCAT_HOME"/logs/localhost_access_log.*.txt 2>/dev/null | head -n 1)
            if [ -n "$LATEST_ACCESS_LOG" ]; then
                tail -n 50 "$LATEST_ACCESS_LOG" | tee -a "$REPORT_FILE"
            else
                echo "No localhost_access_log files found in $TOMCAT_HOME/logs." | tee -a "$REPORT_FILE"
            fi
            echo "" | tee -a "$REPORT_FILE"

        else
            echo "Tomcat Home directory not found or inferred. Skipping detailed Tomcat info." | tee -a "$REPORT_FILE"
        fi

    else
        echo "Tomcat process not found." | tee -a "$REPORT_FILE"
    fi
    echo "" | tee -a "$REPORT_FILE"
}

# 3. PostgreSQL Information
collect_postgres_info() {
    print_header "POSTGRESQL INFORMATION"

    echo "Checking for PostgreSQL process..." | tee -a "$REPORT_FILE"
    POSTGRES_PID=$(pgrep -f "postgres: writer") # A common PostgreSQL process
    if [ -n "$POSTGRES_PID" ]; then
        echo "PostgreSQL is running with PID: $POSTGRES_PID" | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"

        echo "PostgreSQL Process Details (ps -fp $POSTGRES_PID):" | tee -a "$REPORT_FILE"
        ps -fp "$POSTGRES_PID" | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"

        echo "PostgreSQL Version (from psql):" | tee -a "$REPORT_FILE"
        if command_exists psql; then
            sudo -u "$POSTGRES_USER" psql -V | tee -a "$REPORT_FILE"
        else
            echo "psql command not found. Ensure PostgreSQL client tools are installed." | tee -a "$REPORT_FILE"
        fi
        echo "" | tee -a "$REPORT_FILE"

        echo "PostgreSQL Data Directory (inferred or from config):" | tee -a "$REPORT_FILE"
        if [ -d "$POSTGRES_DATA_DIR" ]; then
            echo "$POSTGRES_DATA_DIR" | tee -a "$REPORT_FILE"
        else
            echo "PostgreSQL data directory not found at $POSTGRES_DATA_DIR. Attempting to find via process." | tee -a "$REPORT_FILE"
            # Try to find data directory from process arguments
            POSTGRES_DATA_DIR_INFERRED=$(ps -fp "$POSTGRES_PID" | grep -oE "data=[^ ]+" | cut -d'=' -f2)
            if [ -n "$POSTGRES_DATA_DIR_INFERRED" ] && [ -d "$POSTGRES_DATA_DIR_INFERRED" ]; then
                POSTGRES_DATA_DIR="$POSTGRES_DATA_DIR_INFERRED"
                echo "Inferred PostgreSQL Data Directory: $POSTGRES_DATA_DIR" | tee -a "$REPORT_FILE"
            else
                echo "Could not infer PostgreSQL Data Directory from process." | tee -a "$REPORT_FILE"
            fi
        fi
        echo "" | tee -a "$REPORT_FILE"

        if [ -d "$POSTGRES_DATA_DIR" ]; then
            echo "PostgreSQL Configuration Files (first 20 lines):" | tee -a "$REPORT_FILE"
            echo "--- $POSTGRES_DATA_DIR/postgresql.conf ---" | tee -a "$REPORT_FILE"
            if [ -f "$POSTGRES_DATA_DIR/postgresql.conf" ]; then
                head -n 20 "$POSTGRES_DATA_DIR/postgresql.conf" | tee -a "$REPORT_FILE"
            else
                echo "File not found: $POSTGRES_DATA_DIR/postgresql.conf" | tee -a "$REPORT_FILE"
            fi
            echo "" | tee -a "$REPORT_FILE"

            echo "--- $POSTGRES_DATA_DIR/pg_hba.conf ---" | tee -a "$REPORT_FILE"
            if [ -f "$POSTGRES_DATA_DIR/pg_hba.conf" ]; then
                head -n 20 "$POSTGRES_DATA_DIR/pg_hba.conf" | tee -a "$REPORT_FILE"
            else
                echo "File not found: $POSTGRES_DATA_DIR/pg_hba.conf" | tee -a "$REPORT_FILE"
            fi
            echo "" | tee -a "$REPORT_FILE"

            echo "Last 50 lines of PostgreSQL Log (from $POSTGRES_DATA_DIR/pg_log/ or similar):" | tee -a "$REPORT_FILE"
            # Try common log locations
            POSTGRES_LOG_DIR=""
            if [ -d "$POSTGRES_DATA_DIR/pg_log" ]; then
                POSTGRES_LOG_DIR="$POSTGRES_DATA_DIR/pg_log"
            elif [ -d "/var/log/postgresql" ]; then
                POSTGRES_LOG_DIR="/var/log/postgresql"
            fi

            if [ -n "$POSTGRES_LOG_DIR" ]; then
                LATEST_PG_LOG=$(ls -t "$POSTGRES_LOG_DIR"/*.log 2>/dev/null | head -n 1)
                if [ -n "$LATEST_PG_LOG" ]; then
                    tail -n 50 "$LATEST_PG_LOG" | tee -a "$REPORT_FILE"
                else
                    echo "No PostgreSQL log files found in $POSTGRES_LOG_DIR." | tee -a "$REPORT_FILE"
                fi
            else
                echo "Could not find PostgreSQL log directory." | tee -a "$REPORT_FILE"
            fi
            echo "" | tee -a "$REPORT_FILE"

            if command_exists psql; then
                echo "PostgreSQL Database List:" | tee -a "$REPORT_FILE"
                sudo -u "$POSTGRES_USER" psql -l -t | tee -a "$REPORT_FILE"
                echo "" | tee -a "$REPORT_FILE"

                echo "PostgreSQL Active Connections (pg_stat_activity):" | tee -a "$REPORT_FILE"
                sudo -u "$POSTGRES_USER" psql -c "SELECT datname, usename, client_addr, state, query_start, query FROM pg_stat_activity WHERE state = 'active' ORDER BY query_start DESC;" | tee -a "$REPORT_FILE"
                echo "" | tee -a "$REPORT_FILE"

                echo "PostgreSQL Database Sizes:" | tee -a "$REPORT_FILE"
                sudo -u "$POSTGRES_USER" psql -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size DESC;" | tee -a "$REPORT_FILE"
                echo "" | tee -a "$REPORT_FILE"

                echo "PostgreSQL Long-Running Queries (if any, > 5 seconds):" | tee -a "$REPORT_FILE"
                sudo -u "$POSTGRES_USER" psql -c "SELECT pid, age(now(), query_start) AS duration, usename, datname, query FROM pg_stat_activity WHERE state = 'active' AND query_start IS NOT NULL AND age(now(), query_start) > interval '5 seconds' ORDER BY query_start DESC;" | tee -a "$REPORT_FILE"
                echo "" | tee -a "$REPORT_FILE"
            else
                echo "psql command not found. Skipping detailed PostgreSQL database info." | tee -a "$REPORT_FILE"
            fi
        else
            echo "PostgreSQL Data directory not found or inferred. Skipping detailed PostgreSQL info." | tee -a "$REPORT_FILE"
        fi

    else
        echo "PostgreSQL process not found." | tee -a "$REPORT_FILE"
    fi
    echo "" | tee -a "$REPORT_FILE"
}

# --- Main Execution ---

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges. Please run with 'sudo'."
    exit 1
fi

echo "Starting data collection..." | tee "$REPORT_FILE"
echo "Report will be saved to: $REPORT_FILE" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

collect_system_info
collect_tomcat_info
collect_postgres_info

echo "Data collection complete. Report saved to $REPORT_FILE" | tee -a "$REPORT_FILE"
echo "End of Report." | tee -a "$REPORT_FILE"

