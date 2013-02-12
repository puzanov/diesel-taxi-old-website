#!/bin/sh
pkill -9 -f "taxi"
nohup ruby taxi.rb >> /tmp/taxi.log 2>&1 &
