#!/bin/sh
set -e
ORR_NEW_MAP_FLAG_FILE="/opt/orr/flags/$ORR_NEW_MAP_FLAG_FILE"
ORR_GRAPH_READY_FLAG_FILE="/opt/orr/flags/$ORR_GRAPH_READY_FLAG_FILE"
ORR_PID=""


with_rebuilding() {
    REBUILDING=1
    "$@"
    REBUILDING=0
}


orr_echo(){
    echo "[ORR-WATCHDOG] $1"
}


download_osm() { 
    DEST_PATH="./poland-latest.osm.pbf"

    orr_echo "Downloading the latest OSM map of Poland to $DEST_PATH..."
    curl -fsSL "$OSM_POLAND_URL" -o "$DEST_PATH"

    echo "$DEST_PATH"
}


build_railway_graph() {
    DOWNLOADED_OSM=$(download_osm)

    java $JAVA_OPTS -jar app.jar import -o graph-cache/graph-build config.yml
    mv ./graph-cache/graph-build/* ./graph-cache/graph-ready/
    orr_echo "Railway graph rebuild complete. Serving new graph..."
    touch "$ORR_GRAPH_READY_FLAG_FILE"
    rm -f "$ORR_NEW_MAP_FLAG_FILE"

    if [ -f "$DOWNLOADED_OSM" ]; then
        orr_echo "Deleting OSM file $DOWNLOADED_OSM..."
        rm -f "$DOWNLOADED_OSM"
    fi
}


serve_transit_graph() {
    PORT=8080
    
    while [ "${REBUILDING:-0}" -eq 1 ]; do
        orr_echo "Graph is rebuilding, waiting..."
        sleep 5
    done
    
    if [ -n "$ORR_PID" ] && kill -0 "$ORR_PID" 2>/dev/null; then
        orr_echo "Stopping old ORR Server (PID: $ORR_PID)..."
        kill -15 "$ORR_PID"
        sleep 5
        if kill -0 "$ORR_PID" 2>/dev/null; then
            orr_echo "Force killing..."
            kill -9 "$ORR_PID"
            sleep 1
        fi
    fi
    
    PID=$(lsof -ti tcp:$PORT || true)
    if [ -n "$PID" ]; then
        orr_echo "Port $PORT is occupied by PID $PID. Killing..."
        kill -15 $PID 2>/dev/null || true
        sleep 2
        kill -9 $PID 2>/dev/null || true
        sleep 1
    fi
    
    orr_echo "Starting ORR Server on port $PORT..."
    java $JAVA_OPTS -jar app.jar serve config.yml &
    ORR_PID=$!
    
    rm -f "$ORR_GRAPH_READY_FLAG_FILE"
    orr_echo "ORR Server started with PID: $ORR_PID"
}



orr_echo "Watchdog started!"
trap 'echo "Shutting down..."; [ -n "$ORR_PID" ] && kill $ORR_PID 2>/dev/null; exit 0' TERM INT

while true; do
    if [ -n "$ORR_PID" ] && ! kill -0 "$ORR_PID" 2>/dev/null; then
        orr_echo "ORR Server (PID: $ORR_PID) stopped unexpectedly"
        ORR_PID=""
    fi
    
    if [ -f "$ORR_NEW_MAP_FLAG_FILE" ]; then
        orr_echo "Detected MAP flag. Rebuilding railway graph..."
        with_rebuilding build_railway_graph
    fi
    
    if [ -f "$ORR_GRAPH_READY_FLAG_FILE" ]; then
        orr_echo "Detected new graph ready flag. Starting ORR Server..."
        serve_transit_graph
    fi
    
    sleep 10
done