#!/usr/bin/python3

import threading    # Threading module for creating threads
import time         # Time module for setting delays
import json         # JSON module for unpacking JSON files
import serial       # Serial module for communicating over serial
from serial.tools import list_ports # Contains tools for scanning available serial ports
import queue        # Queue module for inter-thread communications
import socket       # Socket for receiving data from MATLAB GUI
from datetime import datetime   # Time keeping
import briteseed_process as bp  # Module for sending data to MATLAB
import re           # Regex module for text matching

UDP_LISTENER_IP = "0.0.0.0" # IP addresses to listen to (0.0.0.0 = any IP address)
UDP_LISTENER_PORT = 8020    # UDP port for the DTB


"""
---------- THREAD FUNCTIONS ----------

"""



"""
Query thread function

Periodically adds a query command to the command queue
"""
def query(dtb_connected, query_request, query_received):
    while dtb_connected.is_set():
        query_request.set()
        query_received.clear()      # Set the query sent flag
        time.sleep(0.2)             # Delay for 0.2 second for 5Hz update
    logger.info("Terminating query: DTB disconnected")

"""

"""
def task_manager(dtb_connected, tasks, command_queue, movement_event, 
                 save_flag, abort_flag, job_hold, job_active):
    logger.info("Starting task manager...")
    job_active.set()
    counter = 1
    num_cmds = len(tasks['commands'])
    for command, field in zip(tasks['commands'], tasks['fields']):
        if abort_flag.is_set():
            logger.info("Code in abort state, terminating tasks now.")
            break

        if not dtb_connected.is_set():
            logger.info("Terminating tasks: DTB disconnected")
            break

        job_hold.wait()

        logger.info("Running command {} ({} of {})".format(command, counter, num_cmds))
        counter = counter + 1

        if command == "MOVETO":
            movement_event.clear()
            command_queue.put("G90 G1 X{} Y{} Z{} F{}".format(
                field['x'], field['y'], field['z'], field['f']))
            command_queue.put("G4P0")
            movement_event.wait()
        elif command == "INC":
            movement_event.clear()
            command_queue.put("G91 G1 X{} Y{} Z{} F{}".format(
                field['x'], field['y'], field['z'], field['f']))
            command_queue.put("G4P0")
            movement_event.wait()
        elif command == "WAIT":
            time.sleep(field['duration'])
        elif command == "WAITUSER":
            job_hold.clear()
        elif command == "START_SAVE":
            save_flag.set()
        elif command == "STOP_SAVE":
            save_flag.clear()
        elif command == "ZERO":
            command_queue.put("G10 L20 P2 X0Y0Z0")
            command_queue.put("G55")
    job_active.clear()
    logger.info("Tasks completed")

"""

"""
def udp_listener(dtb_connected, PORT, command_queue, movement_event, save_flag,
                 jog_hold, abort_flag, job_hold, stop_sent, job_active):
    IP = "0.0.0.0"
    logger.info("Starting UDP listener")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(2)
    logger.info("Binding to IP {} PORT {}".format(IP, PORT))
    try:
        sock.bind((IP, PORT))
        logger.info("Successfully bound UDP port")
    except:
        logger.error("Could not bind to UDP port, make sure port is not being used")
        
    command_dict = {"commands":[], "fields":[]}
    while dtb_connected.is_set():
        try:
            data, addr = sock.recvfrom(65535)
            if data.decode() == "STOP":
                logger.info("STOP received")
                abort_flag.set()
                feed_hold.set()
                stop_sent.clear()
            elif data.decode() == "RESUME":
                logger.info("RESUME received")
                abort_flag.clear()
                command_queue.put(chr(0x18))
                command_queue.put("~")
                command_queue.put("$X")
                command_queue.put("G55")
            elif data.decode() == "HOME":
                logger.info("HOME received")
                command_queue.put("$H")
            elif "JOG" in data.decode():
                coords = [float(a) for a in data.decode().split(',')[1:]];
                logger.debug("JOG received: {}".format(coords))
                jog_hold.clear()
                command_queue.put("$J=G91X{}Y{}Z{}F800".format(coords[0], coords[1], coords[2]))     
            elif data.decode() == 'HOLD':
                command_queue.put(chr(0x85))
                jog_hold.set()
                logger.debug("HOLD received")
            elif data.decode() == 'PAUSE':
                job_hold.clear()
                logger.debug("PAUSE received")
            elif data.decode() == 'CONTINUE':
                job_hold.set()
                logger.debug("CONTINUE received")
            elif data.decode() == 'ZERO':
                command_queue.put("G10 L20 P2 X0Y0Z0")
                command_queue.put("G55")
            else:
                logger.info("Received data from {}".format(addr[0]))
                try:
                    commands = json.loads(data.decode())
                    if set(command_dict.keys()) == set(commands.keys()):
                        job_hold.set()

                        task_thread = threading.Thread(target=task_manager,
                                                       args=(dtb_connected, commands,
                                                             command_queue, movement_event,
                                                             save_flag, abort_flag, job_hold,
                                                             job_active))
                        task_thread.start()
                    else:
                        pass
                    # Start the thread here
                except:
                    logger.warning("Received invalid data from UDP port: {}".format(data))
        except socket.timeout:
            pass
        time.sleep(0.01)
        
        
    logger.info("Terminating UDP: DTB disconnected")
                

