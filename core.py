#!/usr/bin/env python3

import socket           # Socket module for UDP communication
import threading        # Threading module to run tasks in parallel
import signal           # Signal module to catch keyboard interrupt and close gracefully
import time             # Time module to handle timing
import sys              # Sys module to exit gracefully
import os               # Os module to look for files
import json             # JSON module for unpacking/packing data
import struct           # Struct module to pack data into bytes
from datetime import datetime # Datetime for realtime date
import queue            # Queue class for passing data between threads
import briteseed_process as bp


""" --------- DATA OUTPUT THREAD ----------

This thread is responsible for periodically assembling data from each data stream, aggregating the
data into one byte array, and sending the data to MATLAB through UDP.

On each iteration, this thread will loop through all processes and collect the most recent data
from each process. The thread will also check whether the process has timed-out. The data from each
process is packed into a byte array according to the format specified by each process. Finally,
the data is sent to MATLAB via a UDP stream.
"""
def update_matlab(run):
        while run.is_set():                     # Cleared when keyboard interrupt is sent, allowing thread to close
                try:
                    matlab_msg = bytearray()        # Initialize the message byte array to send
                    for pid in pid_keys:            # Iterate through all available processes (PIDs)
                            try:
                                    data = qs[pid].get(block=False)         # Get data from the process queue. Throws exception if empty
                                    timestamps[pid] = datetime.now()        # Update the last timestamp
                                    with qs[pid].mutex:                     # Clear the queue (need to do this through the mutex)
                                            qs[pid].queue.clear()
                                    last_recv[pid] = data                   # Update the last received message for this process
                                
                            except queue.Empty:     # The get function will fault if no messages have been received
                                    # Check how long it's been since the last message has been received
                                    delta = datetime.now() - timestamps[pid]
                                    # If the time delta exceeds the timeout value, set the running flag to false
                                    if delta.total_seconds() > messages[pid]['timeout']:
                                            if is_running[pid]:
                                                    logger.info("Process '{}' has disconnected".format(messages[pid]['pname']))
                                            is_running[pid] = False
                                            data = bytearray([255]*struct.calcsize(messages[pid]['format']))      # Make an empty byte array of the appropriate size
                                    else:
                                            if not is_running[pid]:
                                                    logger.info("Process '{}' has connected".format(messages[pid]['pname']))
                                            is_running[pid] = True
                                            data = last_recv[pid]
                            finally:
                                    matlab_msg.extend(data) # Append the byte array data from each process into the larger byte array

                    logger.debug("Received {}".format(struct.unpack(combined_dict['format'], matlab_msg)))
                    matlab_sock.sendto(matlab_msg, (MATLAB_IP, MATLAB_OUT_PORT))    # Send the data to MATLAB
                    time.sleep(0.02)
                except Exception as e:
                    logger.error("{}".format(e))
        logger.info("Exiting update thread")

""" --------- DATA RECEIVE PROCESS ----------
Thread function for receiving data from multiple streams. Recieves data from UDP and places
the data into the appropriate queue. Valid UDP packets start with the process ID (PID) in
the first byte. Subsequent bytes are data.

"""
def recv_processes(run):
        while run.is_set():
                try:
                        data, addr = sock.recvfrom(1024)        # Receive any data from UDP port
                        if data[0] in messages:                 # Check first byte for PID
                                qs[data[0]].put(data[1:])       # Put the data into the appropriate queue
                        else:
                                logger.warning("Unknown process PID{}".format(data[0]))        # If PID doesn't match, ignore it
                except Exception as e:
                        logger.error("{}".format(e))
                time.sleep(0.01)
        print("Exiting receive thread")

""" Exit handler
Clears the run flag, allowing the sending and recieving threads to exit cleanly.
"""
def exit_handler(sig, frame):
        try:
                run.clear()
        except:
                pass
        sys.exit(0)



""" ---------- MAIN PROGRAM ---------- """

# Get a logger
logger = bp.logger.get_logger("core")

