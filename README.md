# loadtest
Simple load test on server 
# Default: Monitor for 1 hour with 1-minute performance intervals
./enhanced_monitoring.sh

# Custom duration: Monitor for 2 hours
./enhanced_monitoring.sh -d 7200

# Custom intervals: 30-minute monitoring with 30s performance, 2s network intervals
./enhanced_monitoring.sh -d 1800 -p 30 -n 2

# Show help
./enhanced_monitoring.sh --help
