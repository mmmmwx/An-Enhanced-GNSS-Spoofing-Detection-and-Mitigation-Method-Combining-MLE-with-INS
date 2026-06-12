<<<<<<< HEAD
function [trackResults, channel]= tracking_mitigation(fid, channel, settings)
% Performs code and carrier tracking for all channels.
%
%[trackResults, channel] = tracking(fid, channel, settings)
%
%   Inputs:
%       fid             - file identifier of the signal record.
%       channel         - PRN, carrier frequencies and code phases of all
%                       satellites to be tracked (prepared by preRum.m from
%                       acquisition results).
%       settings        - receiver settings.
%   Outputs:
%       trackResults    - tracking results (structure array). Contains
%                       in-phase prompt outputs and absolute spreading
%                       code's starting positions, together with other
%                       observation data from the tracking loops. All are
%                       saved every millisecond.

%--------------------------------------------------------------------------
%                         CU Multi-GNSS SDR  
% (C) Updated by Yafeng Li, Nagaraj C. Shivaramaiah and Dennis M. Akos
% Based on the original work by Darius Plausinaitis,Peter Rinder, 
% Nicolaj Bertelsen and Dennis M. Akos
%--------------------------------------------------------------------------

%This program is free software; you can redistribute it and/or
%modify it under the terms of the GNU General Public License
%as published by the Free Software Foundation; either version 2
%of the License, or (at your option) any later version.
%
%This program is distributed in the hope that it will be useful,
%but WITHOUT ANY WARRANTY; without even the implied warranty of
%MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%GNU General Public License for more details.
%
%You should have received a copy of the GNU General Public License
%along with this program; if not, write to the Free Software
%Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
%USA.
%--------------------------------------------------------------------------

%CVS record:
%$Id: tracking.m,v 1.14.2.31 2006/08/14 11:38:22 dpl Exp $

%% Initialize result structure ============================================

% Channel status
trackResults.status         = '-';      % No tracked signal, or lost lock

% The absolute sample in the record of the C/A code start:
trackResults.absoluteSample = zeros(1, settings.msToProcess);

% Freq of the PRN code:
trackResults.codeFreq       = inf(1, settings.msToProcess);

% Frequency of the tracked carrier wave:
trackResults.carrFreq       = inf(1, settings.msToProcess);

% Outputs from the correlators (In-phase):
trackResults.I_P            = zeros(1, settings.msToProcess);
trackResults.I_E            = zeros(1, settings.msToProcess);
trackResults.I_L            = zeros(1, settings.msToProcess);

% Outputs from the correlators (Quadrature-phase):
trackResults.Q_E            = zeros(1, settings.msToProcess);
trackResults.Q_P            = zeros(1, settings.msToProcess);
trackResults.Q_L            = zeros(1, settings.msToProcess);

% Loop discriminators
trackResults.dllDiscr       = inf(1, settings.msToProcess);
trackResults.dllDiscrFilt   = inf(1, settings.msToProcess);
trackResults.pllDiscr       = inf(1, settings.msToProcess);
trackResults.pllDiscrFilt   = inf(1, settings.msToProcess);

% Remain code and carrier phase
trackResults.remCodePhase       = inf(1, settings.msToProcess);
trackResults.remCarrPhase       = inf(1, settings.msToProcess);

% multicorrelator
M=20;  % the number of correlators 
trackResults.ACC        = zeros(4*M+1, settings.msToProcess);
trackResults.ACC_mitigation        = zeros(4*M+1, settings.msToProcess);

space = 1/M;     % correlator space 

%C/No
trackResults.CNo.VSMValue = ...
    zeros(1,floor(settings.msToProcess/settings.CNo.VSMinterval));
trackResults.CNo.VSMIndex = ...
    zeros(1,floor(settings.msToProcess/settings.CNo.VSMinterval));

%--- Copy initial settings for all channels -------------------------------
trackResults = repmat(trackResults, 1, settings.numberOfChannels);

%% Initialize tracking variables ==========================================
load('L_2chips.mat') 
load('H_2chips.mat') 
load('inv_Q_2chips.mat') 

% Signal period to be processed
codePeriods = settings.msToProcess;     % For GPS one C/A code is one ms

