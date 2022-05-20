#!/usr/bin/env python3

import serial
from serial.tools import list_ports
import briteseed_process as bp
import time

data_pipe = bp.process("imu", 1, ["x","y","z","vessel_present"], "fffi", 5, PORT=8082)
logger = bp.logger.get_logger("IMU Tool Tracker")

while True:
    tracker_connected = False
    while not tracker_connected:
        tracker_dev = "/dev/ttyACM0"
        try:
            tracker_port = serial.Serial(port=tracker_dev, baudrate=115200,
                                         write_timeout = 1.0, timeout = 2.0)
            if tracker_port.isOpen():
                tracker_port.close()
            tracker_port.open()
            logger.info("Connected to COM port {}".format(tracker_dev))
            time.sleep(2)
            tracker_port.reset_input_buffer()
            tracker_port.write("$I".encode())
            response = tracker_port.read_until().strip().decode()
            if response == '[BRITESEED TOOL TRACKER]':
                tracker_connected = True
                logger.info("Found tool tracker at port {}".format(tracker_dev))
                break
            else:
                logger.info("Invalid response from port {}: {}".format(tracker_dev, response))
                tracker_port.close()
                continue
        except serial.serialutil.SerialException:
            logger.error("Could not open port {}".format(tracker_dev))
        except serial.serialutil.SerialTimeoutException as e:
            logger.error("Timeout on port {}: {}".format(tracker_dev, e))
        finally:
            time.sleep(1)

        if not tracker_connected:
            logger.error("Could not find tool tracker on any port")

    while tracker_connected:
        try:
            data = tracker_port.read_until().strip().decode()
            if not data:
                continue
            logger.info("Received data: {}".format(data))
            data = [float(num) for num in data.split(',')]
            data_pipe.send((data[0], data[1], data[2], int(data[3])))
        except serial.serialutil.SerialException as e:
            logger.error("Error in serial communication: {}".format(e))
            tracker_connected = False
        time.sleep(0.01)