"""
---------- Queues and Events ----------

command_queue is a FIFO queue that contains GCODE commands to be sent to the DTB

Events are used as flags between threads:
query_recieved: Denotes whether the acknowlegement from a query message has been received
movement_event: Set whenever a movement is currently running
dtb_connected:  Set when the DTB is connected. Cleared when the DTB is disconnected.
save_flag:      Set when commanding a save to MATLAB. Cleared when no data save requested.
jog_hold:       When set, stops the DTB from jogging
abort_flag:     Set when the user wants to stop current actions
feed_hold:      Set when the DTB is in a feed hold, stops any movement commands from being sent.

"""
command_queue = queue.Queue()       # Queue for commands to send
query_received = threading.Event()  # Threading event for whether a query acknowlegement has been received
query_request = threading.Event()
movement_event = threading.Event()  # Threading event for whether a command is actively running
dtb_connected = threading.Event()
save_flag = threading.Event()
jog_hold = threading.Event()
abort_flag = threading.Event()
feed_hold = threading.Event()
job_hold = threading.Event()
stop_sent = threading.Event()
job_active = threading.Event()
"""
---------- Data Pipe Configuration ----------

The data pipe is an object from the Briteseed Process module. The process is configured with
process name 'Dynamic Test Bed', process ID of 0, columns for x,y,z coordinates (float) and
a save flag (int), a timeout value of 5 seconds, and the core module UDP port of 8082.

We also get a logger from the data pipe. This is the standardized logger across the DTB,
tool tracker, and core. Generates a rolling log file with name "Dynamic Test Bed.log"
"""

data_pipe = bp.process("dtb", 0, ["x", "y", "z", "save", "job_status"], "fffii", 5, PORT=8082)
logger = bp.logger.get_logger("dtb")

"""
--------- Main program ----------

The main program is split into multiple parts. The whole program is enclosed in a while True loop so
that the program runs continuously. The order of events is as follows:

1) COM port configuration: The program sweeps through all available COM ports on the computer,
searching for the DTB. If the DTB is not found, the sweep begins again. Once the DTB is found, some
variables are initialized and the program advances to the next subroutine.

2) A second while True loop contains all subroutines for reading/writing data to/from the DTB. If the
DTB is disconnected or the serial communication is disrupted, this loop is broken and the program
returns to step 1.

2a) Within the inner while True loop, the first task is to read from the command queue and send the
command to the DTB.

2b) The second task is to check the serial input buffer for any data. Data is read and processed here.

"""
while True:
    expected_acks = 0                   # Counter for the expected number of acknowledgement messages
    dtb_connected.clear()
    with command_queue.mutex:
        command_queue.queue.clear()
        
    """------------------------ COM PORT CONFIGURATION SUBROUTINE -----------------------"""
    while not dtb_connected.is_set():
        dtb_dev = "/dev/ttyACM1"
        try:
            dtb_port = serial.Serial(port=dtb_dev, baudrate=115200, write_timeout=1.0)    # Set parameters for COM port
            if dtb_port.isOpen():           # If the port is already open,
                dtb_port.close()            # Close it.
            dtb_port.open()                 # Open the COM port
            logger.info("Connected to COM port {}".format(dtb_dev))
            time.sleep(2)
            dtb_port.reset_input_buffer()
            dtb_port.write("$I\n".encode())
            response = dtb_port.read_until().strip().decode()
            if response == '[VER:1.1h.20190825:]':
                dtb_port.write("$X\n".encode()) # Unlock the DTB
                dtb_port.write("G10 L20 P2 X0Y0Z0\n".encode())
                dtb_port.write("G55\n".encode())
                logger.info("Found DTB at port {}".format(dtb_dev))
                dtb_connected.set()
                dtb_port.reset_input_buffer()
                break
            else:
                logger.info("Invalid response from port {}".format(dtb_dev))
                dtb_port.close()
                continue
        except serial.serialutil.SerialException as e:
            logger.error("Could not open port {}: {}".format(dtb_dev,e))
            breakpoint()
        except serial.serialutil.SerialTimeoutException:
            logger.error("Write timeout on port {}".format(dtb_dev))
        finally:
            time.sleep(1)