%--- DLL variables --------------------------------------------------------
% Define early-late offset (in chips)
earlyLateSpc = settings.dllCorrelatorSpacing;

% Summation interval
PDIcode = settings.intTime;

% Calculate filter coefficient values
[tau1code, tau2code] = calcLoopCoef(settings.dllNoiseBandwidth, ...
    settings.dllDampingRatio, ...
    1.0);

%--- PLL variables --------------------------------------------------------
% Summation interval
PDIcarr = settings.intTime;

% Calculate filter coefficient values
[tau1carr, tau2carr] = calcLoopCoef(settings.pllNoiseBandwidth, ...
                                    settings.pllDampingRatio, 0.25);
% -------- Number of acqusired signals ------------------------------------
TrackedNr =0 ;
for channelNr = 1:settings.numberOfChannels
    if channel(channelNr).status == 'T'
        TrackedNr = TrackedNr+1;
    end
end

% Start waitbar
hwb = waitbar(0,'Tracking...');

%Adjust the size of the waitbar to insert text
CNoPos=get(hwb,'Position');
set(hwb,'Position',[CNoPos(1),CNoPos(2),CNoPos(3),90],'Visible','on');

if (settings.fileType==1)
    dataAdaptCoeff=1;
else
    dataAdaptCoeff=2;
end
%% Start processing channels ==============================================
for channelNr = 1:settings.numberOfChannels
    
    % Only process if PRN is non zero (acquisition was successful)
    if (channel(channelNr).PRN ~= 0)
    % % Save additional information - each channel's tracked PRN
        trackResults(channelNr).PRN     = channel(channelNr).PRN;

        % Move the starting point of processing. Can be used to start the
        % signal processing at any point in the data record (e.g. for long
        % records). In addition skip through that data file to start at the
        % appropriate sample (corresponding to code phase). Assumes sample
        % type is schar (or 1 byte per sample)

        if strcmp(settings.dataType,'int16')
            fseek(fid, ...
                dataAdaptCoeff*((channel(channelNr).codePhase)*2), ...
                'bof');
        else
            fseek(fid, ...
                dataAdaptCoeff*( channel(channelNr).codePhase-1), ...
                'bof');
        end


        % Get a vector with the C/A code sampled 1x/chip
        caCode = generateCAcode(channel(channelNr).PRN);
        % Then make it possible to do early and late versions
        caCode = [caCode(1023) caCode caCode(1)];

        %--- Perform various initializations ------------------------------
        if settings.mitigation
        % define initial code frequency basis of NCO
            codeFreq      = channel(channelNr).codeFreq;
            % define residual code phase (in chips)
            remCodePhase  = channel(channelNr).remCodePhase;
            % define carrier frequency which is used over whole tracking period
            carrFreq      = channel(channelNr).acquiredFreq;
            carrFreqBasis = channel(channelNr).acquiredFreq;
            % define residua carrier phase
            remCarrPhase  = channel(channelNr).remCarrPhase;
    
            %code tracking loop parameters
            oldCodeNco   =  channel(channelNr).oldCodeNco;
            oldCodeError = channel(channelNr).oldCodeError;
    
            %carrier/Costas loop parameters
            oldCarrNco   = channel(channelNr).oldCarrNco;
            oldCarrError = channel(channelNr).oldCarrError;
        else
            codeFreq      = settings.codeFreqBasis;
            % define residual code phase (in chips)
            remCodePhase  = 0.0;
            % define carrier frequency which is used over whole tracking period
            carrFreq      = channel(channelNr).acquiredFreq;
            carrFreqBasis = channel(channelNr).acquiredFreq;
            % define residual carrier phase
            remCarrPhase  = 0.0;
    
            %code tracking loop parameters
            oldCodeNco   = 0.0;
            oldCodeError = 0.0;
    
            %carrier/Costas loop parameters
            oldCarrNco   = 0.0;
            oldCarrError = 0.0;
        end
