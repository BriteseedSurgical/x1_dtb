import cv2
import numpy as np
import matplotlib.pyplot as plt

def getSampleholder_Coordinates(image):  
    
    # original = image.copy()
    x,y,z= np.shape(image)
    half_height = int(x/2)
    half_width  = int(y/2)
    
    gray = cv2.cvtColor(image,cv2.COLOR_BGR2GRAY)
    thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)[1]
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5,5))
    close = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel, iterations=2)
    
    horizontal_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (35,2))
    detect_horizontal = cv2.morphologyEx(close, cv2.MORPH_OPEN, horizontal_kernel, iterations=2)
    cnts = cv2.findContours(detect_horizontal, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cnts = cnts[0] if len(cnts) == 2 else cnts[1]
    
    n_points = []
    cM0 = None
    cM1 = None
    max1 = 0
    max2 = 0

    for contour in cnts:
        n_points.append(len(contour))
        if len(contour) > max1:
            max1 = len(contour)
    for contour in cnts:
        if len(contour) > max2 and len(contour) < max1:
            max2 = len(contour)

    for contour in cnts:
        if len(contour) == max1:
            cM0 = contour
        if len(contour) == max2:
            cM1 = contour

    try:
        t1 = np.mean(cM0,axis = 0)[0][1]
        t2 = np.mean(cM1,axis = 0)[0][1]

        above = None
        below = None

        if t1 < half_height:
            above = cM0
            below = cM1
        else:
            above = cM1
            below = cM0

        reduced_below = []

        above_left_top     = np.min(above,axis=0)[0] 
        above_right_bottom = np.max(above,axis=0)[0]
        below_left_top     = np.min(below,axis=0)[0]
        below_right_bottom = np.max(below,axis=0)[0]
        
        left_above  = above_left_top[0]
        right_above = above_right_bottom[0]

        for element in below:
            if element[0][0] > left_above and element[0][0] < right_above:
                reduced_below.append(element)

        if len(reduced_below) > 0:
            reduced_below = np.array(reduced_below)
            reduced_below_left_top     = np.min(reduced_below,axis=0)[0]
            reduced_below_right_bottom = np.max(reduced_below,axis=0)[0]    

        max_above = None
        min_below = None

        max_above = int(above_right_bottom[1])

        if len(reduced_below) > 0:
            min_below = int(reduced_below_left_top[1])
        else:
            min_below = int(below_left_top[1])
    except:
        left_above = 1
        max_above = 1
        right_above = 1
        min_below = 1


    # cv2.rectangle(original,(left_above,max_above),(right_above,min_below),[0,0,0],3)
    # cv2.imshow('original', original)
    return left_above,max_above,right_above,min_below


def getTool_Coordinates(image, prev_frame):
    # Converts each frame to grayscale - we previously only converted the first frame to grayscale
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    
    # Opens a new window and displays the output frame
    diff_image = cv2.absdiff(gray, prev_frame)
    
    ret,thresh_subject = cv2.threshold(diff_image, 85, 100, cv2.THRESH_TOZERO)

    kernel = np.ones((50,50),np.uint8)
    dilated = cv2.dilate(thresh_subject,kernel,iterations = 1)
    # cv2.imshow("Dilated",dilated)

    contours_tool,hierarchy = cv2.findContours(dilated.copy(),cv2.RETR_TREE,cv2.CHAIN_APPROX_NONE)

    thr = 250
    max_cntr = None
    pt1 = []
    pt2 = []
    if contours_tool == []:
        pt1 =[1,1]
        pt2 =[1,1]
    else:
        for cntr in contours_tool:
            mean = np.mean(np.array(cntr),axis =0)
            if mean[0][1] > thr :
                max_cntr = cntr
                update_cont = np.vstack(max_cntr)
                sort_cont = np.sort(update_cont, axis=0)
                pt1 = sort_cont[0]
                pt2 = sort_cont[-1]
            else:
                pt1 =[1,1]
                pt2 =[1,1]

                
    return pt1[0], pt1[1], pt2[0],pt2[1], gray