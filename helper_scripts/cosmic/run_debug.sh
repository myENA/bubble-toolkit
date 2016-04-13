# Run the Cosmic management server
echo "Double checking Cosmic is not already running"
killall -9 java
while timeout 1 bash -c 'cat < /dev/null > /dev/tcp/localhost/8096' 2>&1 > /dev/null; do echo "Waiting for socket to close.."; sleep 10; done

# Start Cosmic Management Server
cd /data/git/cs1/cosmic/cosmic-client
echo "Starting Cosmic"
mvnDebug -pl :cloud-client-ui jetty:run > jetty.log 2>&1 &

# Wait until it comes up
echo "Waiting for Cosmic to start"
while ! timeout 1 bash -c 'cat < /dev/null > /dev/tcp/localhost/8000' 2>&1 > /dev/null; do echo "Waiting for Mgt server to start.."; sleep 10; done

echo "Cosmic has started; debugger listening on port 8000"
