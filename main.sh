#!/usr/bin/bash

control_c() {
	echo "exiting"
	kill &DTB_PID
	kill &TRACKER_PID
	kill &CORE_PID
	exit
}

echo "Closing all ports..."
./close_ports.py
sleep 2

echo "-------- STARTING DTB SERVICE ---------"
./dtb_handler.py &
DTB_PID=$!
sleep 10
echo "-------- STARTING TRACKER SERVICE --------"
./tracker_handler.py &
TRACKER_PID=$!
sleep 10
echo "-------- STARTING CORE ---------"
./core.py &
CORE_PID=$!

read
echo "Exiting"
kill & DTB_PID
kill & TRACKER_PID
kill & CORE_PID