# IP address configurations
MATLAB_IP = "192.168.1.121"     # IP address of lab computer
MATLAB_IN_PORT = 8080           # Port for receiving data from MATLAB (unused)
MATLAB_OUT_PORT = 50256         # Port for sending data to MATLAB (arbitrary)

LOCAL_IP = "127.0.0.1"          # Localhost IP
IN_PORT = 8082                  # Data input port (processes send data here)
OUT_PORT = 8083                 # Data output port (processes recieve data here)

# Define the socket for sending data to MATLAB (SOCK_DGRAM = UDP)
logger.info("Sending data to MATLAB at IP {} PORT {}".format(MATLAB_IP, MATLAB_IN_PORT))
matlab_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

# Define the internal communication socket (SOCK_DGRAM = UDP)
logger.info("Binding to internal socket at IP {} PORT {}".format(LOCAL_IP, IN_PORT))
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

# Bind to the data input port (don't need to bind to output ports)
try:
        sock.bind((LOCAL_IP, IN_PORT))
except:
        logger.error("Failed to bind to internal socket")
sock.settimeout(1)

messages = {}   # Dictionary for containing metadata about each process (keyed by PID)
timestamps = {} # Dictionary for keeping track of the last time data was recieved from each process (keyed by PID)

# Search for process configuration files in a directory. Each process generates a JSON file which
# contains information on the fields/data structure of the corresponding message.
process_dir = "/home/pi/briteseed_data_hub/process_configs"
logger.info("Finding processes in directory {}".format(os.path.abspath(process_dir)))
files = os.listdir(process_dir) # Look for all the files in the process directory
files.sort()                    # Sort the files to make sure they always come in the same order
for fn in files:                # Look for JSON files in the configuration folder
        if fn.endswith(".json"):                        # Only process JSON files
                f = open(process_dir + "/" + fn)        # Open each file
                process_data = json.load(f)             # Load the JSON data into a dictionary
                try:
                        messages[process_data['pid']] = process_data            # Update the dictionary of all configurations
                        timestamps[process_data['pid']] = datetime.now()        # Initialize the timestamp dict
                        logger.info("Successfully loaded process '%s'" % fn.replace(".json", ""))
                except:
                        logger.warning("Failed to load process '%s'")

# Combine fields from all PIDs into one dictionary. This is useful for parsing the combined message sent to MATLAB
combined_dict = {"format":'', "names":[], "size":0}
for message in messages:
        combined_dict["format"] += messages[message]["format"]
        # Append the process name to each message name for clarity
        col_names = [messages[message]["pname"]+ "_" + name for name in messages[message]["col_names"]] 
        combined_dict["names"].extend(col_names)
combined_dict["size"] = struct.calcsize(combined_dict["format"])

# Write the combined dictionary into a JSON file. This can be read by MATLAB to correctly parse the combined data
with open("/home/pi/briteseed_data_hub/pi_config/data_hub_config.json", "w") as fn:
        json.dump(combined_dict, fn)
        
# Get a sorted list of all the keys
pid_keys = list(messages)
pid_keys.sort()

# Set up a dictionary of queues. When data is recieved from each process, the data will be stored in the corresponding queue
qs = {}         # Queue for data
last_recv = {}  # Dictionary for last recieved data
is_running = {} # Flag to note if process is running or not

for pid in messages:
        qs[pid] = queue.LifoQueue()     # LIFO queue used so that the update thread always returns the latest info
        is_running[pid] = False         # Initialize the running flags
        last_recv[pid] = bytearray(struct.calcsize(messages[pid]['format']))

# Get things started
signal.signal(signal.SIGINT, exit_handler)      # Tie the keyboard interrupt signal to the exit handler function
run = threading.Event()                         # Initialize the running flag. When this is cleared, the threads will exit
run.set()
update_thread = threading.Thread(target=update_matlab, args=(run,))     # Define the update (sending) thread
recv_thread = threading.Thread(target=recv_processes, args=(run,))      # Define the recieving thread

update_thread.start()   # Start the update thread
recv_thread.start()     # Start the recieving thread
while True:             # While True loop to block execution on this shell.
    time.sleep(1)
