#!/bin/sh
# KIBERmine Server Launch Script
# Optimized JVM settings for Mohist 1.20.1 with G1GC

cd "$(dirname "$(readlink -fn "$0")")"

# Find the server JAR (supports version updates)
JAR_FILE=$(ls mohist-1.20.1-*.jar 2>/dev/null | head -1)
if [ -z "$JAR_FILE" ]; then
    echo "ERROR: Server JAR not found!"
    exit 1
fi

# Memory settings
MIN_RAM="4G"
MAX_RAM="6G"

# Launch with optimized G1GC settings
exec java \
    -Xms${MIN_RAM} \
    -Xmx${MAX_RAM} \
    -XX:+UseG1GC \
    -XX:MaxGCPauseMillis=200 \
    -XX:+ParallelRefProcEnabled \
    -XX:G1HeapRegionSize=16M \
    -XX:G1ReservePercent=20 \
    -XX:G1HeapWastePercent=5 \
    -XX:+DisableExplicitGC \
    -XX:+UseStringDeduplication \
    -XX:+UnlockExperimentalVMOptions \
    -XX:+AlwaysPreTouch \
    -Xss256k \
    -jar "$JAR_FILE" nogui