%%
        %C/No computation
        vsmCnt  = 0;CNo = 0;

        %=== Process the number of specified code periods =================
        for loopCnt =  1:codePeriods

            %% GUI update -------------------------------------------------------------
            % The GUI is updated every 50ms. This way Matlab GUI is still
            % responsive enough. At the same time Matlab is not occupied
            % all the time with GUI task.
            if (rem(loopCnt, 50) == 0)

                Ln = newline;
                trackingStatus=['Tracking: Ch ', int2str(channelNr), ...
                    ' of ', int2str(TrackedNr),Ln ...
                    'PRN: ', int2str(channel(channelNr).PRN),Ln ...
                    'Completed ',int2str(loopCnt), ...
                    ' of ', int2str(codePeriods), ' msec',Ln...
                    'C/No: ',CNo,' (dB-Hz)'];

                try
                    waitbar(loopCnt/codePeriods,hwb,trackingStatus);
                catch
                    % The progress bar was closed. It is used as a signal
                    % to stop, "cancel" processing. Exit.
                    disp('Progress bar closed, exiting...');
                    return
                end
            end

            %% Read next block of data ------------------------------------------------
            % Record sample number (based on 8bit samples)
            if strcmp(settings.dataType,'int16')
                trackResults(channelNr).absoluteSample(loopCnt) =(ftell(fid))/dataAdaptCoeff/2;
            else
                trackResults(channelNr).absoluteSample(loopCnt) =(ftell(fid))/dataAdaptCoeff;
            end
            % Update the phasestep based on code freq (variable) and
            % sampling frequency (fixed)
            codePhaseStep = codeFreq / settings.samplingFreq;
            
            % Find the size of a "block" or code period in whole samples
            blksize = ceil((settings.codeLength-remCodePhase) / codePhaseStep);

            % Read in the appropriate number of samples to process this
            % interation
            [rawSignal, samplesRead] = fread(fid, ...
                dataAdaptCoeff*blksize, settings.dataType);

            rawSignal = rawSignal';

            % For complex data 
            if (dataAdaptCoeff==2)
                rawSignal1=rawSignal(1:2:end);
                rawSignal2=rawSignal(2:2:end);
                rawSignal = rawSignal1 + 1i .* rawSignal2;  % transpose vector
            end


            % If did not read in enough samples, then could be out of
            % data - better exit
            if (samplesRead ~= dataAdaptCoeff*blksize)
                disp('Not able to read the specified number of samples  for tracking, exiting!')
                delete(hwb);
                return
            end

            %% Set up all the code phase tracking information -------------------------
            % Save remCodePhase for current correlation


            code_ML = zeros(4*M+1,blksize);
            for code_chips = 1:4*M+1
                phase_i = code_chips*space -(2+space);
                tcode   = (remCodePhase+phase_i) : ...
                    codePhaseStep : ...
                    ((blksize-1)*codePhaseStep+remCodePhase+phase_i);
                tcode2  = mod(floor(tcode),1023) + 1;%由码相位决定该采样点位于caCode的第几个chip内
                code_ML(code_chips,:) = caCode(tcode2);
            end
             remCodePhase = blksize*codePhaseStep+remCodePhase - 1023.0;
    
            %% Generate the carrier frequency to mix the signal to baseband -----------
            % Save remCarrPhase for current correlation


            % Get the argument to sin/cos functions
            time    = (0:blksize) ./ settings.samplingFreq;
            trigarg = ((carrFreq * 2.0 * pi) .* time) + remCarrPhase;
            % Remaining carrier phase for each tracking update
            remCarrPhase = rem(trigarg(blksize+1), (2 * pi));

            % Finally compute the signal to mix the collected data to
            % bandband
            carrsig = exp(-1i .* trigarg(1:blksize));
            BasebandSignal = carrsig .* rawSignal;
 %% Generate the six standard accumulated values ---------------------------
            ACC_total =  zeros(4*M+1, 1);
            for code_chips = 1:4*M+1
                ACC_total(code_chips) =  sum(code_ML(code_chips,:)  .* BasebandSignal);
            end
            % 
            % hold on
            % plot(abs(ACC_total))
            trackResults(channelNr).ACC(:,loopCnt)=ACC_total';
 %% Spoofing mitigation
            if settings.mitigation

                [AuSpoof_index,AuSpoof_amp]=Grid_medll(ACC_total,L_2chips,H_2chips,inv_Q_2chips);
    
                ACC_mitigation=ACC_total-AuSpoof_amp(2)*AutoCorr_CA([-2:space:2]-(AuSpoof_index(2)-M*2-1)/M );
    
                trackResults(channelNr).ACC_mitigation(:,loopCnt)=ACC_mitigation';

                % Now get early, late, and prompt values for each
                I_E = real(ACC_mitigation(1.5*M+1));
                Q_E = imag(ACC_mitigation(1.5*M+1));
                I_P = real(ACC_mitigation(2*M+1));
                Q_P = imag(ACC_mitigation(2*M+1));
                I_L = real(ACC_mitigation(2.5*M+1));
                Q_L = imag(ACC_mitigation(2.5*M+1));
            else 

                I_E = real(ACC_total(1.5*M+1));
                Q_E = imag(ACC_total(1.5*M+1));
                I_P = real(ACC_total(2*M+1));
                Q_P = imag(ACC_total(2*M+1));
                I_L = real(ACC_total(2.5*M+1));
                Q_L = imag(ACC_total(2.5*M+1));
            end
            %% Find PLL error and update carrier NCO ----------------------------------

            % Implement carrier loop discriminator (phase detector)
            carrError = atan(Q_P / I_P) / (2.0 * pi);

            % Implement carrier loop filter and generate NCO command
            carrNco = oldCarrNco + (tau2carr/tau1carr) * ...
                (carrError - oldCarrError) + carrError * (PDIcarr/tau1carr);
            oldCarrNco   = carrNco;
            oldCarrError = carrError;

            % Save carrier frequency for current correlation
            trackResults(channelNr).carrFreq(loopCnt) = carrFreq;

            % Modify carrier freq based on NCO command
            carrFreq = carrFreqBasis + carrNco;

            

            %% Find DLL error and update code NCO -------------------------------------
            codeError = (sqrt(I_E * I_E + Q_E * Q_E) - sqrt(I_L * I_L + Q_L * Q_L)) / ...
                (sqrt(I_E * I_E + Q_E * Q_E) + sqrt(I_L * I_L + Q_L * Q_L));

            % Implement code loop filter and generate NCO command
            codeNco = oldCodeNco + (tau2code/tau1code) * ...
                (codeError - oldCodeError) + (codeError+oldCodeError) * (PDIcode/tau1code/2);
            oldCodeNco   = codeNco;
            oldCodeError = codeError;

            % Save code frequency for current correlation
            codeFreq = settings.codeFreqBasis - codeNco;

            trackResults(channelNr).codeFreq(loopCnt) = codeFreq;
            % Modify code freq based on NCO command

            %% Record various measures to show in postprocessing ----------------------
            trackResults(channelNr).remCodePhase(loopCnt) = remCodePhase;
            trackResults(channelNr).remCarrPhase(loopCnt) = remCarrPhase;

            trackResults(channelNr).dllDiscr(loopCnt)       = codeError;
            trackResults(channelNr).dllDiscrFilt(loopCnt)   = codeNco;
            trackResults(channelNr).pllDiscr(loopCnt)       = carrError;
            trackResults(channelNr).pllDiscrFilt(loopCnt)   = carrNco;

            trackResults(channelNr).I_E(loopCnt) = I_E;
            trackResults(channelNr).I_P(loopCnt) = I_P;
            trackResults(channelNr).I_L(loopCnt) = I_L;
            trackResults(channelNr).Q_E(loopCnt) = Q_E;
            trackResults(channelNr).Q_P(loopCnt) = Q_P;
            trackResults(channelNr).Q_L(loopCnt) = Q_L;

            %% CNo calculation --------------------------------------
            if (rem(loopCnt,settings.CNo.VSMinterval)==0)
                vsmCnt=vsmCnt+1;
                CNoValue=CNoVSM(trackResults(channelNr).I_P(loopCnt-settings.CNo.VSMinterval+1:loopCnt),...
                    trackResults(channelNr).Q_P(loopCnt-settings.CNo.VSMinterval+1:loopCnt),settings.CNo.accTime);
                trackResults(channelNr).CNo.VSMValue(vsmCnt)=CNoValue;
                trackResults(channelNr).CNo.VSMIndex(vsmCnt)=loopCnt;
                CNo=int2str(CNoValue);
            end

        end % for loopCnt

        % If we got so far, this means that the tracking was successful
        % Now we only copy status, but it can be update by a lock detector
        % if implemented
        trackResults(channelNr).status  = channel(channelNr).status;

    end % if a PRN is assigned