#        if not dtb_connected.is_set():
#            logger.error("Could not find DTB on any port")
#           time.sleep(5) 

    query_thread = threading.Thread(target=query, args=(dtb_connected, query_request, query_received,))
    query_thread.start()    # Start the query thread
    query_received.set()    # Initialize the query_received event
    query_request.clear()   # Initialize the query_request event
    udp_thread = threading.Thread(target=udp_listener, args=(dtb_connected, UDP_LISTENER_PORT,
                                                             command_queue, movement_event,
                                                             save_flag, jog_hold, abort_flag, 
                                                             job_hold, stop_sent, job_active, ))
    udp_thread.start()

    while True:
        # Check if the command queue has anything in it
        if expected_acks == 0 or feed_hold.is_set():
            try:
                command = command_queue.get(block=False)    # Get the first command in the queue
                command = command + '\n'                    # Append a newline onto the command

                if "$J" in command and (jog_hold.is_set() or feed_hold.is_set()):
                    pass
                elif command.strip() not in ['?', '~', '$X', chr(0x18), "G55"] and feed_hold.is_set():
                    logger.info("Movement commands not allowed while feed hold is set: {}".format(command))
                else:
                    dtb_port.write(command.encode('utf-8'))     # Write the command to the DTB

                    if command.strip() == '~':		# If the command is a cycle start/resume command
                        dtb_port.write(0x18)			# Soft reset, needed to restart DTB after limit switch hit
                        with command_queue.mutex:
                            command_queue.queue.clear()		# Clear the command queue
                        time.sleep(0.5)				# Wait to make sure everything is clear
                        
                        dtb_port.reset_input_buffer()		# Flush all pending acks from the DTB
                        expected_acks = 0			# Re-initialize the number of expected acks
                        feed_hold.clear()			# Clear the feed hold flag

                    elif command.strip() == "G4P0":             # If the command is a wait command
                        pass
                    else:                                       # Otherwise
                        expected_acks = expected_acks + 1       # Increment the expected acks
                    logger.debug("COMMAND:{}".format(command.strip()))
           
                
            except serial.serialutil.SerialTimeoutException:
                break
            except queue.Empty:
                pass

        if abort_flag.is_set() and not stop_sent.is_set():
            dtb_port.write("!\n".encode())
            logger.debug("!")
            expected_acks = expected_acks + 1
            stop_sent.set()
        elif query_request.is_set():
            dtb_port.write("?\n".encode())
            logger.debug("?")
            expected_acks = expected_acks + 1
            query_request.clear()
        # Check to see if there is any serial data
        try:
            if dtb_port.in_waiting:
                response = dtb_port.read_until().strip().decode('utf-8')    # Read full line
                if not response:            # If the response is empty, do nothing
                    pass
                elif response == 'ok':      # Process the acknowledgement message
                    expected_acks = expected_acks - 1
                    if not query_received.is_set(): # Ignore the acks due to query
                        query_received.set()
                    elif expected_acks == -1:       # The counter only goes to -1 when G4P0 returns
                        if not movement_event.is_set(): # Clear the movement event flag
                            movement_event.set()
                            logger.info("Movement completed")
                        else:
                            logger.info("unexpected ack received")
                        expected_acks = 0           # Reset the counter
                    else:
                        pass
                elif response[0] == '<':    # Process the status response message
                    logger.debug("STATUS:{}".format(response))
                    coords = re.search("WPos:(-*[0-9]*\.[0-9]*),(-*[0-9]*\.[0-9]*),(-*[0-9]*\.[0-9]*)", response)
                    try:
                        data = (float(coords.group(1)), float(coords.group(2)), float(coords.group(3)), save_flag.is_set(), job_active.is_set())
                        #logger.info(data)
                    except:
                        print(response)
                        pass
                    data_pipe.send(data)
                    pass
        except serial.serialutil.SerialException as e:
            logger.error("Error in serial communication: {}".format(e))
            break

        time.sleep(0.01)

    movement_event.set()
    logger.info("Restarting process...")
