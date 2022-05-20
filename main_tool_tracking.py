#!/usr/bin/env python3
import briteseed_process as bp
from support_functions_tool_tracking import *
import cv2

vidcap = cv2.VideoCapture(0)
cap,image = vidcap.read()

image = cv2.resize(image, (600,600))

prev_gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
# cv2.imshow("First frame", prev_gray)
# cv2.waitKey(0)

# Initialize the data pipe. Send 8 floats to MATLAB
data_pipe = bp.process("cv", 2,
                       ["xS0", "yS0", "xS1", "yS1", "xT0", "yT0", "xT1", "yT1"],
                       "ffffffff", 5, PORT=8082)
logger = bp.logger.get_logger("CV Tool Tracker")
                       
while(vidcap.isOpened()):
    ret, image_origin = vidcap.read()
    image = cv2.resize(image_origin, (600,600))


    [xT0, yT0, xT1, yT1, prev_frame] = getTool_Coordinates(image, prev_gray)
    prev_gray = prev_frame
    cv2.rectangle(image,(xT0,yT0),(xT1,yT1),[0,255,0],3)

    [xS0,yS0, xS1, yS1] = getSampleholder_Coordinates(image)

    cv2.rectangle(image,(xS0,yS0),(xS1,yS1),[0,0,0],3)

    cv2.imshow('Webcam Feed',image)

    # Send the data to the aggregator
    data_pipe.send((xS0, yS0, xS1, yS1, xT0, yT0, xT1, yT1))
    logger.debug((xS0, yS0, xS1, yS1, xT0, yT0, xT1, yT1))
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

#cap.release()
cv2.destroyAllWindows()
