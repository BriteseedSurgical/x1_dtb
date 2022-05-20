#!/usr/bin/env python3

import json     # Import JSON module for saving configuration dictionary
import socket   # Import socket module for sending/receiving data
import os       # Import OS module for file handling
import struct   # Import struct module for packing data
import logging
from logging.handlers import RotatingFileHandler

class process:
        """
        Process class for Briteseed data hub. Communicates with core module
        to send data to the MATLAB GUI.

        Attributes
        ----------
        config_dict : dict
                Dictionary containing process details
        IP : str
                String for core IP address
        PORT : int
                Integer for core input port
        sock : socket.socket
                UDP socket
        """

        def __init__(self, pname, pid, col_names, format, timeout, IP="127.0.0.1", PORT=50000):
                """
                Initialization function for process class

                Parameters
                ----------
                pname : str
                        Process name
                pid : int
                        Process ID number (0-255)
                col_names : (str)
                        Tuple of column names for saving to MATLAB
                format : str
                        Format string for variables to save, following struct convention
                        Only supports h, H, i, I, f, d
                timeout : float
                        Timeout value for this process in seconds
                IP : str, optional
                        IP address of core module (default "127.0,0,1")
                PORT : int, optional
                        UDP port of core module (default "50000")
                """
                # Pack the configuration dictionary
                self.config_dict = {
                        "pname":pname,
                        "pid":pid,
                        "col_names":col_names,
                        "format":format,
                        "timeout":timeout}
                # Set the IP and PORT values
                self.IP = IP
                self.PORT = PORT

                # Save the configuration file so that it can be shared with the core module
                with open("/home/pi/briteseed_data_hub/process_configs/"+f'{pid:03d}'+pname+".json", "w") as fn:
                        json.dump(self.config_dict, fn)

                # Initialize a UDP socket
                self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        def send(self, data):
                """
                Sending function. Sends "data" to core module

                Parameters
                ----------
                data : tuple
                        Tuple of data for sending to MATLAB. Must follow order and
                        convention as specified in the format string
                """
                # Pack the data into a buffer, appending the PID, according to
                # the given format string
                out_buffer = struct.pack("<B"+self.config_dict["format"], self.config_dict["pid"], *data)

                # Send the data over UDP
                self.sock.sendto(out_buffer, (self.IP, self.PORT))

class logger:
        def get_logger(name):
                logger = logging.getLogger(name)
                logger.setLevel(logging.DEBUG)

                ch = logging.StreamHandler()
                ch.setLevel(logging.INFO)

                fh = RotatingFileHandler('/home/pi/briteseed_data_hub/logs/'+name+'.log', maxBytes = 500000, backupCount=10)
                fh.setLevel(logging.DEBUG)

                formatter = logging.Formatter('%(asctime)s:%(levelname)s:%(message)s')
                ch.setFormatter(formatter)
                fh.setFormatter(formatter)

                logger.addHandler(ch)
                logger.addHandler(fh)
                return logger

