#!/usr/bin/env python3

import serial
from serial.tools import list_ports

all_ports = list_ports.comports()
for port in all_ports:
	print("Closing port {}".format(port.device))
	port = serial.Serial(port=port.device, baudrate=115200,write_timeout=1.0, timeout=2.0)
	port.close()
	print(port.isOpen())
