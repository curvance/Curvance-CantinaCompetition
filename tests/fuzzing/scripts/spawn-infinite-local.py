#!/usr/bin/python3

import time 
import psutil
import os

def checkIfProcessRunning(processName):
    '''
    Check if there is any running process that contains the given name processName.
    '''
    #Iterate over the all the running process
    for proc in psutil.process_iter():
        try:
            # Check if process name contains the given name string.
            if processName.lower() in proc.name().lower():
                return True
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            pass
    return False;    

while True:
    if(not checkIfProcessRunning("medusa")): 
        os.system("make mc")

    time.sleep(10) #make function to sleep for 10 seconds
    