end % for channelNr

% Close the waitbar
close(hwb)
=======
function [trackResults, channel]= tracking_mitigation(fid, channel, settings)
% Performs code and carrier tracking for all channels.
%
%[trackResults, channel] = tracking(fid, channel, settings)
%
%   Inputs:
%       fid             - file identifier of the signal record.
%       channel         - PRN, carrier frequencies and code phases of all
%                       satellites to be tracked (prepared by preRum.m from
%                       acquisition results).
%       settings        - receiver settings.
%   Outputs:
%       trackResults    - tracking results (structure array). Contains
%                       in-phase prompt outputs and absolute spreading
%                       code's starting positions, together with other
%                       observation data from the tracking loops. All are
%                       saved every millisecond.

%--------------------------------------------------------------------------
%                         CU Multi-GNSS SDR  
% (C) Updated by Yafeng Li, Nagaraj C. Shivaramaiah and Dennis M. Akos
% Based on the original work by Darius Plausinaitis,Peter Rinder, 
% Nicolaj Bertelsen and Dennis M. Akos
%--------------------------------------------------------------------------

%This program is free software; you can redistribute it and/or
%modify it under the terms of the GNU General Public License
%as published by the Free Software Foundation; either version 2
%of the License, or (at your option) any later version.
%
%This program is distributed in the hope that it will be useful,
%but WITHOUT ANY WARRANTY; without even the implied warranty of
%MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%GNU General Public License for more details.
%
%You should have received a copy of the GNU General Public License
%along with this program; if not, write to the Free Software
%Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
%USA.
%--------------------------------------------------------------------------

