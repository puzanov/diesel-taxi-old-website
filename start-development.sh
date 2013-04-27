#!/bin/sh
pkill -9 -f "diesel"
nohup ruby diesel.rb >> /tmp/taxi.log 2>&1 &
