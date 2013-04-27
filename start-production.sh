#!/bin/sh
pkill -9 -f "diesel"
nohup ruby diesel.rb production >> /tmp/diesel.log 2>&1 &