%CVS record:
%$Id: tracking.m,v 1.14.2.31 2006/08/14 11:38:22 dpl Exp $

%% Initialize result structure ============================================

% Channel status
trackResults.status         = '-';      % No tracked signal, or lost lock

% The absolute sample in the record of the C/A code start:
trackResults.absoluteSample = zeros(1, settings.msToProcess);

% Freq of the PRN code:
trackResults.codeFreq       = inf(1, settings.msToProcess);

% Frequency of the tracked carrier wave:
trackResults.carrFreq       = inf(1, settings.msToProcess);

% Outputs from the correlators (In-phase):
trackResults.I_P            = zeros(1, settings.msToProcess);
trackResults.I_E            = zeros(1, settings.msToProcess);
trackResults.I_L            = zeros(1, settings.msToProcess);

% Outputs from the correlators (Quadrature-phase):
trackResults.Q_E            = zeros(1, settings.msToProcess);
trackResults.Q_P            = zeros(1, settings.msToProcess);
trackResults.Q_L            = zeros(1, settings.msToProcess);

% Loop discriminators
trackResults.dllDiscr       = inf(1, settings.msToProcess);
trackResults.dllDiscrFilt   = inf(1, settings.msToProcess);
trackResults.pllDiscr       = inf(1, settings.msToProcess);
trackResults.pllDiscrFilt   = inf(1, settings.msToProcess);

% Remain code and carrier phase
trackResults.remCodePhase       = inf(1, settings.msToProcess);
trackResults.remCarrPhase       = inf(1, settings.msToProcess);

% multicorrelator
M=20;  % the number of correlators 
trackResults.ACC        = zeros(4*M+1, settings.msToProcess);
trackResults.ACC_mitigation        = zeros(4*M+1, settings.msToProcess);

space = 1/M;     % correlator space 

%C/No
trackResults.CNo.VSMValue = ...
    zeros(1,floor(settings.msToProcess/settings.CNo.VSMinterval));
trackResults.CNo.VSMIndex = ...
    zeros(1,floor(settings.msToProcess/settings.CNo.VSMinterval));

%--- Copy initial settings for all channels -------------------------------
trackResults = repmat(trackResults, 1, settings.numberOfChannels);

%% Initialize tracking variables ==========================================
load('L_2chips.mat') 
load('H_2chips.mat') 
load('inv_Q_2chips.mat') 

% Signal period to be processed
codePeriods = settings.msToProcess;     % For GPS one C/A code is one ms

%--- DLL variables --------------------------------------------------------
% Define early-late offset (in chips)
earlyLateSpc = settings.dllCorrelatorSpacing;

% Summation interval
PDIcode = settings.intTime;

