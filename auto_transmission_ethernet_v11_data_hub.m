function varargout = auto_transmission_ethernet_v9_data_hub(varargin)
% AUTO_TRANSMISSION_GUI_V1 MATLAB code for auto_transmission_gui_v1.fig
%      AUTO_TRANSMISSION_GUI_V1, by itself, creates a new AUTO_TRANSMISSION_GUI_V1 or raises the existing
%      singleton*.
%
%      H = AUTO_TRANSMISSION_GUI_V1 returns the handle to a new AUTO_TRANSMISSION_GUI_V1 or the handle to
%      the existing singleton*.
%
%      AUTO_TRANSMISSION_GUI_V1('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in AUTO_TRANSMISSION_GUI_V1.M with the given input arguments.
%
%      AUTO_TRANSMISSION_GUI_V1('Property','Value',...) creates a new AUTO_TRANSMISSION_GUI_V1 or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before auto_transmission_gui_v1_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to auto_transmission_gui_v1_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help auto_transmission_gui_v1

% Last Modified by GUIDE v2.5 28-Oct-2021 12:15:19

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @auto_transmission_gui_v1_OpeningFcn, ...
                   'gui_OutputFcn',  @auto_transmission_gui_v1_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT4

% --- Executes just before auto_transmission_gui_v1 is made visible.
function auto_transmission_gui_v1_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to auto_transmission_gui_v1 (see VARARGIN)
%% Loading models
evalin('base','clc');
evalin('base','warning off');

addpath( '/media/briteseed_data/BRIMSTONE/Working Directory')
addpath( '/media/briteseed_data/BRIMSTONE/Working Directory/DTB');

settings.bvTissueTimeNet = evalin('base','net_v16');
settings.vgg = evalin('base','net_bvt_m_v5');

try
    params = evalin('base','params');
catch
    params = [];
end

nargin = numel(varargin);
if (nargin == 0)
  settings.N_channel = 1;
elseif (nargin == 1)
  if ~isnumeric(varargin{1}) || ~any(varargin{1} == 1:2)
    error('The input argument must be an interger between 1 and 2');
  end
  settings.N_channel = varargin{1};
else
  error('Can only have zero or one input argument.');
end
%% UDP Ports
remotePort =60000;
remotePort2=60002 ;
localPort=60001;
localPort2=60003;

% Issue a close in case didn't exit program cleanly during previous instance.
instrobjs = instrfind('Type', 'udp', 'Status', 'open');
for i=1:length(instrobjs)
    fclose(instrobjs(i));
end

% Configure port and establish the callback function used when data 
% is ready.

serialPort = udp('192.168.1.10', remotePort, 'LocalPort', localPort);
serialPort.ReadAsyncMode = 'manual';
serialPort.OutputBufferSize = 40;
serialPort.InputBufferSize = 5130000;
serialPort.BytesAvailableFcnCount = 513;
serialPort.BytesAvailableFcnMode = 'byte';
serialPort.BytesAvailableFcn = {@serial_full_callback, hObject, handles};

% Configure second UDP Ethernet Port for the GUI Overlay
udpPort = udp('192.168.1.20', remotePort2, 'LocalPort', localPort2);
udpPort.OutputBufferSize = 250;

% Compute some synchronization header information.
settings.bufferSize = serialPort.BytesAvailableFcnCount;
settings.headerSize = 1;
settings.N_cmos_image = 247;
settings.h = ones(1,8)./8;
settings.imagebuff = zeros(settings.N_cmos_image,1);

%% Saving Real Time BV Size Data and BVT Decision 
columns_rt = 'LED1, LED2, LED3, LED4, LED5, LED6,';

for i = 1:247
    columns_rt = [columns_rt 'DC_Sensor#' num2str(i) ',']; 
end

% REMOVED NEW LINE FROM HERE
columns_rt = [columns_rt 'LED-Cycle, dipFound, Dips-present, adaptdone, BSA-adapt, refdipminloc, BVT buffer, BVT decision, Colorbar, Flagcolor, SE buffer, DL-size, ML-size, FPGA_Counter, Jaw Angle'];

dataType_rt = '%d,%d,%d,%d,%d,%d,'; 
dataType_rt = [dataType_rt repmat('%f,',1,247)];
dataType_rt = [dataType_rt '%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %f, %f, %d, %d'];
settings.bvcolumn = columns_rt;
settings.bvdtype = dataType_rt;

settings.Date = evalin('base', 'date');
settings.Month = evalin('base', 'clock');

settings.rtfolder = [settings.Date(8:end) num2str(settings.Month(1,2)) ...
    settings.Date(1:2) '_realtime_data'];

settings.rtfolderName = [settings.Date(8:end) num2str(settings.Month(1,2)) ...
    settings.Date(1:2) '_Automation'];

if exist(settings.rtfolderName,'dir')~=7
    rtfilenum = 1;
else
    oldFolder = cd(settings.rtfolderName);
    rtfilenum = numel(dir('*.csv'))+1;
    cd(oldFolder);
end
settings.rtfilenum = rtfilenum;
settings.rtcount = 0;
%% Variables used for intra/inter-module Communication
settings.DC = zeros(settings.N_cmos_image,1); % Unsmoothened dc signal for saving dc profile

settings.dips = []; % dips varibale from detect dips

settings.bufferData = zeros(settings.N_cmos_image,9); % Buffer for AC profile
settings.nndata=zeros(9,250); % Buffer for Deeplearning Size estimation Network
settings.vggsize = 0;
settings.count1 = 1; % Counter for AC bufferData

settings.dcMLsize = 0; 
settings.saveData = 0; % to trigger datasaving
settings.bvsizeGPD = []; % Variable for printing the size in bvbar

settings.bvSizeReady = 0; % to invoke bvbar
settings.I = zeros(size(settings.DC)); % for generating the red bar

settings.tempAC = zeros(settings.N_cmos_image,1); % for tracking ac plots
settings.meanLoc = 125; %DC profile

settings.datasavecount = 0; % Data save counter- why instead of line 325? no 326-327

settings.ledI = zeros(1,6); %Variable to store LEDi
settings.inds = [1,2,3,4,5,6]; % LED indices 
settings.save_data_time = 10;

% LED Adapt Variables
[settings.maxI, settings.tempMaxI] = deal(9000); 
[settings.minI, settings.tempMinI] = deal(100);

%BVT Related Flags
settings.bvTissueCount = 0; % BVT data buffer counter
settings.bvTissueData = zeros(27,250); % BVT Buffer
settings.bvDetected =0;
settings.colorflag = 'white';
settings.flag_buff =zeros(1,3);
settings.bv3=0;

% Variables to check if the DC profile is saturated for a while or LEDi is
% set to zero
settings.startCycle = 0;
settings.dipFound = 0;
settings.adaptdone = 0;

settings.baselineadapt = 0; % variable for shuffling between baseline adapt process. 
% If it is 1 baselineadapt has been initiated else it is done or not invoked 
settings.adaptcount = 1; % Counter that keeps track before LEDi are changed during BSA

settings.baseline = 2000; 
settings.baselineRange = [1990,2010]; 

%pump reading
settings.pbuff=ones(1,10);
settings.buffcount=1;
settings.bufflength=10;
settings.pumpcount = 1;
settings.pumpreading = zeros(1,100);
settings.pumpmax = -1000;
settings.pumpmin = 1000;

%Overlay related buffer
settings.overlaybuffer = ones(4,247);
settings.overlay_count1=1;
settings.datatosend= ones(1,247); 
settings.bvDetected_buffer= zeros(4,1);
settings.toOverlayBoard = uint8(zeros(udpPort.OutputBufferSize,1));
settings.toOverlayBoard(1) = 255;
%% Angle sensor mapping coefficients
% USE THESE for meddux handheld
settings.angle_coeffs = [1.09410084751401e-05,-0.0454385062540506, 48.3045312178481];

% use with meddux benchtop
% settings.angle_coeffs = [ -3.14556002057478e-07 , 0.00225600873483697 , -5.22588721966790 , 3935.93542142933];
%% Objects that the serial port callback routine can manipulate.
% PLotting variabels and axes set
% DC profile axes
h_dc_shadow = findobj('Tag','dcPlotAxes');
settings.h_dc_shadow = plot(h_dc_shadow(1),1:settings.N_cmos_image,...
    [zeros(settings.N_cmos_image,1), zeros(settings.N_cmos_image,1), ...
    zeros(settings.N_cmos_image,1), zeros(settings.N_cmos_image,1), ...
    zeros(settings.N_cmos_image,1)],'LineWidth',2);
% settings.h_dc_shadow = plot(h_dc_shadow,1:settings.N_cmos_image,...
%     zeros(settings.N_cmos_image,1),'LineWidth',2);
set(h_dc_shadow,'XTick',[]);
xlim(h_dc_shadow,[2 settings.N_cmos_image]);
handles.yAxesMinEdit = 100;
handles.yAxesMaxEdit = 4500;
ylim(h_dc_shadow,[handles.yAxesMinEdit handles.yAxesMaxEdit]);

[settings.refminloc, settings.refjawangle, settings.refdipmin] = deal([]);

% Axes for BV bar
t = [repmat([1, 1, 1],5,1); repmat([0.98, 0.83, 0.65],5,1)];
settings.BloodMap = t;
h_safesnipsaxes = findobj('Tag','dcImageAxes');
settings.h_cmosACimage = image(1:settings.N_cmos_image, ...
    1, ones(settings.N_cmos_image,1) , 'Parent', h_safesnipsaxes(1));
colormap(h_safesnipsaxes(1),settings.BloodMap);
set(h_safesnipsaxes,'XDir','reverse');
set(h_safesnipsaxes, 'TickDir', 'out');
set(h_safesnipsaxes, 'XTickMode', 'manual');
set(h_safesnipsaxes, 'XTick', []);
set(h_safesnipsaxes, 'YTickMode', 'manual');
set(h_safesnipsaxes, 'YTick', []);
set(h_safesnipsaxes, 'xlimmode', 'manual', 'ylimmode', 'manual',...
  'zlimmode', 'manual', 'climmode', 'manual', 'alimmode', 'manual');  
set(h_safesnipsaxes, 'DrawMode', 'fast');
set(h_safesnipsaxes, 'NextPlot', 'replacechildren');
settings.displayChart = 0;

settings.T = cell(5,1);
settings.baselineRange = [1990, 2010];
%% Opening the serial port 
% set(handles.StartAutomationCheckbox,'UserData',0);
set(handles.LED2Checkbox,'Value',1);
set(handles.LED4Checkbox,'Value',1);
set(handles.LED6Checkbox,'Value',1);
set(handles.autoUpdateLEDCheckbox,'Value',1);
set(handles.PumpControlButton,'UserData',0);

tempVesselStr = cellstr(get(handles.VesselMenu,'String'));
set(handles.VesselMenu,'UserData',tempVesselStr{1});
tempTissueStr = cellstr(get(handles.TissueMenu,'String'));
set(handles.TissueMenu,'UserData',tempTissueStr{1});

if ~isempty(params)
    set(handles.VesselMenu,'Value',params.vessel);
    set(handles.TissueMenu,'Value',params.tissue);
    set(handles.VesselSizeEdit,'String',params.vesselsize);
    set(handles.ThicknessEdit,'String',params.thickness);
    set(handles.VesselPositionEdit,'String',params.posn);
    set(handles.CommentsEdit,'String',params.comments);
end

b = instrfind;

try
    for i = 1:length(b)
        if regexpi(b.Status{i},'open')
            fclose(b(i));
        end
    end
catch
end

% Start things rolling.
try
    fopen(serialPort);
    fopen(udpPort);
catch
    errordlg('Please Reconnect the Board. The MATLAB seems to be having difficulty reading it','Error!');
    close all;
end

% Important that this be asynchronous.  Synchronous read doesn't work
% so well with GUI callbacks and neither does it get the BytesAvailable
% event until the whole buffer is full.

% Save the serial port in the GUIDATA for later retrieval.
handles.serialport = serialPort;
settings.serialport = serialPort;
handles.udpport = udpPort;
settings.udpport = udpPort;
handles.troubleshoot = 0;

code=zeros(20,1);
code(1:16) = sprintf('%16s','LED_intensity');
fwrite(handles.serialport,code);
%% Configure the UDP port to receive data from the Raspberry Pi
% Read the configuration file
settings.bdh_vars.config = jsondecode(fileread('/home/briteseed_data/pi_config/data_hub_config.json'));                % Decode the JSON file

% Configure the UDP port
settings.bdh_vars.bdhPort = udp('127.0.0.1', 50256, 'LocalPort', 50256, 'Timeout', 0.0001);
settings.bdh_vars.bdhPort.InputBufferSize = 400;
settings.bdh_vars.bdhPort.InputDatagramPacketSize = 80;
fopen(settings.bdh_vars.bdhPort);
settings.bdh_vars.last_save_cmd = 0;
settings.bdh_vars.counter = 0;

% Append external data to realtime column names
columns_rt = strcat(columns_rt, ',', strjoin(settings.bdh_vars.config.names, ','), '\n');

fmt = settings.bdh_vars.config.format;
fmt(fmt == 'i' | fmt == 'I' | fmt == 'h' | fmt == 'H') = 'd';
fmt = strcat("%", split(fmt, ""));
dataType_rt = strcat(dataType_rt, ',', strjoin(fmt(2:end-1), ',') , '\n');
settings.bvcolumn = char(columns_rt);
settings.bvdtype = char(dataType_rt);

settings.external_rt_data = zeros(length(settings.bdh_vars.config.format), 1);
%% Final touches
set(hObject, 'UserData', settings);
% Choose default command line output for auto_transmission_gui_v1
handles.output = hObject;
% Update handles structure
guidata(hObject, handles);
readasync(handles.serialport);

% UIWAIT makes auto_transmission_gui_v1 wait for user response (see UIRESUME)
% uiwait(handles.figure1);
% --- Outputs from this function are returned to the command line.
function varargout = auto_transmission_gui_v1_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;
% --- Executes on button press in close_button.
function close_button_Callback(hObject, ~, handles)
% hObject    handle to close_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
fclose(handles.serialport);
fclose(handles.udpport);
delete(handles.figure1);

%% Main Function % --- Called when serial port is full.
function serial_full_callback (obj,~,hSettings, handles)
settings = get(hSettings,'UserData');
stopasync(settings.serialport);
% Data Reading and Processing
Data = fread(obj,settings.bufferSize);

%% Read external data from Raspberry Pi
% To implement external data into other GUIs, copy this section and place
% at the beginning of the serial_full_callback.
if strcmp(settings.bdh_vars.bdhPort.Status, 'open')
    navailable = settings.bdh_vars.bdhPort.BytesAvailable;

    if navailable
        if settings.bdh_vars.counter >= 100
            disp("Raspberry Pi has reconnected")    % Print a status message
        end
        settings.bdh_vars.counter = 0;

        % Iteratively clear the input buffer by reading
        for i = 1:(navailable/settings.bdh_vars.config.size)-1
            [~] = fread(settings.bdh_vars.bdhPort, navailable-settings.bdh_vars.config.size, 'int8');
        end

        % Read the last-received packet of data
        data = fread(settings.bdh_vars.bdhPort, settings.bdh_vars.config.size);
        % Only unpack data if some data was received
        data_processed = unpack_udp_packet(data, settings.bdh_vars.config);
        if ~isempty(data_processed)
            settings.external_data = data_processed;
            settings.external_rt_data = cellfun(@double, struct2cell(data_processed));
            % Start a data save when the dtb_save variable is 1
            if settings.external_data.dtb_save
                set(handles.dataSaveButton, 'Value', 1);
            % If dtb_save goes from 1 to 0, stop the data save
            elseif ~settings.external_data.dtb_save && settings.bdh_vars.last_save_cmd
                set(handles.dataSaveButton, 'Value', 0);
            end
            % Keep track of the last save command
            settings.bdh_vars.last_save_cmd = settings.external_data.dtb_save;
        end
    else
        % If no data received this loop, increment the counter
        settings.external_rt_data = zeros(length(settings.bdh_vars.config.format), 1);
        settings.bdh_vars.counter = settings.bdh_vars.counter + 1;
    end

    if settings.bdh_vars.counter == 100
        settings.external_data = [];
        settings = rmfield(settings, 'external_data');
        disp("Raspberry Pi has disconnected")
    end
else
    fopen(settings.bdh_vars.bdhPort);
end

%% Main processing
if get(handles.StartAutomationCheckbox,'Value')
    % If the Automation option is ON
    if ~isempty(Data)        
%% Unpack the incoming serial data
        updated_msb = Data(settings.headerSize+5:2:settings.headerSize+498);
        lsb = Data(settings.headerSize+6:2:settings.headerSize+498);
        msb = mod(updated_msb,16);
        % Decode data and assign it to the serial data array
        serialdata =  double(uint16(bitshift(msb,8)) + uint16(lsb));
        if get(handles.smoothSignalCheckbox,'Value')
            settings.DC = filtfilt(settings.h,1,sgolayfilt(medfilt1(serialdata,13),1,21));
        else
            settings.DC= serialdata;
        end
        settings.imagebuff(1:247,:) = serialdata;    
%% Plot the Signal(s)
        settings.T{1} = settings.DC;
        settings.T{2} = zeros(size(settings.DC));
        settings.T{3} = zeros(size(settings.DC));
        settings.T{4} = zeros(size(settings.DC));
        settings.T{5} = zeros(size(settings.DC));
        set(settings.h_dc_shadow, {'YData'},settings.T);
        if ~isempty(settings.dips)
            [settings.dipmin,minloc] = min(settings.DC(settings.dips(1):settings.dips(2)));
            settings.dipminloc = minloc + settings.dips(1)-1;
        end
%% Pump Reading
        if get(handles.ShowPumpReadingCheckbox,'Value') 
            pumpdata = double(uint16(Data(settings.headerSize+4)));
            if strcmpi(get(handles.PumpReadingText,'Visible'),'off')
                set(handles.PumpReadingText,'Visible','on');
            end
            
            if settings.buffcount < 2*(settings.bufflength+1)
                settings.pbuff(1,settings.buffcount) = pumpdata;
                settings.buffcount = settings.buffcount+1;
            else
                sp=max(settings.pbuff);
                dp=min(settings.pbuff);
                settings.buffcount=1;
                set(handles.PumpReadingText,'String', ['Pump Reading' newline num2str(sp) '/' num2str(dp)]);

            end
            if settings.pumpcount < 101
                settings.pumpreading(1,settings.pumpcount) = pumpdata;
                settings.pumpmax = max([settings.pumpmax, pumpdata]);
                settings.pumpmin = min([settings.pumpmin, pumpdata]);
                settings.pumpcount = settings.pumpcount+1;
            else
                settings.pumpreading(1:99) = settings.pumpreading(2:100);
                settings.pumpreading(100) = pumpdata;
                settings.pumpmax = max([settings.pumpmax, pumpdata]);
                settings.pumpmin = min([settings.pumpmin, pumpdata]);
            end

       
        else
            if strcmpi(get(handles.PumpReadingText,'Visible'),'on')
                set(handles.PumpReadingText,'Visible','off');
            end
        end
%% Angle Sensor Reading Begins
        tempangledata = double(uint16(bitshift(Data(settings.headerSize+1),8)) + ...
                uint16(Data(settings.headerSize+2)));

        jawangle = round(polyval(settings.angle_coeffs,tempangledata));
        settings.theta = jawangle;
        
        if settings.theta > 60
            settings.theta = 60;
        end

        if settings.theta < 0
            settings.theta = 1;
        end
        
        if get(handles.AutoFill_JA_Checkbox,'Value')
            set(handles.JawAngleEdit,'String',num2str(settings.theta));  
        end
%% LED Intensities
        ledmsb = Data(500:2:510);   
        ledlsb = Data(501:2:511);
        settings.ledI = double(uint16(bitshift(ledmsb,8)) + uint16(ledlsb))';
        
        for i = 1:3
            eval(['set(handles.LED' num2str(i*2) '_Edit,''String'',settings.ledI(' num2str(i*2) '));']);
        end
%% Detect Dips        
        try
            dips = detectroi(settings.DC,2); 
        catch
            dips =[];
        end
        
        if ~isempty(dips)
            ndips = size(dips,1);
            slopesum = zeros(1,ndips);
            for k = 1:ndips
                slopesum(1,k) = abs(sum(diff(settings.DC(dips(k,1):dips(k,2)))));
            end

            if ~isempty(dips)
                if size(dips,1) > 1
                    [~,l] = min(slopesum);
                    dips = dips(l,:);
                end
                settings.dips = dips;
            else
                settings.dips = [];
            end
        else
            settings.dips = [];
        end        
%% Baseline Adapt
        if settings.dipFound && ~settings.startCycle   
% Adapt process
%             if settings.baselineadapt && ~settings.adaptdone
            if ~settings.adaptdone
                if ~mod(settings.adaptcount,2)
                    if isempty(settings.dips)
                        mDC = mean(settings.DC);
                        % If the average of the DC profile is above 3500,
                        % bring down the brightness
                        if mDC > 3200
                            if settings.baseRefLEDI == settings.tempMaxI 
                                settings.baseRefLEDI = round((settings.tempMinI+settings.tempMaxI)/2);
                            else
                                settings.tempMaxI = settings.baseRefLEDI;
                                settings.baseRefLEDI = round((settings.tempMinI+settings.tempMaxI)/2);
                            end
                            
                            adaptvals(settings.serialport, settings.baseRefLEDI);
                            settings.adaptcount = 1;

                        % If the average of the DC profile is below 3300,
                        % increase the brightness of the LEDs
                        elseif mDC < 2800
                            if settings.baseRefLEDI == settings.tempMinI
                                settings.baseRefLEDI = settings.tempMaxI;
                            else
                                settings.tempMinI = settings.baseRefLEDI;
                                settings.baseRefLEDI = round((settings.tempMinI+settings.tempMaxI)/2);
                            end
                            adaptvals(settings.serialport, settings.baseRefLEDI);%missing the same items
                            settings.adaptcount = 1;
                        % If the average is within the desired range, stop
                        % the adapt process
                        else
                            if mean(settings.DC) < 3500
                                settings.baselineadapt = 0;
                                settings.adaptcount = 1;
                                settings.refjawangle = settings.theta;
                            else
                                settings.baseRefLEDI =  round(mean([settings.minI, settings.maxI]));
                            end

                            settings.tempMinI = settings.minI;
                            settings.tempMaxI = settings.maxI;
                            settings.adaptdone = 1;
                            settings.dipFound = 0;
                        end
                        
                        if abs(settings.tempMinI - settings.tempMaxI) < 5
                            if mean(settings.DC) < 3500
%                                 settings.baselineadapt = 0; 
                                settings.adaptcount = 1;
                                settings.refjawangle = settings.theta;
                            else
                                settings.baseRefLEDI =  round(mean([settings.minI, settings.maxI]));
                            end
                            settings.tempMinI = settings.minI;
                            settings.tempMaxI = settings.maxI;
                            settings.adaptdone = 1;
                            settings.dipFound = 0;
                        end
                        
                    else
                        range = settings.dips(1,1):settings.dips(1,2);            
                        minval = min(settings.DC(range));
                        if minval < 1950 
                            if settings.baseRefLEDI == settings.tempMinI
                                settings.baseRefLEDI = settings.tempMaxI;
                            else
                                settings.tempMinI = settings.baseRefLEDI;
                                settings.baseRefLEDI = round((settings.tempMinI+settings.tempMaxI)/2);
                            end  
          
                            adaptvals(settings.serialport,settings.baseRefLEDI);
                            settings.adaptcount = 1;
                            
                        elseif minval > 2050
                            if settings.baseRefLEDI == settings.tempMaxI 
                                settings.baseRefLEDI = round((settings.tempMinI+settings.tempMaxI)/2);
                            else
                                settings.tempMaxI = settings.baseRefLEDI;
                                settings.baseRefLEDI = round((settings.tempMinI+settings.tempMaxI)/2);
                            end
                            adaptvals(settings.serialport, settings.baseRefLEDI); 
                            settings.adaptcount = 1;
                        else
%                             settings.baselineadapt = 0;                           
                            settings.adaptcount = 1;
                            settings.tempMinI = settings.minI;
                            settings.tempMaxI = settings.maxI;
                            settings.refjawangle = settings.theta;
                            [settings.refdipmin,minloc] = min(settings.DC(settings.dips(1):settings.dips(2)));
                            settings.refminloc = settings.dips(1)+minloc-1;
                            settings.adaptdone = 1;
                        end
                        if abs(settings.tempMinI - settings.tempMaxI) < 5
%                             settings.baselineadapt = 0;
                            settings.adaptcount = 1;
                            settings.tempMinI = settings.minI;
                            settings.tempMaxI = settings.maxI;
                            settings.refjawangle = settings.theta;
                            [settings.refdipmin,minloc] = min(settings.DC(settings.dips(1):settings.dips(2)));
                            settings.refminloc = settings.dips(1)+minloc-1;
                            settings.adaptdone = 1;
                        end
                    end
                else
                    settings.adaptcount = settings.adaptcount+1;
                end  
            end
% Surveillance 
            if settings.adaptdone 
                if settings.dipmin > 2200 || settings.dipmin < 1800       
                    if settings.ledI(4) == 9999
                        settings.dipFound = 0;
                    end                    
                    settings.adaptdone = 0;
                    settings.module_flag = 34;
                end
            end                     
        end       
%% Stop LED Cycling
        if ~isempty(settings.dips) && settings.startCycle
            settings.dipFound = 1;
            settings.startCycle=0;
            settings.adaptdone = 0;
            
            code = zeros(20,1);
            code(1:8) = sprintf('%8s', 'LED_adap');
            code(9) = uint8(0);
            code(10) = uint8(bin2dec('00101010'));
            
            
            
            %SNO1 Vals Updated on 11/16/21
%             v11= 562; v12=600; v13=618;
%             v21= 707; v22=800; v23=844; 
%             v31= 853; v32=1000; v33=1071;
%             v41= 998; v42=1200; v43=1297;
%             v51= 1216; v52=1500; v53=1637;


            
            %SNO1 Vals Updated on 11/30/21
%             v11= 559; v12=600; v13=612;
%             v21= 699; v22=800; v23=829; 
%             v31= 838; v32=1000; v33=1045;
%             v41= 978; v42=1200; v43=1261;
%             v51= 1187; v52=1500; v53=1585;

            %SNO1 Vals Updated on 12/07/21
%             v11= 559; v12=600; v13=618;
%             v21= 700; v22=800; v23=843; 
%             v31= 841; v32=1000; v33=1068;
%             v41= 982; v42=1200; v43=1292;
%             v51= 1193; v52=1500; v53=1630;
            
            %SNO1 Vals Updated on 12/14/21
            v11= 559; v12=600; v13=620;
            v21= 699; v22=800; v23=850; 
            v31= 840; v32=1000; v33=1080;
            v41= 981; v42=1200; v43=1311;
            v51= 1192; v52=1500; v53=1656;
            
            %SNO2 Vals Updated on 10/28/21
%             v11= 561; v12=600; v13=633;
%             v21= 709; v22=800; v23=885; 
%             v31= 857; v32=1000; v33=1136;
%             v41= 1005; v42=1200; v43=1388;
%             v51= 1227; v52=1500; v53=1765;

             %SNO2 Vals Updated on 11/16/21
%              v11= 562; v12=600; v13=618;
%              v21= 707; v22=800; v23=844; 
%              v31= 853; v32=1000; v33=1071;
%              v41= 998; v42=1200; v43=1297;
%              v51= 1216; v52=1500; v53=1637;

              %SNO2 Vals Updated on 12/02/21
%              v11= 578; v12=600; v13=626;
%              v21= 746; v22=800; v23=865; 
%              v31= 914; v32=1000; v33=1105;
%              v41= 1082; v42=1200; v43=1345;
%              v51= 1333; v52=1500; v53=1704;
            
            if settings.ledI(4) == 1500
                settings.baseRefLEDI = v52;
                code(11) = uint8(bitshift(v51,-8));
                code(12) = uint8(mod(v51,256));
                code(13) = uint8(bitshift(v52,-8));
                code(14) = uint8(mod(v52,256));
                code(15) = uint8(bitshift(v43,-8));
                code(16) = uint8(mod(v53,256));
            elseif settings.ledI(4) == 600
                settings.baseRefLEDI = v12;
                code(11) = uint8(bitshift(v11,-8));
                code(12) = uint8(mod(v11,256));
                code(13) = uint8(bitshift(v12,-8));
                code(14) = uint8(mod(v12,256));
                code(15) = uint8(bitshift(v13,-8));
                code(16) = uint8(mod(v13,256));                
            elseif settings.ledI(4) == 800
                settings.baseRefLEDI = v22;
                code(11) = uint8(bitshift(v21,-8));
                code(12) = uint8(mod(v21,256));
                code(13) = uint8(bitshift(v22,-8));
                code(14) = uint8(mod(v22,256));
                code(15) = uint8(bitshift(v23,-8));
                code(16) = uint8(mod(v23,256));                
            elseif settings.ledI(4) == 1000
                settings.baseRefLEDI = v32;
                code(11) = uint8(bitshift(v31,-8));
                code(12) = uint8(mod(v31,256));
                code(13) = uint8(bitshift(v32,-8));
                code(14) = uint8(mod(v32,256));
                code(15) = uint8(bitshift(v33,-8));
                code(16) = uint8(mod(v33,256));                
            elseif settings.ledI(4) == 1200
                settings.baseRefLEDI = v42;
                code(11) = uint8(bitshift(v41,-8));
                code(12) = uint8(mod(v41,256));
                code(13) = uint8(bitshift(v42,-8));
                code(14) = uint8(mod(v42,256));
                code(15) = uint8(bitshift(v43,-8));
                code(16) = uint8(mod(v43,256));                
            end
            
            fwrite(settings.serialport,code);
            settings.module_flag = 2;
        end
%% Start LED Cycling
        if ~settings.startCycle && ~settings.dipFound
            settings.startCycle = 1;
            code = zeros(40,1);
            
            code(1:8) = sprintf('%8s', 'LED_ints');
            
            %SNO1 Vals Updated on 11/16/21
%             v11= 562; v12=600; v13=618;
%             v21= 707; v22=800; v23=844; 
%             v31= 853; v32=1000; v33=1071;
%             v41= 998; v42=1200; v43=1297;
%             v51= 1216; v52=1500; v53=1637;


            %SNO1 Vals Updated on 11/30/21
%             v11= 559; v12=600; v13=612;
%             v21= 699; v22=800; v23=829; 
%             v31= 838; v32=1000; v33=1045;
%             v41= 978; v42=1200; v43=1261;
%             v51= 1187; v52=1500; v53=1585;

            %SNO1 Vals Updated on 12/07/21
%             v11= 559; v12=600; v13=618;
%             v21= 700; v22=800; v23=843; 
%             v31= 841; v32=1000; v33=1068;
%             v41= 982; v42=1200; v43=1292;
%             v51= 1193; v52=1500; v53=1630;
            
            %SNO1 Vals Updated on 12/14/21
            v11= 559; v12=600; v13=620;
            v21= 699; v22=800; v23=850; 
            v31= 840; v32=1000; v33=1080;
            v41= 981; v42=1200; v43=1311;
            v51= 1192; v52=1500; v53=1656;
            
            %SNO2 Vals Updated on 10/28/21
%             v11= 561; v12=600; v13=633;
%             v21= 709; v22=800; v23=885; 
%             v31= 857; v32=1000; v33=1136;
%             v41= 1005; v42=1200; v43=1388;
%             v51= 1227; v52=1500; v53=1765;

             %SNO2 Vals Updated on 11/16/21
%              v11= 562; v12=600; v13=618;
%              v21= 707; v22=800; v23=844; 
%              v31= 853; v32=1000; v33=1071;
%              v41= 998; v42=1200; v43=1297;
%              v51= 1216; v52=1500; v53=1637;
             
             %SNO2 Vals Updated on 12/02/21
%              v11= 578; v12=600; v13=626;
%              v21= 746; v22=800; v23=865; 
%              v31= 914; v32=1000; v33=1105;
%              v41= 1082; v42=1200; v43=1345;
%              v51= 1333; v52=1500; v53=1704; 
             
            code(9) = uint8(bitshift(v11,-8));
            code(10) = uint8(mod(v11,256));
            code(11) = uint8(bitshift(v12,-8));
            code(12) = uint8(mod(v12,256));
            code(13) = uint8(bitshift(v13,-8));
            code(14) = uint8(mod(v13,256));
            code(15) = uint8(bitshift(v21,-8));
            code(16) = uint8(mod(v21,256));
            code(17) = uint8(bitshift(v22,-8));
            code(18) = uint8(mod(v22,256));
            code(19) = uint8(bitshift(v23,-8));
            code(20) = uint8(mod(v23,256));
            code(21) = uint8(bitshift(v31,-8));
            code(22) = uint8(mod(v31,256));
            code(23) = uint8(bitshift(v32,-8));
            code(24) = uint8(mod(v32,256));
            code(25) = uint8(bitshift(v33,-8));
            code(26) = uint8(mod(v33,256));                        
            code(27) = uint8(bitshift(v41,-8));
            code(28) = uint8(mod(v41,256));
            code(29) = uint8(bitshift(v42,-8));
            code(30) = uint8(mod(v42,256));
            code(31) = uint8(bitshift(v43,-8));
            code(32) = uint8(mod(v43,256));
            code(33) = uint8(bitshift(v51,-8));
            code(34) = uint8(mod(v51,256));
            code(35) = uint8(bitshift(v52,-8));
            code(36) = uint8(mod(v52,256));
            code(37) = uint8(bitshift(v53,-8));
            code(38) = uint8(mod(v53,256));

            fwrite(settings.serialport,code);
            
%
            settings.flag_buff= zeros(1,3);
            settings.bvTissueCount = 1;
            settings.count1 = 1;
            settings.module_flag = 1;
            settings.timer_start = tic;
        end
%% Start Recursive AC Computation if Dip detected
        if settings.adaptdone && ~isempty(settings.dips) && settings.ledI(6)>525 && settings.dipFound            
            
            settings.bvSizeReady = 1;
            
            leds=[settings.ledI(2)./9999,settings.ledI(4)./9999,settings.ledI(6)./9999];
            dcdata=(settings.DC)./max(settings.DC);
           
            settings.nndata(settings.count1,:) = [leds,dcdata'];
            
            if mod(settings.count1,9)
                settings.count1 = settings.count1+1;                
            else
                settings.vggsize=settings.vgg.predict(settings.nndata(1:9,:));
                settings.count1 = 1;
            end
            
            
            settings.bvTissueData(settings.bvTissueCount,:) =[leds,dcdata'];%would use thsi for the V12
            
            if ~mod(settings.bvTissueCount, 9)
                if settings.bvTissueCount == 9
                    res = settings.bvTissueTimeNet.predict(settings.bvTissueData(1:9,:));
                    [~,l] = max(res);
                    l = l-1;  
                    settings.flag_buff(1,1) = l;
                    settings.bvTissueCount = settings.bvTissueCount+1;
                elseif settings.bvTissueCount == 18
                    res = settings.bvTissueTimeNet.predict(settings.bvTissueData(10:18,:));
                    [~,l] = max(res);
                    l = l-1;  
                    settings.flag_buff(1,2) = l;
                    settings.bvTissueCount = settings.bvTissueCount+1;
                elseif settings.bvTissueCount == 27
                    res = settings.bvTissueTimeNet.predict(settings.bvTissueData(19:27,:));
                    [~,l] = max(res);
                    l = l-1;  
                    settings.flag_buff(1,3) = l;
                    settings.bvTissueCount = 1;
                end
                
            else
                settings.bvTissueCount = settings.bvTissueCount+1;
            end
            
            
            if (mode(settings.flag_buff) && settings.bv3) %BVT Flagged Vessels more than twice, buffer full
                settings.colorflag = 'red'; 
                settings.bvDetected = 1;
                settings.bv3 = 0;
            elseif (~mode(settings.flag_buff) && settings.bv3) %BVT IDe'ed Tissue more than twice, buffer full
                settings.colorflag = 'white'; 
                settings.bvDetected = 0;
                settings.bv3 = 0;
            elseif (mode(settings.flag_buff) && ~settings.bv3) %BVT ID'ed vessels atleast twice, buffer ~full
                settings.colorflag = 'red';
                settings.bvDetected = 1;
            elseif (~mode(settings.flag_buff) && ~settings.bv3) %BVT ID'ed tiss atleast twice, buffer ~full
                settings.colorflag = 'beige';
                settings.bvDetected = 0;
            end
                
                        
            settings.module_flag = 61;
        else
            if settings.adaptdone
                settings.dipFound = 0;
                settings.adaptdone = 0;
                settings.startCycle = 0;
                settings.bvSizeReady = 0;
                settings.module_flag = 622;
            end
        end
%% Start the Fancy BV Tracking Bar
        if settings.bvSizeReady && ~isempty(settings.dips)       
            bvsize = round(settings.vggsize,2);
            %overlayBuffer(end) = uint8(round(bvsize * 10));
            set(handles.bvSizeBarText,'String',[num2str(bvsize) 'mm']);
            [~, meanLoc] = min(settings.DC(settings.dips(1,1):settings.dips(1,2))); 
            meanLoc = settings.dips(1)+meanLoc;

            % 1mm ~ 14.35 pixels
            X = bvsize*14.35; % Convert mm size to pixel numbers
            settings.I = ones(settings.N_cmos_image,1);
            if ~isnan(X)        
                leftregion = floor(meanLoc-X/2);
                if leftregion < 1 
                   leftregion = 1;
                end
                rightregion = ceil(meanLoc+X/2);
                if rightregion > 247 
                   rightregion = 247;
                end                        
                settings.I(leftregion:rightregion,1) = 9;
            end

            switch settings.colorflag
                case 'white'
                    settings.I = zeros(settings.N_cmos_image,1);                        
                    settings.BloodMap = [repmat([1, 1, 1],5,1); repmat([0,0,0],5,1)];
                    colormap(handles.dcImageAxes,settings.BloodMap);
                case 'beige'
                    settings.BloodMap = [repmat([1, 1, 1],5,1); repmat([0.98, 0.83, 0.65],5,1)];
                    colormap(handles.dcImageAxes,settings.BloodMap);
                case 'red'
                    settings.BloodMap = [repmat([1, 1, 1],5,1); repmat([0.9,0,0],5,1)];
                    colormap(handles.dcImageAxes,settings.BloodMap);
            end
                            
        else
            settings.I_temp = ones(settings.N_cmos_image,1);
            set(handles.bvSizeBarText,'String','');
        end
        
        if(settings.overlay_count1 < 5 )
            settings.overlay_count1 = settings.overlay_count1+1;
            settings.overlaybuffer(settings.overlay_count1,:) = flipud(settings.I)';
            settings.bvDetected_buffer(settings.overlay_count1,1)  = settings.bvDetected;
            settings.toOverlayBoard(end-1) = uint8(0);
        else
            settings.overlaybuffer(1:3,:) = settings.overlaybuffer(2:4,:); 
            settings.overlaybuffer(4,:) = flipud(settings.I)';
            
            settings.bvDetected_buffer(1:3,1)  = settings.bvDetected_buffer(2:4,1);
            settings.bvDetected_buffer(4,1)  = settings.bvDetected;
        end
%% Reset counters and flags
        if settings.startCycle && ~settings.dipFound 
            if toc(settings.timer_start) >= 0.1
                settings.overlay_count1 = 1; % reset Overlay_buffer count if cycling was on for more than 3seconds
                settings.vggsize = 0;
                settings.bvDetected_buffer(1:4,1) = zeros(4,1);
                settings.I = zeros(settings.N_cmos_image,1);
                settings.overlaybuffer = zeros(5,247);
                settings.count1 = 1;
                settings.bvTissueCount =1;
                settings.bvSizeReady = 0;
            end
        end
%% Send packet to Overlay
% for overlay bar:
        settings.datatosend = mode(settings.overlaybuffer(2:end,:),1);
        settings.toOverlayBoard(2:end-2) = uint8(settings.datatosend');
        settings.toOverlayBoard(end-1) = uint8(median(settings.bvDetected_buffer));
        settings.toOverlayBoard(end) = uint8(round(round(settings.vggsize,1) * 10));
        fwrite(settings.udpport, settings.toOverlayBoard);
        
% for matlab bar: 
        set(settings.h_cmosACimage,'CData',settings.toOverlayBoard(2:end-2));  
%% Saving Realtime Data
        if get(handles.dataSaveButton, 'Value')
            if ~settings.rtcount
                set(handles.timerText,'Visible','on');
                settings.rtcount = 1;

                folderName = settings.rtfolderName;
                settings.fileName = strcat(folderName,'_File_',num2str(settings.rtfilenum));

                set(handles.dataSaveButton,'BackgroundColor',[0,204,102]./255,...
                    'FontWeight','bold','Enable','inactive');

                vessel = get(handles.VesselMenu,'UserData');
                vesselsize = get(handles.VesselSizeEdit,'String');
                thickness = get(handles.ThicknessEdit,'String');
                tissue = get(handles.TissueMenu,'UserData');
                comments = get(handles.CommentsEdit,'String');
                jawangle = get(handles.JawAngleEdit,'String');
                tool = get(handles.tool_used, 'UserData');
                approach = get(handles.Condition, 'UserData');
                
                if strcmpi(vesselsize,'---') 
                    vesselsize = '0mm';
                end
                temp_vs = strsplit(strrep(vesselsize,'-','.'),'mm');
                if str2num(temp_vs{1}) == 0
                    vesselsize = [vesselsize '_NA'];
                elseif str2num(temp_vs{1}) < 4
                    vesselsize = [vesselsize '_Small'];
                elseif str2num(temp_vs{1}) > 4
                    vesselsize = [vesselsize '_Large'];
                end
                
                settings.fileName = [settings.fileName '_V_' vessel '_VS_' vesselsize ...
                    '_T_' tissue '_Th_' thickness '_' comments '_A_' approach '_JA_' ...
                    jawangle '_T_' tool '_V11_DTB.csv'];

                folder=settings.rtfolderName;
                % Check if the folder Already Exists. Create one if it does not
                if exist(folder,'dir')~=7
                    mkdir(folder);
                end
                settings.savefolderName = folder;

                % Create a Temp File
                settings.tempName = tempname();
                settings.temp_fid = fopen(settings.tempName,'w');
                fprintf(settings.temp_fid,settings.bvcolumn);  
                settings.ref_counter = 0;
            else
                settings.ref_counter = settings.ref_counter+1;
                set(handles.dataSaveButton,'String','Saving Data');
                set(handles.dataSaveButton,'BackgroundColor',[0.5 1 0.5]);
                dipflag = double(~isempty(settings.dips));
               % Counter from FPGA
                counter = double(uint16(bitshift(Data(512),8)) + ...
                        uint16(Data(513)));
                if strcmp(settings.colorflag, 'white')
                    color = 0;
                elseif strcmp(settings.colorflag, 'beige')
                    color = 1;
                elseif strcmp(settings.colorflag, 'red')
                    color = 2;
                end
                
                if isempty(settings.dcMLsize)
                    dcMLsize_save = 9999;
                else
                    dcMLsize_save = settings.dcMLsize;
                end
                if isempty(settings.vggsize)
                    vggsize_save = 9999;
                else
                    vggsize_save = settings.vggsize;
                end
                if isempty(settings.refminloc)
                    refminloc_save = 9999;
                else
                    refminloc_save = settings.refminloc;
                end
                
                saveData = [settings.ledI settings.DC' settings.startCycle settings.dipFound ...
                    dipflag settings.adaptdone settings.baselineadapt refminloc_save ...
                    settings.bvTissueCount settings.bvDetected settings.bvSizeReady color ...
                    settings.count1 vggsize_save dcMLsize_save counter settings.theta ...
                    settings.external_rt_data'];
                fprintf(settings.temp_fid, settings.bvdtype, saveData);
            end
        else
            if settings.rtcount
                name = fullfile(pwd, settings.savefolderName, settings.fileName);
                copyfile(settings.tempName, name);
                settings.rtfilenum = settings.rtfilenum+1;
                fclose(settings.temp_fid);
                set(handles.dataSaveButton,'BackgroundColor',0.94*ones(1,3),...
                    'FontWeight','bold','Enable','on', 'String','Save Data');
                set(handles.dataSaveButton,'UserData',0);            
                settings.rtcount = 0;
                settings.ref_counter
            end
        end        
    end
else
    if ~isempty(Data)
%% Data Unpacking
        l = size(Data(settings.headerSize+5:2:settings.headerSize+498),1);
        %This l is used to find out the size of the incoming data. If the data
        %size if less than 250, zeros wil be appended to the end of the
        %sequence so the system does not stop        
        msb = Data(settings.headerSize+5:2:settings.headerSize+498);
        lsb = Data(settings.headerSize+6:2:settings.headerSize+498);
        msb = mod(msb,16);

        % Unpack data and Assign it to the serial data array
        serialdata =  double(uint16(bitshift(msb,8)) + uint16(lsb));
        settings.imagebuff(1:l,1) = serialdata;

        % Filter the incoming signal if needed
        if handles.smoothSignalCheckbox.Value
            settings.DC = filtfilt(settings.h,1,sgolayfilt(medfilt1(serialdata,13),1,21));
%             settings.dipdc = serialdata;
        else
            settings.DC= serialdata;
%             settings.dipdc = serialdata
        end
%         settings.DC = filtfilt(settings.h,1,sgolayfilt(medfilt1(serialdata,13),1,21));
%% Pump Reading
        if get(handles.ShowPumpReadingCheckbox,'Value') 
            pumpdata = double(uint16(Data(settings.headerSize+4)));
            if strcmpi(get(handles.PumpReadingText,'Visible'),'off')
                set(handles.PumpReadingText,'Visible','on');
            end
            
            if settings.buffcount < 2*(settings.bufflength+1)
                settings.pbuff(1,settings.buffcount) = pumpdata;
                settings.buffcount = settings.buffcount+1;
            else
                sp=max(settings.pbuff);
                dp=min(settings.pbuff);
                settings.buffcount=1;
                set(handles.PumpReadingText,'String', ['Pump Reading' newline num2str(sp) '/' num2str(dp)]);

            end
            if settings.pumpcount < 101
                settings.pumpreading(1,settings.pumpcount) = pumpdata;
                settings.pumpmax = max([settings.pumpmax, pumpdata]);
                settings.pumpmin = min([settings.pumpmin, pumpdata]);
                settings.pumpcount = settings.pumpcount+1;
            else
                settings.pumpreading(1:99) = settings.pumpreading(2:100);
                settings.pumpreading(100) = pumpdata;
                settings.pumpmax = max([settings.pumpmax, pumpdata]);
                settings.pumpmin = min([settings.pumpmin, pumpdata]);
            end

       
        else
            if strcmpi(get(handles.PumpReadingText,'Visible'),'on')
                set(handles.PumpReadingText,'Visible','off');
            end
        end
%% Angle Sensor Reading Begins
        tempangledata = double(uint16(bitshift(Data(settings.headerSize+1),8)) + ...
                uint16(Data(settings.headerSize+2)));
        jawangle = round(polyval(settings.angle_coeffs,tempangledata));

        settings.theta = jawangle;
        if settings.theta > 60
            settings.theta = 60;
        end

        if settings.theta < 0
            settings.theta = 0;
        end

        if get(handles.AutoFill_JA_Checkbox,'Value')
            set(handles.JawAngleEdit,'String',num2str(settings.theta));
        end
        ledmsb = Data(500:2:510);   
        ledlsb = Data(501:2:511);
        settings.ledI = double(uint16(bitshift(ledmsb,8)) + uint16(ledlsb))';
        settings.ledI = settings.ledI(settings.inds);
        for i = 1:3
            eval(['set(handles.LED' num2str(i*2) '_Edit,''String'',settings.ledI(' num2str(i*2) '));']);
        end

        settings.trackdc = get(handles.dcTrackCheckbox,'Value');
        settings.trackac = get(handles.acTrackCheckbox,'Value');
%% Dip Detection
        try
            dips = detectroi(settings.DC,2); 
        catch
            dips=[];
        end
        if ~isempty(dips)
            % Select the Best of all the Dips Detected. The best dip is
            % selected as the one which has the smallest sum of its
            % derivative. In an ideal case, the dip's derivative should be
            % almost zero.
            ndips = size(dips,1);

            slopesum = zeros(1,ndips);
            for k = 1:ndips
                slopesum(1,k) = abs(sum(diff(settings.DC(dips(k,1):dips(k,2)))));
            end

            if ~isempty(dips)
                if size(dips,1) > 1
                    [~,l] = min(slopesum);
                    dips = dips(l,:);
                end
                settings.dips = dips;
            else
                settings.dips = [];
            end
        else
            settings.dips = [];
        end
%% Plot the Signal(s)
        if settings.trackdc 
            if ~isempty(settings.dips)
                range = settings.dips(1):settings.dips(2);
                sdc(range) = settings.DC(range);
            else
%                 set(handles.roiText,'String','No Dips Detected','BackgroundColor',...
%                     [1,0.5,0.5]);
            end
        else
            sdc = zeros(size(settings.DC));
        end

        if ~isempty(settings.dips)
            [settings.dipmin,minloc] = min(settings.DC(settings.dips(1):settings.dips(2)));
            settings.dipminloc = minloc + settings.dips(1)-1;
        end

        if settings.trackac && ~isempty(settings.dips)
            sac = settings.tempAC;
        else
            sac = zeros(size(settings.DC));
        end
        settings.T{1} = settings.DC;
        settings.T{2} = sac;
        settings.T{3} = sdc;
        settings.T{4} = zeros(size(settings.DC));
        settings.T{5} = zeros(size(settings.DC));
        set(settings.h_dc_shadow, {'YData'},settings.T);   
%% Baseline Adapt
      
        if handles.baseline2000.Value
            val = 2000;
            settings.baseline=val;
            settings.baselineRange = [val-10, val+10];
        end
      
% Adapt Process         
        if settings.baselineadapt
            if ~mod(settings.adaptcount,5)
                if isempty(settings.dips)
                    mDC = mean(settings.DC);
                    if mDC > 3200
                        if settings.baseRefLEDI == settings.tempMaxI 
                            settings.baseRefLEDI = round((settings.tempMinI+settings.tempMaxI)/2);
                        else
                            settings.tempMaxI = settings.baseRefLEDI;
                            settings.baseRefLEDI = round((settings.tempMinI+settings.tempMaxI)/2);
                        end
                        adaptvals(settings.serialport, settings.baseRefLEDI);
                        settings.adaptcount = 1;

                    elseif mDC < 2800
                        if settings.baseRefLEDI == settings.tempMinI
                            settings.baseRefLEDI = settings.tempMaxI;
                        else
                            settings.tempMinI = settings.baseRefLEDI;
                            settings.baseRefLEDI = round((settings.tempMinI+settings.tempMaxI)/2);
                        end
                        adaptvals(settings.serialport, settings.baseRefLEDI);
                        settings.adaptcount = 1;

                    else
                        if mean(settings.DC) < 3500
                            settings.baselineadapt = 0;
                            settings.adaptcount = 1;
                            set(handles.baseline2000,'Value',0);
                            settings.refjawangle = settings.theta;

                        else
                            settings.baseRefLEDI =  round(mean([settings.minI, settings.maxI]));
                        end

                        settings.tempMinI = settings.minI;
                        settings.tempMaxI = settings.maxI;
                    end

                    if abs(settings.tempMinI - settings.tempMaxI) < 5
                        if mean(settings.DC) < 3500
                            settings.baselineadapt = 0;
                            settings.adaptcount = 1;
                            set(handles.baseline2000,'Value',0);
                            settings.refjawangle = settings.theta;
                        else
                            settings.baseRefLEDI =  round(mean([settings.minI, settings.maxI]));
                        end

                        settings.tempMinI = settings.minI;
                        settings.tempMaxI = settings.maxI;

                    end

                else

                    range = settings.dips(1,1):settings.dips(1,2);            
                    minval = min(settings.DC(range));

                    if minval < settings.baselineRange(1)
                        if settings.baseRefLEDI == settings.tempMinI
                            settings.baseRefLEDI = settings.tempMaxI;
                        else
                            settings.tempMinI = settings.baseRefLEDI;
                            settings.baseRefLEDI = round((settings.tempMinI+settings.tempMaxI)/2);
                        end    

                        adaptvals(settings.serialport, settings.baseRefLEDI);
                        settings.adaptcount = 1;

                    elseif minval > settings.baselineRange(2)
                        if settings.baseRefLEDI == settings.tempMaxI 
                            settings.baseRefLEDI = round((settings.tempMinI+settings.tempMaxI)/2);
                        else
                            settings.tempMaxI = settings.baseRefLEDI;
                            settings.baseRefLEDI = round((settings.tempMinI+settings.tempMaxI)/2);
                        end

                        adaptvals(settings.serialport, settings.baseRefLEDI);
                        settings.adaptcount = 1;

                    else
                        settings.baselineadapt = 0;
                        settings.adaptcount = 1;
                        set(handles.baseline2000,'Value',0);
                        settings.tempMinI = settings.minI;
                        settings.tempMaxI = settings.maxI;
                        settings.refjawangle = settings.theta;
                        [settings.refdipmin,minloc] = min(settings.DC(settings.dips(1):settings.dips(2)));
                        settings.refminloc = settings.dips(1)+minloc-1;
                    end
                    if abs(settings.tempMinI - settings.tempMaxI) < 5
                        settings.baselineadapt = 0;
                        settings.adaptcount = 1;
                        set(handles.baseline2000,'Value',0);
                        settings.tempMinI = settings.minI;
                        settings.tempMaxI = settings.maxI;
                        settings.refjawangle = settings.theta;
                        [settings.refdipmin,minloc] = min(settings.DC(settings.dips(1):settings.dips(2)));
                        settings.refminloc = settings.dips(1)+minloc-1;
                    end
                end
            else
                settings.adaptcount = settings.adaptcount+1;
            end
        end
% Start Baseline Adapt
        if get(handles.baseline2000,'Value')
            if ~settings.baselineadapt
                [settings.tempMinI, settings.minI] = deal(100);
                [settings.tempMaxI, settings.maxI] = deal(9000);
                settings.baseRefLEDI = round(mean([settings.tempMinI, settings.tempMaxI]));
                settings.baselineadapt = 1;
                adaptvals(settings.serialport,settings.baseRefLEDI);
            end
        else
        end
    end   
%% Turn the LED Cycling off if it's still running 
    if settings.startCycle
        settings.dipFound = 0;
        settings.startCycle=0;
        settings.adaptdone = 0;
        settings.baselineadapt = 1;
        settings.baseRefLEDI = 1550;
        code = zeros(20,1);
        code(1:8) = sprintf('%8s', 'LED_adap');
        code(9) = uint8(0);
        code(10) = uint8(bin2dec('00101010'));
        code(11) = uint8(bitshift(1561,-8));
        code(12) = uint8(mod(1561,256));
        code(13) = uint8(bitshift(1550,-8));
        code(14) = uint8(mod(1550,256));
        code(15) = uint8(bitshift(1799,-8));
        code(16) = uint8(mod(1799,256)); 
        fwrite(settings.serialport,code);
    end
end
readasync(settings.serialport);
set(hSettings, 'UserData', settings);

%% Functions that are used in the main function
function adaptvals(serialport,val)
% global ledvalues;
thr = 9999;
if val > thr || val < 0 
    val = (val > thr)*thr + (val < 0)*0;
end
currIntled= val;


% % VSHH_3 18/08/2020 coefficents 
%A = [1, 0.0234, 1, 0.0141, 1 , 0.0826];
%B = [0.0242, 0.0242, 0.0247, 0.0247, 0.0203, 0.0203];

%SN01 Coeffs Updated 11/16/2021
%  A = [0,0.38849,0,4.6577,0,7.8812];
%  B = [0,0.017116,0,0.011698,0,0.010553];

 % SN01 11/30/21
%  A = [0,1.0624,0,8.561,0,12.0725];
%  B = [0,0.014821,0,0.010336,0,0.009564];

 % SN01 12/07/21
%  A = [0,2.5119,0,15.0034,0,23.715];
%  B = [0,0.013023,0,0.0091652,0,0.0081551];

 % SN01 12/14/21
 A = [0,0.31543,0,3.4344,0,7.2282];
 B = [0,0.017438,0,0.01226,0,0.010658];

%SN02 Coeffs Updated 11/16/2021
%  A = [0,0.64421,0,2.1088,0,7.2196];
%  B = [0,0.01595,0,0.013376,0,0.010728];

% SN02 11/30/21
%  A = [0,2.1717,0,5.839,0,13.9824];
%  B = [0,0.013346,0,0.011204,0,0.00935];

 % SN02 12/07/21
%  A = [0,1.1782,0,4.2144,0,10.5028];
%  B = [0,0.014663,0,0.011881,0,0.0099416];

 % SN02 12/14/21
%  A = [0,1.7713,0,6.7151,0,14.1022];
%  B = [0,0.013808,0,0.010906,0,0.009305];

c = A(4)*exp(B(4)*currIntled);
thr = 9999;
v = round((log(c)-log(A))./B);
v(v>thr) = thr;
v(v<0) = 0;
v = uint16(v);
v = [0,v(2),0,v(4),0,v(6)];
code = zeros(20,1);
code(1:8) = sprintf('%8s','LED_INT');

code(9:2:20) = uint8(bitshift(v,-8));
code(10:2:20) = uint8(mod(v,256));
% write(serialport,code,'uint8');
fwrite(serialport,code);

%% % --- Executes on button press in dcTrackCheckbox.
function dcTrackCheckbox_Callback(hObject, eventdata, handles)
% hObject    handle to dcTrackCheckbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% Hint: get(hObject,'Value') returns toggle state of dcTrackCheckbox
% --- Executes on button press in acTrackCheckbox.
function acTrackCheckbox_Callback(hObject, eventdata, handles)
% hObject    handle to acTrackCheckbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of acTrackCheckbox

function jawAngleEdit_Callback(hObject, eventdata, handles)

% --- Executes during object creation, after setting all properties.
function jawAngleEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to jawAngleEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes on button press in dataSaveButton.
function dataSaveButton_Callback(hObject, eventdata, handles)
% hObject    handle to dataSaveButton (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

set(hObject,'UserData',1);

function LED1_Edit_Callback(hObject, eventdata, handles)
% hObject    handle to LED1_Edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of LED1_Edit as text
%        str2double(get(hObject,'String')) returns contents of LED1_Edit as a double

thr = 9999;

val = str2double(get(hObject,'String'));
if val > thr || val < 0 
    val = (val > thr)*thr + (val < 0)*0;
end

val = uint16(val);
val1 = uint8(bitshift(val,-8));
val2 = uint8(mod(val,256));

update_led_intensity(handles,val1,val2,1);

% --- Executes during object creation, after setting all properties.
function LED1_Edit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to LED1_Edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function LED2_Edit_Callback(hObject, eventdata, handles)
% hObject    handle to LED2_Edit (see GCBO)
% eventdata  re`served - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of LED2_Edit as text
%        str2double(get(hObject,'String')) returns contents of LED2_Edit as a double

thr = 9999;

val = str2double(get(hObject,'String'));
if val > thr || val < 0 
    val = (val > thr)*thr + (val < 0)*0;
end

val = uint16(val);
val1 = uint8(bitshift(val,-8));
val2 = uint8(mod(val,256));

update_led_intensity(handles,val1,val2,2);

% --- Executes during object creation, after setting all properties.
function LED2_Edit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to LED2_Edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function LED3_Edit_Callback(hObject, eventdata, handles)
% hObject    handle to LED3_Edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of LED3_Edit as text
%        str2double(get(hObject,'String')) returns contents of LED3_Edit as a double

thr = 9999;

val = str2double(get(hObject,'String'));
if val > thr || val < 0 
    val = (val > thr)*thr + (val < 0)*0;
end

val = uint16(val);
val1 = uint8(bitshift(val,-8));
val2 = uint8(mod(val,256));

update_led_intensity(handles,val1,val2,3);

% --- Executes during object creation, after setting all properties.
function LED3_Edit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to LED3_Edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function LED4_Edit_Callback(hObject, eventdata, handles)
% hObject    handle to LED4_Edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of LED4_Edit as text
%        str2double(get(hObject,'String')) returns contents of LED4_Edit as a double

thr = 9999;

val = str2double(get(hObject,'String'));
if val > thr || val < 0 
    val = (val > thr)*thr + (val < 0)*0;
end

val = uint16(val);
val1 = uint8(bitshift(val,-8));
val2 = uint8(mod(val,256));

update_led_intensity(handles,val1,val2,4);

% --- Executes during object creation, after setting all properties.
function LED4_Edit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to LED4_Edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function LED5_Edit_Callback(hObject, eventdata, handles)
% hObject    handle to LED5_Edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of LED5_Edit as text
%        str2double(get(hObject,'String')) returns contents of LED5_Edit as a double


thr = 9999;

val = str2double(get(hObject,'String'));
if val > thr || val < 0 
    val = (val > thr)*thr + (val < 0)*0;
end

val = uint16(val);
val1 = uint8(bitshift(val,-8));
val2 = uint8(mod(val,256));

update_led_intensity(handles,val1,val2,5);

% --- Executes during object creation, after setting all properties.
function LED5_Edit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to LED5_Edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function LED6_Edit_Callback(hObject, eventdata, handles)
% hObject    handle to LED6_Edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of LED6_Edit as text
%        str2double(get(hObject,'String')) returns contents of LED6_Edit as a double

thr = 9999;

val = str2double(get(hObject,'String'));
if val > thr || val < 0 
    val = (val > thr)*thr + (val < 0)*0;
end

val = uint16(val);
val1 = uint8(bitshift(val,-8));
val2 = uint8(mod(val,256));

update_led_intensity(handles,val1,val2,6);

% --- Executes during object creation, after setting all properties.
function LED6_Edit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to LED6_Edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes on button press in autoUpdateLEDCheckbox.
function autoUpdateLEDCheckbox_Callback(hObject, eventdata, handles)
% hObject    handle to autoUpdateLEDCheckbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of autoUpdateLEDCheckbox

function yAxisMinEdit_Callback(hObject, eventdata, handles)
% hObject    handle to yAxisMinEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of yAxisMinEdit as text
%        str2double(get(hObject,'String')) returns contents of yAxisMinEdit as a double

handles.yAxesMinEdit = str2double(get(hObject,'String'));
set(handles.dcPlotAxes,'YLim',[handles.yAxesMinEdit, handles.yAxesMaxEdit]);
guidata(hObject, handles);

% --- Executes during object creation, after setting all properties.
function yAxisMinEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to yAxisMinEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function yAxisMaxEdit_Callback(hObject, eventdata, handles)
% hObject    handle to yAxisMaxEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of yAxisMaxEdit as text
%        str2double(get(hObject,'String')) returns contents of yAxisMaxEdit as a double

handles.yAxesMaxEdit = str2double(get(hObject,'String'));
set(handles.dcPlotAxes,'YLim',[handles.yAxesMinEdit, handles.yAxesMaxEdit]);
guidata(hObject, handles);

% --- Executes during object creation, after setting all properties.
function yAxisMaxEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to yAxisMaxEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes on button press in yAxisResetButton.
function yAxisResetButton_Callback(hObject, eventdata, handles)
% hObject    handle to yAxisResetButton (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

handles.yMin = 100;
handles.yMax = 4500;
set(handles.dcPlotAxes,'YLim',[handles.yMin, handles.yMax]);

% --- Executes on button press in saveSizeEstimatesCheckbox.
function saveSizeEstimatesCheckbox_Callback(hObject, eventdata, handles)
% hObject    handle to saveSizeEstimatesCheckbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of saveSizeEstimatesCheckbox

function update_led_intensity(handles,val1,val2,n)
if get(handles.autoUpdateLEDCheckbox,'Value')
%     theta = get(handles.JawAngleEdit,'String');
%     theta = str2double(theta(regexp(theta,'\d')));
    currIntled3 = double(bitshift(uint16(val1),8) + uint16(val2));
    adaptvals(handles.serialport, currIntled3);
else
    code= zeros(20,1);
    code(1:16) = sprintf('%16s',['LED' num2str(n) '_intensity']);
    code(17) = val1;
    code(18) = val2;
    fwrite(handles.serialport,code);
end

% --- Executes on button press in indivDataSaveCheckbox.
function indivDataSaveCheckbox_Callback(hObject, eventdata, handles)
% hObject    handle to indivDataSaveCheckbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of indivDataSaveCheckbox
function VesselSizeEdit_Callback(hObject, eventdata, handles)
% hObject    handle to VesselSizeEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes during object creation, after setting all properties.
function VesselSizeEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to VesselSizeEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function ThicknessEdit_Callback(hObject, eventdata, handles)
% hObject    handle to ThicknessEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes during object creation, after setting all properties.
function ThicknessEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to ThicknessEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on selection change in VesselMenu.
function VesselMenu_Callback(hObject, eventdata, handles)
% hObject    handle to VesselMenu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns VesselMenu contents as cell array
%        contents{get(hObject,'Value')} returns selected item from VesselMenu

contents = cellstr(get(hObject,'String'));
vessel = contents{get(hObject,'Value')};
set(hObject,'UserData',vessel);
if strcmpi(vessel,'none')
    set(handles.VesselSizeEdit,'String','0mm');
end

% --- Executes during object creation, after setting all properties.
function VesselMenu_CreateFcn(hObject, eventdata, handles)
% hObject    handle to VesselMenu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on selection change in TissueMenu.
function TissueMenu_Callback(hObject, eventdata, handles)
% hObject    handle to TissueMenu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns TissueMenu contents as cell array
%        contents{get(hObject,'Value')} returns selected item from TissueMenu

contents = cellstr(get(hObject,'String'));
tissue = contents{get(hObject,'Value')};
set(hObject,'UserData',tissue);
if strcmpi(tissue,'none')
    set(handles.ThicknessEdit,'String','0mm');
end

% --- Executes during object creation, after setting all properties.
function TissueMenu_CreateFcn(hObject, eventdata, handles)
% hObject    handle to TissueMenu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function JawAngleEdit_Callback(hObject, eventdata, handles)
% hObject    handle to JawAngleEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of JawAngleEdit as text
%        str2double(get(hObject,'String')) returns contents of JawAngleEdit as a double


% --- Executes during object creation, after setting all properties.
function JawAngleEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to JawAngleEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function VesselPositionEdit_Callback(hObject, eventdata, handles)
% hObject    handle to VesselPositionEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of VesselPositionEdit as text
%        str2double(get(hObject,'String')) returns contents of VesselPositionEdit as a double


% --- Executes during object creation, after setting all properties.
function VesselPositionEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to VesselPositionEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in AutoPositionFillCheckbox.
function AutoPositionFillCheckbox_Callback(hObject, eventdata, handles)
% hObject    handle to AutoPositionFillCheckbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of AutoPositionFillCheckbox


% --- Executes on button press in UseAllLEDsCheckbox.
function UseAllLEDsCheckbox_Callback(hObject, eventdata, handles)
% hObject    handle to UseAllLEDsCheckbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of UseAllLEDsCheckbox

if ~get(hObject,'Value')
    for i = 1:6
        eval(['set(handles.LED' num2str(i) 'Checkbox,''Visible'',''on'');']);
    end
else
    for i = 1:6
        eval(['set(handles.LED' num2str(i) 'Checkbox,''Visible'',''off'');']);
    end
end

% --- Executes on button press in LED1Checkbox.
function LED1Checkbox_Callback(hObject, eventdata, handles)
% hObject    handle to LED1Checkbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of LED1Checkbox


% --- Executes on button press in LED2Checkbox.
function LED2Checkbox_Callback(hObject, eventdata, handles)
% hObject    handle to LED2Checkbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of LED2Checkbox


% --- Executes on button press in LED3Checkbox.
function LED3Checkbox_Callback(hObject, eventdata, handles)
% hObject    handle to LED3Checkbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of LED3Checkbox


% --- Executes on button press in LED4Checkbox.
function LED4Checkbox_Callback(hObject, eventdata, handles)
% hObject    handle to LED4Checkbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of LED4Checkbox


% --- Executes on button press in LED5Checkbox.
function LED5Checkbox_Callback(hObject, eventdata, handles)
% hObject    handle to LED5Checkbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of LED5Checkbox


% --- Executes on button press in LED6Checkbox.
function LED6Checkbox_Callback(hObject, eventdata, handles)
% hObject    handle to LED6Checkbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of LED6Checkbox

function BaselineEdit_Callback(hObject, eventdata, handles)
% hObject    handle to BaselineEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of BaselineEdit as text
%        str2double(get(hObject,'String')) returns contents of BaselineEdit as a double


val = str2double(get(hObject,'String'));
valtest = (val > 3500)*3500 + (val < 500)*500;

if valtest
   val = valtest;
end

set(hObject,'UserData',val);
guidata(hObject, handles);

% --- Executes during object creation, after setting all properties.
function BaselineEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to BaselineEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function DataSaveTimeEdit_Callback(hObject, eventdata, handles)
% hObject    handle to DataSaveTimeEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of DataSaveTimeEdit as text
%        str2double(get(hObject,'String')) returns contents of DataSaveTimeEdit as a double


% --- Executes during object creation, after setting all properties.
function DataSaveTimeEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to DataSaveTimeEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes on button press in SaveTrackingDataCheckbox.
function SaveTrackingDataCheckbox_Callback(hObject, eventdata, handles)
% hObject    handle to SaveTrackingDataCheckbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of SaveTrackingDataCheckbox


function CommentsEdit_Callback(hObject, eventdata, handles)
% hObject    handle to CommentsEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of CommentsEdit as text
%        str2double(get(hObject,'String')) returns contents of CommentsEdit as a double


% --- Executes during object creation, after setting all properties.
function CommentsEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to CommentsEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in ShowPumpReadingCheckbox.
function ShowPumpReadingCheckbox_Callback(hObject, eventdata, handles)
% hObject    handle to ShowPumpReadingCheckbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of ShowPumpReadingCheckbox

code = zeros(20,1);
code(1:16) = sprintf('%16s','monitor_pump');
code(17) = get(hObject,'Value');
fwrite(handles.serialport,code);


% --- Executes on button press in PumpControlButton.
function PumpControlButton_Callback(hObject, eventdata, handles)
% hObject    handle to PumpControlButton (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

set(hObject,'UserData',1-get(hObject,'UserData'));
if get(hObject,'UserData')
    set(hObject,'String', 'Turn Pump OFF', 'BackgroundColor',[0,0,0]);
else
    set(hObject,'String', 'Turn Pump ON', 'BackgroundColor',[0.5,0.5,1]);
end
code = zeros(20,1);
code(1:16) = sprintf('%16s', 'HBP_power');
code(17) = uint8(get(hObject,'UserData'));
fwrite(handles.serialport,code);

% --- Executes on button press in AutoFill_JA_Checkbox.
function AutoFill_JA_Checkbox_Callback(hObject, eventdata, handles)
% hObject    handle to AutoFill_JA_Checkbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of AutoFill_JA_Checkbox

% --- Executes when user attempts to close figure1.
function figure1_CloseRequestFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
close_button_Callback(hObject, [], handles);

% --- Executes during object creation, after setting all properties.
function dcPlotAxes_CreateFcn(hObject, eventdata, handles)
% hObject    handle to dcPlotAxes (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: place code in OpeningFcn to populate dcPlotAxes

function baselineEdit_Callback(hObject, eventdata, handles)
% hObject    handle to baselineEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of baselineEdit as text
%        str2double(get(hObject,'String')) returns contents of baselineEdit as a double


% --- Executes during object creation, after setting all properties.
function baselineEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to baselineEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in StartAutomationCheckbox.
function StartAutomationCheckbox_Callback(hObject, eventdata, handles)
% hObject    handle to StartAutomationCheckbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of StartAutomationCheckbox


% --- Executes on button press in smoothSignalCheckbox.
function smoothSignalCheckbox_Callback(hObject, eventdata, handles)
% hObject    handle to smoothSignalCheckbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of smoothSignalCheckbox


% --- Executes on button press in baseline2000.
function baseline2000_Callback(hObject, eventdata, handles)
% hObject    handle to baseline2000 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of baseline2000



% --- Executes during object creation, after setting all properties.
function baseline2000_CreateFcn(hObject, eventdata, handles)
% hObject    handle to baseline2000 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called


% --- Executes on button press in reconnectButton.
function reconnectButton_Callback(hObject, eventdata, handles)
% hObject    handle to reconnectButton (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
settings = get(handles.figure1,'UserData');
stopasync(handles.serialport);

% Issue a close in case didn't exit program cleanly during previous instance.
instrobjs = instrfind('Type', 'udp', 'Status', 'open');
for i=1:length(instrobjs)
    fclose(instrobjs(i));
end
handles.serialport.BytesAvailableFcn = {@serial_full_callback, handles.figure1, handles};

% Start things rolling.
try
    fopen(handles.serialport);
    fopen(handles.udpport);
    code=zeros(20,1);
    code(1:16) = sprintf('%16s','LED_intensity');
    fwrite(handles.serialport,code);
    readasync(handles.serialport);
catch exception
    errordlg('Please Reconnect the Board. The MATLAB seems to be having difficulty reading it','Error!');
end


% --- Executes on selection change in tool_used.
function tool_used_Callback(hObject, eventdata, handles)
% hObject    handle to tool_used (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
contents = cellstr(get(hObject,'String'));
vessel = contents{get(hObject,'Value')};
set(hObject,'UserData',vessel);

% Hints: contents = cellstr(get(hObject,'String')) returns tool_used contents as cell array
%        contents{get(hObject,'Value')} returns selected item from tool_used


% --- Executes during object creation, after setting all properties.
function tool_used_CreateFcn(hObject, eventdata, handles)
% hObject    handle to tool_used (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on selection change in scenario.
function scenario_Callback(hObject, eventdata, handles)
% hObject    handle to scenario (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns scenario contents as cell array
%        contents{get(hObject,'Value')} returns selected item from scenario


% --- Executes during object creation, after setting all properties.
function scenario_CreateFcn(hObject, eventdata, handles)
% hObject    handle to scenario (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in dataSaveButton.
function saveRealtimeData_Callback(hObject, eventdata, handles)
% hObject    handle to dataSaveButton (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
set(hObject,'UserData',1);


% --- Executes on button press in save_timer_button.
function save_timer_button_Callback(hObject, eventdata, handles)
% hObject    handle to save_timer_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
set(handles.dataSaveButton, 'Value', 1);
t = timer('TimerFcn', {@save_timer_callback, hObject, handles}, ...
                        'Period', 1, 'ExecutionMode', 'fixedRate');
hObject.UserData = 120;
start(t); 

function save_timer_callback(obj,~,hObject,handles)
if hObject.UserData < 0
    set(hObject, 'String', 'Save RT Data (2min)')
    set(handles.dataSaveButton, 'Value', 0);
    stop(obj);s
else
    set(hObject, 'String', num2str(hObject.UserData));
    hObject.UserData = hObject.UserData - 1;
end


% --- Executes on button press in dtb_button.
function dtb_button_Callback(hObject, eventdata, handles)
% hObject    handle to dtb_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
dtb_interface2(handles.figure1)


% --- Executes on selection change in Condition.
function Condition_Callback(hObject, eventdata, handles)
% hObject    handle to Condition (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns Condition contents as cell array
%        contents{get(hObject,'Value')} returns selected item from Condition


% --- Executes during object creation, after setting all properties.
function Condition_CreateFcn(hObject, eventdata, handles)
% hObject    handle to Condition (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end
