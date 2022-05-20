This folder contains Python scripts for the data aggregator. 

---------- SCRIPTS ----------
briteseed_process.py: 			Module containing functions for sending data from a process to the aggregator core.
core.py:				Main script for the aggregator.
dtb_handler.py:				Script for connecting to, and communicating with, the DTB. Sends data back to the aggregator.
main_tool_tracking.py:			Main script for basic CV algorithm. Sends data back to the aggregator.
support_functions_tool_tracking.py: 	Support functions for the CV tool tracker.
tracker_handler.py:			Script for connecting to, and communicating with, the IMU tool tracker. Sends data back to the aggregator.

---------- DIRECTORIES ----------
logs:			Contains logs for all the handlers
process_configs:	Contains JSON configuration files for each process

---------- FILES ----------
data_hub_config.json:	JSON configuration file for the data aggregator. Contains info on the data packing order for the aggregated stream.