% Calculate filter coefficient values
[tau1code, tau2code] = calcLoopCoef(settings.dllNoiseBandwidth, ...
    settings.dllDampingRatio, ...
    1.0);

%--- PLL variables --------------------------------------------------------
% Summation interval
PDIcarr = settings.intTime;

% Calculate filter coefficient values
[tau1carr, tau2carr] = calcLoopCoef(settings.pllNoiseBandwidth, ...
                                    settings.pllDampingRatio, 0.25);
% -------- Number of acqusired signals ------------------------------------
TrackedNr =0 ;
for channelNr = 1:settings.numberOfChannels
    if channel(channelNr).status == 'T'
        TrackedNr = TrackedNr+1;
    end
end

% Start waitbar
hwb = waitbar(0,'Tracking...');

%Adjust the size of the waitbar to insert text
CNoPos=get(hwb,'Position');
set(hwb,'Position',[CNoPos(1),CNoPos(2),CNoPos(3),90],'Visible','on');

if (settings.fileType==1)
    dataAdaptCoeff=1;
else
    dataAdaptCoeff=2;
end
%% Start processing channels ==============================================
for channelNr = 1:settings.numberOfChannels
    
    % Only process if PRN is non zero (acquisition was successful)
    if (channel(channelNr).PRN ~= 0)
    % % Save additional information - each channel's tracked PRN
        trackResults(channelNr).PRN     = channel(channelNr).PRN;

        % Move the starting point of processing. Can be used to start the
        % signal processing at any point in the data record (e.g. for long
        % records). In addition skip through that data file to start at the
        % appropriate sample (corresponding to code phase). Assumes sample
        % type is schar (or 1 byte per sample)

        if strcmp(settings.dataType,'int16')
            fseek(fid, ...
                dataAdaptCoeff*((channel(channelNr).codePhase)*2), ...
                'bof');
        else
            fseek(fid, ...
                dataAdaptCoeff*( channel(channelNr).codePhase-1), ...
                'bof');
        end


        % Get a vector with the C/A code sampled 1x/chip
        caCode = generateCAcode(channel(channelNr).PRN);
        % Then make it possible to do early and late versions
        caCode = [caCode(1023) caCode caCode(1)];

        %--- Perform various initializations ------------------------------
        if settings.mitigation
        % define initial code frequency basis of NCO
            codeFreq      = channel(channelNr).codeFreq;
            % define residual code phase (in chips)
            remCodePhase  = channel(channelNr).remCodePhase;
            % define carrier frequency which is used over whole tracking period
            carrFreq      = channel(channelNr).acquiredFreq;
            carrFreqBasis = channel(channelNr).acquiredFreq;
            % define residua carrier phase
            remCarrPhase  = channel(channelNr).remCarrPhase;
    
            %code tracking loop parameters
            oldCodeNco   =  channel(channelNr).oldCodeNco;
            oldCodeError = channel(channelNr).oldCodeError;
    
            %carrier/Costas loop parameters
            oldCarrNco   = channel(channelNr).oldCarrNco;
            oldCarrError = channel(channelNr).oldCarrError;
        else
            codeFreq      = settings.codeFreqBasis;
            % define residual code phase (in chips)
            remCodePhase  = 0.0;
            % define carrier frequency which is used over whole tracking period
            carrFreq      = channel(channelNr).acquiredFreq;
            carrFreqBasis = channel(channelNr).acquiredFreq;
            % define residual carrier phase
            remCarrPhase  = 0.0;
    
            %code tracking loop parameters
            oldCodeNco   = 0.0;
            oldCodeError = 0.0;
    
            %carrier/Costas loop parameters
            oldCarrNco   = 0.0;
            oldCarrError = 0.0;
        end
