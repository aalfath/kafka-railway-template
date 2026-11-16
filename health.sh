#!/bin/sh
# Answers one HTTP request on stdin/stdout (run by busybox `nc -lk -e`).
# 200 once the broker has started and its SCRAM user is set, otherwise 503.
read -r _line
if [ -f /tmp/kafka-ready ] && nc -z -w 2 127.0.0.1 9092 2>/dev/null; then
  body='{"status":"ok"}'; status='200 OK'
else
  body='{"status":"starting"}'; status='503 Service Unavailable'
fi
printf 'HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' "$status" "${#body}" "$body"
