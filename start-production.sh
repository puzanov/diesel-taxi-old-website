#!/bin/sh
pkill -9 -f "taxi"
nohup ruby taxi.rb production >> /tmp/taxi.log 2>&1 &