%%
        %C/No computation
        vsmCnt  = 0;CNo = 0;

        %=== Process the number of specified code periods =================
        for loopCnt =  1:codePeriods

            %% GUI update -------------------------------------------------------------
            % The GUI is updated every 50ms. This way Matlab GUI is still
            % responsive enough. At the same time Matlab is not occupied
            % all the time with GUI task.
            if (rem(loopCnt, 50) == 0)

                Ln = newline;
                trackingStatus=['Tracking: Ch ', int2str(channelNr), ...
                    ' of ', int2str(TrackedNr),Ln ...
                    'PRN: ', int2str(channel(channelNr).PRN),Ln ...
                    'Completed ',int2str(loopCnt), ...
                    ' of ', int2str(codePeriods), ' msec',Ln...
                    'C/No: ',CNo,' (dB-Hz)'];

                try
                    waitbar(loopCnt/codePeriods,hwb,trackingStatus);
                catch
                    % The progress bar was closed. It is used as a signal
                    % to stop, "cancel" processing. Exit.
                    disp('Progress bar closed, exiting...');
                    return
                end
            end

            %% Read next block of data ------------------------------------------------
            % Record sample number (based on 8bit samples)
            if strcmp(settings.dataType,'int16')
                trackResults(channelNr).absoluteSample(loopCnt) =(ftell(fid))/dataAdaptCoeff/2;
            else
                trackResults(channelNr).absoluteSample(loopCnt) =(ftell(fid))/dataAdaptCoeff;
            end
            % Update the phasestep based on code freq (variable) and
            % sampling frequency (fixed)
            codePhaseStep = codeFreq / settings.samplingFreq;
            
            % Find the size of a "block" or code period in whole samples
            blksize = ceil((settings.codeLength-remCodePhase) / codePhaseStep);

            % Read in the appropriate number of samples to process this
            % interation
            [rawSignal, samplesRead] = fread(fid, ...
                dataAdaptCoeff*blksize, settings.dataType);

            rawSignal = rawSignal';

            % For complex data 
            if (dataAdaptCoeff==2)
                rawSignal1=rawSignal(1:2:end);
                rawSignal2=rawSignal(2:2:end);
                rawSignal = rawSignal1 + 1i .* rawSignal2;  % transpose vector
            end


            % If did not read in enough samples, then could be out of
            % data - better exit
            if (samplesRead ~= dataAdaptCoeff*blksize)
                disp('Not able to read the specified number of samples  for tracking, exiting!')
                delete(hwb);
                return
            end

            %% Set up all the code phase tracking information -------------------------
            % Save remCodePhase for current correlation


            code_ML = zeros(4*M+1,blksize);
            for code_chips = 1:4*M+1
                phase_i = code_chips*space -(2+space);
                tcode   = (remCodePhase+phase_i) : ...
                    codePhaseStep : ...
                    ((blksize-1)*codePhaseStep+remCodePhase+phase_i);
                tcode2  = mod(floor(tcode),1023) + 1;%由码相位决定该采样点位于caCode的第几个chip内
                code_ML(code_chips,:) = caCode(tcode2);
            end
             remCodePhase = blksize*codePhaseStep+remCodePhase - 1023.0;
    
            %% Generate the carrier frequency to mix the signal to baseband -----------
            % Save remCarrPhase for current correlation


            % Get the argument to sin/cos functions
            time    = (0:blksize) ./ settings.samplingFreq;
            trigarg = ((carrFreq * 2.0 * pi) .* time) + remCarrPhase;
            % Remaining carrier phase for each tracking update
            remCarrPhase = rem(trigarg(blksize+1), (2 * pi));

            % Finally compute the signal to mix the collected data to
            % bandband
            carrsig = exp(-1i .* trigarg(1:blksize));
            BasebandSignal = carrsig .* rawSignal;
 %% Generate the six standard accumulated values ---------------------------
            ACC_total =  zeros(4*M+1, 1);
            for code_chips = 1:4*M+1
                ACC_total(code_chips) =  sum(code_ML(code_chips,:)  .* BasebandSignal);
            end
            % 
            % hold on
            % plot(abs(ACC_total))
            trackResults(channelNr).ACC(:,loopCnt)=ACC_total';
 %% Spoofing mitigation
            if settings.mitigation

                [AuSpoof_index,AuSpoof_amp]=Grid_medll(ACC_total,L_2chips,H_2chips,inv_Q_2chips);
    
                ACC_mitigation=ACC_total-AuSpoof_amp(2)*AutoCorr_CA([-2:space:2]-(AuSpoof_index(2)-M*2-1)/M );
    
                trackResults(channelNr).ACC_mitigation(:,loopCnt)=ACC_mitigation';

                % Now get early, late, and prompt values for each
                I_E = real(ACC_mitigation(1.5*M+1));
                Q_E = imag(ACC_mitigation(1.5*M+1));
                I_P = real(ACC_mitigation(2*M+1));
                Q_P = imag(ACC_mitigation(2*M+1));
                I_L = real(ACC_mitigation(2.5*M+1));
                Q_L = imag(ACC_mitigation(2.5*M+1));
            else 

                I_E = real(ACC_total(1.5*M+1));
                Q_E = imag(ACC_total(1.5*M+1));
                I_P = real(ACC_total(2*M+1));
                Q_P = imag(ACC_total(2*M+1));
                I_L = real(ACC_total(2.5*M+1));
                Q_L = imag(ACC_total(2.5*M+1));
            end
            %% Find PLL error and update carrier NCO ----------------------------------

            % Implement carrier loop discriminator (phase detector)
            carrError = atan(Q_P / I_P) / (2.0 * pi);

            % Implement carrier loop filter and generate NCO command
            carrNco = oldCarrNco + (tau2carr/tau1carr) * ...
                (carrError - oldCarrError) + carrError * (PDIcarr/tau1carr);
            oldCarrNco   = carrNco;
            oldCarrError = carrError;

            % Save carrier frequency for current correlation
            trackResults(channelNr).carrFreq(loopCnt) = carrFreq;

            % Modify carrier freq based on NCO command
            carrFreq = carrFreqBasis + carrNco;

            

            %% Find DLL error and update code NCO -------------------------------------
            codeError = (sqrt(I_E * I_E + Q_E * Q_E) - sqrt(I_L * I_L + Q_L * Q_L)) / ...
                (sqrt(I_E * I_E + Q_E * Q_E) + sqrt(I_L * I_L + Q_L * Q_L));

            % Implement code loop filter and generate NCO command
            codeNco = oldCodeNco + (tau2code/tau1code) * ...
                (codeError - oldCodeError) + (codeError+oldCodeError) * (PDIcode/tau1code/2);
            oldCodeNco   = codeNco;
            oldCodeError = codeError;

            % Save code frequency for current correlation
            codeFreq = settings.codeFreqBasis - codeNco;

            trackResults(channelNr).codeFreq(loopCnt) = codeFreq;
            % Modify code freq based on NCO command

            %% Record various measures to show in postprocessing ----------------------
            trackResults(channelNr).remCodePhase(loopCnt) = remCodePhase;
            trackResults(channelNr).remCarrPhase(loopCnt) = remCarrPhase;

            trackResults(channelNr).dllDiscr(loopCnt)       = codeError;
            trackResults(channelNr).dllDiscrFilt(loopCnt)   = codeNco;
            trackResults(channelNr).pllDiscr(loopCnt)       = carrError;
            trackResults(channelNr).pllDiscrFilt(loopCnt)   = carrNco;

            trackResults(channelNr).I_E(loopCnt) = I_E;
            trackResults(channelNr).I_P(loopCnt) = I_P;
            trackResults(channelNr).I_L(loopCnt) = I_L;
            trackResults(channelNr).Q_E(loopCnt) = Q_E;
            trackResults(channelNr).Q_P(loopCnt) = Q_P;
            trackResults(channelNr).Q_L(loopCnt) = Q_L;

            %% CNo calculation --------------------------------------
            if (rem(loopCnt,settings.CNo.VSMinterval)==0)
                vsmCnt=vsmCnt+1;
                CNoValue=CNoVSM(trackResults(channelNr).I_P(loopCnt-settings.CNo.VSMinterval+1:loopCnt),...
                    trackResults(channelNr).Q_P(loopCnt-settings.CNo.VSMinterval+1:loopCnt),settings.CNo.accTime);
                trackResults(channelNr).CNo.VSMValue(vsmCnt)=CNoValue;
                trackResults(channelNr).CNo.VSMIndex(vsmCnt)=loopCnt;
                CNo=int2str(CNoValue);
            end

        end % for loopCnt

        % If we got so far, this means that the tracking was successful
        % Now we only copy status, but it can be update by a lock detector
        % if implemented
        trackResults(channelNr).status  = channel(channelNr).status;

    end % if a PRN is assigned
end % for channelNr

% Close the waitbar
close(hwb)
>>>>>>> dd185dbd3df17ab91cd383b9d2fdb82a32048e8f
