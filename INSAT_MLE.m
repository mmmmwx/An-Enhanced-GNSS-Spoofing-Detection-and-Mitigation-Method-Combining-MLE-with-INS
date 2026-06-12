function [INSATsetting,Rx,trackResults] = INSAT_MLE(fid, channel,trackRes,navSolutions,eph,activeChnList,svTimeTable, settings)
    activeChnList=activeChnList(1:settings.numberOfChannels);
%% Initialize result structure ============================================
    %INS measurements
    load('L_2chips.mat') 
    load('H_2chips.mat') 
    load('inv_Q_2chips.mat') 
    addpath 'insfunctions'
    
    [Rx,INSATsetting] = initINSATsetting_mitigation(settings,channel,trackRes,svTimeTable,activeChnList,navSolutions);
    
    % Channel status
    trackResults.status         = '-';      % No tracked signal, or lost lock
    % The absolute sample in the record of the Rx.C/A code start:
    trackResults.absoluteSample = zeros(1, INSATsetting.tracklength);
    % Freq of the Rx.C/A code:
    trackResults.codeFreq       = inf(1, INSATsetting.tracklength);
    % Frequency of the tracked carrier wave:
    trackResults.carrFreq       = inf(1, INSATsetting.tracklength);
    % Outputs from the correlators (In-phase):
    trackResults.I_P            = zeros(1, INSATsetting.tracklength);
    trackResults.I_E            = zeros(1, INSATsetting.tracklength);
    trackResults.I_L            = zeros(1, INSATsetting.tracklength);
    % Outputs from the correlators (Quadrature-phase):
    trackResults.Q_E            = zeros(1, INSATsetting.tracklength);
    trackResults.Q_P            = zeros(1, INSATsetting.tracklength);
    trackResults.Q_L            = zeros(1, INSATsetting.tracklength);
    % Loop discriminators
    trackResults.dllDiscr       = inf(1, INSATsetting.tracklength);
    trackResults.dllDiscrFilt       = inf(1, INSATsetting.tracklength);
    trackResults.pllDiscr       = inf(1, INSATsetting.tracklength);
    trackResults.pllDiscrFilt       = inf(1, INSATsetting.tracklength);
    % Remain code and carrier phase
    trackResults.remCodePhase       = inf(1, settings.msToProcess);
    trackResults.remCarrPhase       = inf(1, settings.msToProcess);
    % C/No
    trackResults.CNo.VSMValue = ...
        zeros(1,floor(INSATsetting.tracklength/settings.CNo.VSMinterval));
    trackResults.CNo.VSMIndex = ...
        zeros(1,floor(INSATsetting.tracklength/settings.CNo.VSMinterval));
    trackResults.CNo.PRMValue=0; %To avoid error message when
    trackResults.CNo.PRMIndex=0; %tracking window is closed before completion.
    %--- Multi-Correlator
    % multicorrelator
    M=20;
    trackResults.ACC        = zeros(4*M+1, settings.msToProcess);
    trackResults.ACC_mitigation        = zeros(4*M+1, settings.msToProcess);
    space = 1/M;     
    %--- Spoofing mitigation
    trackResults.dist_code=zeros(1, INSATsetting.tracklength); %tracking window is closed before completion.
    %--- Copy initial settings for all channels -------------------------------
    trackResults = repmat(trackResults, 1, settings.numberOfChannels);
    %% Initialize tracking variables ==========================================
    %--- DLL variables --------------------------------------------------------
    % Define early-late offset (in chips)
    earlyLateSpc = settings.dllCorrelatorSpacing;
    % Summation interval
    INSATsetting.pdicode = settings.intTime;
    % Calculate filter coefficient values
    [tau1code, tau2code] = calcLoopCoef(settings.dllNoiseBandwidth, settings.dllDampingRatio, 1.0);
    %--- PLL variables --------------------------------------------------------
    % Summation interval
    INSATsetting.pdicarr = settings.intTime;
    % Calculate filter coefficient values
    [tau1carr, tau2carr] = calcLoopCoef(settings.pllNoiseBandwidth,settings.pllDampingRatio, 0.25);
    
    % -------- Number of acqusired signals ------------------------------------
    for channelNr = 1:settings.numberOfChannels
        if channel(channelNr).status == 'T'
            trackResults(channelNr).status = trackRes(channelNr).status;
            trackResults(channelNr).PRN = trackRes(channelNr).PRN;
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
    
    iUpdate=1;  % kalman update index
    dt   = INSATsetting.dt(iUpdate);
    ddt0 = INSATsetting.ddt(iUpdate);
    INSATsetting.X0(16)=-ddt0/1000;
    
    MLE_Start=zeros(settings.numberOfChannels,1); %
    
    %% Start processing channels ==============================================
        %=== Process the number of specified code periods =================
        iloopCnt = 1;
        while iloopCnt <= INSATsetting.tracklength
         %calculate transmit time for every millisecond
            Rx.transmitTime(activeChnList)=Rx.transmitTime(activeChnList)-...
                (-dt)/settings.c+Rx.blksize/settings.samplingFreq-(Rx.dSv-Rx.dPlos)/settings.c;
            if rem(iloopCnt-1,100)==0%update sv position per 100ms to reduce calculation
                [satPositionsall, ~] = satpos([Rx.transmitTime(Rx.transmitTime>0),Rx.transmitTime0(Rx.transmitTime0>0)], ...
                        [trackRes(activeChnList).PRN,trackRes(activeChnList).PRN],eph);
                satPositions=satPositionsall(:,1:settings.numberOfChannels);
                satPositions0=satPositionsall(:,end/2+1:end);
            else
                satPositions(1:3,:)=satPositions(1:3,:)+INSATsetting.kmt*satPositions(4:6,:);
                satPositions0(1:3,:)=satPositions0(1:3,:)+INSATsetting.kmt*satPositions0(4:6,:);
            end
            %read dataset segment into memory
            if strcmp(settings.dataType,'int16')
                fseek(fid, 2*dataAdaptCoeff*(0*settings.skipNumberOfSamples + Rx.minpos),'bof');
                [rawSignal0, ~] = fread(fid,dataAdaptCoeff*(max(Rx.samplepos)-Rx.minpos+max(Rx.blksize)+1), settings.dataType);
            else
                fseek(fid, dataAdaptCoeff*(0*settings.skipNumberOfSamples + Rx.minpos-1),'bof');
                [rawSignal0, ~] = fread(fid,dataAdaptCoeff*(max(Rx.samplepos)-Rx.minpos+max(Rx.blksize)+1), settings.dataType);        
            end
            for iChannel=1:settings.numberOfChannels

                channelNr = iChannel;
                Rx.blksize(1,iChannel)=ceil((settings.codeLength-Rx.remCodePhase(1,channelNr)) / Rx.codePhaseStep(1,channelNr));
                rawSignal= rawSignal0((Rx.samplepos(iChannel)-Rx.minpos)*dataAdaptCoeff+1:(Rx.samplepos(iChannel)-Rx.minpos+Rx.blksize(1,iChannel))*dataAdaptCoeff)';
     
                %% GUI update -------------------------------------------------------------
                % The GUI is updated every 50ms. This way Matlab GUI is still responsive enough. 
                if (rem(iloopCnt, 50) == 0)&&(iChannel == 1)
                    Ln = newline;
                    trackingStatus=['Tracking Completed ',int2str(iloopCnt), ...
                        ' of ', int2str(INSATsetting.tracklength), ' msec',Ln...
                        'C/No of PRN',int2str(channel(channelNr).PRN),': ',Rx.CNo,' (dB-Hz)'];
                    try
                        waitbar(iloopCnt/INSATsetting.tracklength,hwb,trackingStatus);
                    catch
                        % The progress bar was closed. It is used as a signal to stop, "cancel" processing. Exit.
                        disp('Progress bar closed, exiting...');
                        return
                    end
                end            
                if strcmp(settings.dataType,'int16')
                    trackResults(channelNr).absoluteSample(iloopCnt) = (ftell(fid)-dataAdaptCoeff*(max(Rx.samplepos)-Rx.minpos+max(Rx.blksize)+1)*2+ ...
                        (Rx.samplepos(iChannel)-Rx.minpos)*dataAdaptCoeff*2)/dataAdaptCoeff/2;
                else
                    trackResults(channelNr).absoluteSample(iloopCnt) = (ftell(fid)-dataAdaptCoeff*(max(Rx.samplepos)-Rx.minpos+max(Rx.blksize)+1)*2+ ...
                        (Rx.samplepos(iChannel)-Rx.minpos)*dataAdaptCoeff*2)/dataAdaptCoeff;
                end
                if (dataAdaptCoeff==2)
                    rawSignal1=rawSignal(1:2:end);
                    rawSignal2=rawSignal(2:2:end);
                    rawSignal = rawSignal1 + 1i.* rawSignal2;  %transpose vector
                end
                if rem(iloopCnt-1,100)==0%transform sv pos to enu per 100ms to reduce calculation
                    Rx.satPosenu(1:3,iChannel)=Rx.est_DCMel_KF*(satPositions(1:3,iChannel)-Rx.pos_kf');
                    Rx.satPosenu0(1:3,iChannel)=Rx.est_DCMel_KF*(satPositions0(1:3,iChannel)-Rx.pos_kf');
                    Rx.satVelenu(1:3,iChannel)=(Rx.satPosenu(1:3,iChannel)-Rx.satPosenu0(1:3,iChannel))/INSATsetting.kmt;
                else
                    dvtmp=(Rx.satVelenu(1:3,iChannel)+Rx.vel_l(iloopCnt,1:3)')*INSATsetting.kmt;
                    Rx.satPosenu(1:3,iChannel)=Rx.satPosenu(1:3,iChannel)+dvtmp;
                    Rx.satPosenu0(1:3,iChannel)=Rx.satPosenu0(1:3,iChannel)+dvtmp;
                end
                %calculate LOS
                le=Rx.satPosenu(1,iChannel);ln=Rx.satPosenu(2,iChannel);lu=Rx.satPosenu(3,iChannel);
                norm_a=sqrt(le*le+ln*ln+lu*lu);
                a=[le;ln;lu]/norm_a;
                % form measurement matrix
                INSATsetting.H(iChannel,:)=[-a(1),-a(2),-a(3),zeros(1,12),-1,0];
                INSATsetting.H(iChannel+settings.numberOfChannels,:)=[zeros(1,3),+a(1),+a(2),+a(3),zeros(1,9),0,1];            
                Rx.dSv(iChannel)=(Rx.satPosenu(1:3,iChannel)-Rx.satPosenu0(1:3,iChannel))'*a;%sv displacement projection on LOS
                Rx.Vs(iChannel)=(Rx.satVelenu(1:3,iChannel)'-Rx.velenu)*a;%relative velocity between sv and user on LOS          
                Rx.dPlos(iChannel)=(INSATsetting.kmt*Rx.velenu)*a;%the user displacement between current and previous epoch
                Rx.dVlos(iChannel)=INSATsetting.X0(4:6)'*a;%estimated user velocity error on LOS
                % update code frequency and phase
                % Rx.codeFreq(1,iChannel)=settings.codeFreqBasis*(1-(ddt0+Rx.Vs(iChannel))/settings.c);
                % Rx.codePhaseStep(1,iChannel) = Rx.codeFreq(1,iChannel) / settings.samplingFreq;                
                %correct previous Rx.codePhase with estimated position error
                Rx.codePhase(1,iChannel) = Rx.codePhase(1,iChannel) + (dt+INSATsetting.X0(1:3)'*a)/settings.c*Rx.codeFreq(1,iChannel);
                %generate current 1ms code phase
                Rx.codePhase(1,iChannel) = Rx.codePhase(1,iChannel) -...
                    (Rx.dSv(iChannel)-Rx.dPlos(iChannel))/settings.c*Rx.codeFreq(1,iChannel)+(Rx.blksize(1,iChannel)-Rx.blksize0(1,iChannel)).*Rx.codePhaseStep(1,iChannel);
                code_ML = zeros(4*M+1,Rx.blksize(1,iChannel));
                for code_chips = 1:4*M+1
                    phase_i = code_chips*space -(2+space);
                    tcode   = (Rx.remCodePhase(1,iChannel)+phase_i) : ...
                        Rx.codePhaseStep(1,iChannel) : ...
                        ((Rx.blksize(1,iChannel)-1)*Rx.codePhaseStep(1,iChannel)+Rx.remCodePhase(1,iChannel)+phase_i);
                    tcode2 = mod(floor(tcode),  1023) + 1;
    
                    code_ML(code_chips,:) = Rx.caCode(iChannel,tcode2);
                end
      
                %% Generate the carrier frequency to mix the signal to baseband -----------
                % Rx.carrFreq(1,iChannel)=settings.IF-(ddt0+Rx.Vs(iChannel))/settings.c*1575.42e6;
                INSATsetting.dopplerFeedback(iloopCnt,iChannel) = -(ddt0+Rx.Vs(iChannel))/settings.c*1575.42e6;
                Rx.remCodePhase(1,iChannel) = Rx.blksize(1,iChannel)*Rx.codePhaseStep(1,iChannel)+Rx.remCodePhase(1,iChannel)-1023;
                time=(0:Rx.blksize(1,iChannel)) ./ settings.samplingFreq;
    
                % Get the argument to sin/cos functions
                trigarg = ((Rx.carrFreq(1,iChannel) * 2.0 * pi) .* time) + Rx.remCarrPhase(1,iChannel);
                Rx.remCarrPhase(1,iChannel) = rem(trigarg(Rx.blksize(1,iChannel)+1), (2 * pi));
    
                % Finally compute the signal to mix the collected data to bandband
                carrsig = exp(-1i .* trigarg(1:Rx.blksize(1,iChannel)));%so time-consuming, to be optimized...
    
                %% Generate the six standard accumulated values ---------------------------
                % First mix to baseband
                BasebandSignal = carrsig .* rawSignal;
                ACC_total =  zeros(4*M+1, 1);
                for i = 1:4*M+1
                    ACC_total(i) =  sum(code_ML(i,:)  .* BasebandSignal);
                end
                % Now get early, late, and prompt values for each

               %%  mitigation
               if  ~MLE_Start(iChannel)
                   if (rem(iloopCnt, 1000) == 0)&&(iloopCnt ~= 0)
                      authen_spoof_index=zeros(1000,1);
                      for iiloopCnt=iloopCnt-999:iloopCnt      
                         U= trackResults(activeChnList(iChannel)).ACC(:,iiloopCnt);
                         [AuSpoof_index,~]=Grid_medll(U,L_2chips,H_2chips,inv_Q_2chips);
                         authen_spoof_index(iiloopCnt-iloopCnt+1000)=AuSpoof_index(2);
                         WTCCP=LFICP_test(authen_spoof_index,1000)/20;
                      end 
                      if WTCCP<0.01
                        MLE_Start(iChannel)=1;
                      end
                   end
               else

                   [AuSpoof_index,AuSpoof_amp]=Grid_medll(ACC_total,L_2chips,H_2chips,inv_Q_2chips);
                   ACC_mitigation=ACC_total-AuSpoof_amp(2)*AutoCorr_CA([-2:space:2]-(AuSpoof_index(2)-M*2-1)/M );
                   ACC_total=ACC_mitigation;
               end
                    
                    I_E = real(ACC_total(1.5*M+1));
                    Q_E = imag(ACC_total(1.5*M+1));
                    I_P = real(ACC_total(2*M+1));
                    Q_P = imag(ACC_total(2*M+1));
                    I_L = real(ACC_total(2.5*M+1));
                    Q_L = imag(ACC_total(2.5*M+1));
             
         %% Find PLL error and update carrier NCO ----------------------------------
    
                % Implement carrier loop discriminator (phase detector)
                if (iloopCnt==1)
                    Rx.IP1(1,iChannel)=I_P;
                    Rx.QP1(1,iChannel)=Q_P;
                    Rx.carrErrorold(1,iChannel)=Rx.carrError(1,iChannel);
                    Rx.carrError(1,iChannel)=0;
                else
                    dot=Rx.IP1(1,iChannel)*I_P+Rx.QP1(1,iChannel)*Q_P;
                    cross=Rx.IP1(1,iChannel)*Q_P-I_P*Rx.QP1(1,iChannel);
                    % frequency discriminator
                    Rx.carrErrorold(1,iChannel)=Rx.carrError(1,iChannel);
                    Rx.carrError(1,iChannel) = cross*sign(dot)/(2*pi*(I_P*I_P+Q_P*Q_P));
                    Rx.IP1(1,iChannel)=I_P;
                    Rx.QP1(1,iChannel)=Q_P;
                end
                
                %% Find PLL error and update carrier NCO ----------------------------------
                % Implement carrier loop discriminator (phase detector)
                Rx.carrError(1,iChannel) = atan(Q_P / I_P) / (2.0 * pi);
                % Implement carrier loop filter and generate NCO command
                Rx.carrNco(1,iChannel) = Rx.oldCarrNco(1,iChannel) + (tau2carr/tau1carr) * (Rx.carrError(1,iChannel) ...
                     - Rx.oldCarrError(1,iChannel)) + Rx.carrError(1,iChannel) * (INSATsetting.pdicarr/tau1carr);
                Rx.oldCarrNco(1,iChannel)   = Rx.carrNco(1,iChannel);
                Rx.oldCarrError(1,iChannel) = Rx.carrError(1,iChannel);
                % Save carrier frequency for current correlation
                trackResults(channelNr).carrFreq(iloopCnt) = Rx.carrFreq(1,iChannel);
                % Modify carrier freq based on NCO command
                % Rx.carrFreq(1,iChannel) = Rx.carrFreqBasis(1,iChannel) + Rx.carrNco(1,iChannel);
                if iloopCnt == 1
                    Rx.carrFreq(1,iChannel) = Rx.carrNco(1,iChannel) + settings.IF + INSATsetting.dopplerFeedback(iloopCnt,iChannel);  %  Rx.carrNco(1,iChannel) +
                else
                    Rx.carrFreq(1,iChannel) = Rx.carrNco(1,iChannel) + settings.IF + INSATsetting.dopplerFeedback(iloopCnt-1,iChannel)...  % Rx.carrNco(1,iChannel) +
                    + (INSATsetting.dopplerFeedback(iloopCnt,iChannel)-INSATsetting.dopplerFeedback(iloopCnt-1,iChannel))/20;
                end
    
                % Implement carrier loop filter and generate NCO command
                INSATsetting.Z(iChannel+settings.numberOfChannels,1)=(Rx.carrErrorold(1,iChannel)+(Rx.carrError(1,iChannel)-Rx.carrErrorold(1,iChannel))...
                    /Rx.blksize(1,iChannel)*(Rx.blksize(1,iChannel)-rem((Rx.samplepos(1,iChannel)-Rx.minpos),Rx.blksize(1,iChannel))))/INSATsetting.pdi/1575.42e6*settings.c;
    
                %% Find DLL error and update code NCO -------------------------------------
                Rx.codeError(1,iChannel) = (sqrt(I_E * I_E + Q_E * Q_E) - sqrt(I_L * I_L + Q_L * Q_L)) / ...
                    (sqrt(I_E * I_E + Q_E * Q_E) + sqrt(I_L * I_L + Q_L * Q_L));           
                % Implement code loop filter and generate NCO command
                Rx.codeNco(1,iChannel) = Rx.oldCodeNco(1,iChannel) + (tau2code/tau1code) * (Rx.codeError(1,iChannel)...
                     - Rx.oldCodeError(1,iChannel)) + Rx.codeError(1,iChannel) * (INSATsetting.pdicode/tau1code);
                
                Rx.oldCodeNco(1,iChannel)   = Rx.codeNco(1,iChannel);
                Rx.oldCodeError(1,iChannel) = Rx.codeError(1,iChannel);
                %update code frequency and phase
                Rx.codeFreq(1,iChannel) = settings.codeFreqBasis + INSATsetting.dopplerFeedback(iloopCnt,iChannel)/1540; % - codeNco(1,iChannel)
                Rx.codePhaseStep(1,iChannel) = Rx.codeFreq(1,iChannel) / settings.samplingFreq;  
                
                % Save code frequency for current correlation
                trackResults(channelNr).codeFreq(iloopCnt) = Rx.codeFreq(1,iChannel);
                
                % Modify code freq based on NCO command
                % Rx.codeFreq(1,iChannel) = settings.codeFreqBasis - Rx.codeNco(1,iChannel);
                INSATsetting.Z(iChannel,1)=(Rx.codeErrorold(1,iChannel)+(Rx.codeError(1,iChannel)-Rx.codeErrorold(1,iChannel))...
                    /Rx.blksize(1,iChannel)*(Rx.blksize(1,iChannel)-rem((Rx.samplepos(1,iChannel)-Rx.minpos),Rx.blksize(1,iChannel))))/Rx.codeFreq(1,iChannel)*settings.c;
                %% Record various measures to show in postprocessing ----------------------
                trackResults(activeChnList(iChannel)).ACC(:,iloopCnt)=ACC_total';
                trackResults(activeChnList(iChannel)).remCodePhase(iloopCnt) =  Rx.remCodePhase(1,iChannel);
                trackResults(activeChnList(iChannel)).remCarrPhase(iloopCnt) = Rx.remCarrPhase(1,iChannel);
                trackResults(activeChnList(iChannel)).dllDiscr(iloopCnt) = Rx.codeError(1,iChannel);
                trackResults(activeChnList(iChannel)).dllDiscrFilt(iloopCnt) = Rx.codeNco(1,iChannel);
                trackResults(activeChnList(iChannel)).pllDiscr(iloopCnt) = Rx.carrError(1,iChannel);
                trackResults(activeChnList(iChannel)).pllDiscrFilt(iloopCnt) = Rx.carrNco(1,iChannel);
                trackResults(activeChnList(iChannel)).I_E(iloopCnt) = I_E;
                trackResults(activeChnList(iChannel)).I_P(iloopCnt) = I_P;
                trackResults(activeChnList(iChannel)).I_L(iloopCnt) = I_L;
                trackResults(activeChnList(iChannel)).Q_E(iloopCnt) = Q_E;
                trackResults(activeChnList(iChannel)).Q_P(iloopCnt) = Q_P;
                trackResults(activeChnList(iChannel)).Q_L(iloopCnt) = Q_L;
        
                %% 
                if (settings.CNo.enableVSM==1) && (iChannel==1)
                    if (rem(iloopCnt,settings.CNo.VSMinterval)==0)
                        Rx.vsmCnt(iChannel)=Rx.vsmCnt(iChannel)+1;
                        CNoValue=CNoVSM(trackResults(activeChnList(iChannel)).I_P(iloopCnt-settings.CNo.VSMinterval+1:iloopCnt),...
                            trackResults(activeChnList(iChannel)).Q_P(iloopCnt-settings.CNo.VSMinterval+1:iloopCnt),settings.CNo.accTime);
                        trackResults(activeChnList(iChannel)).CNo.VSMValue(Rx.vsmCnt(iChannel))=CNoValue;
                        trackResults(activeChnList(iChannel)).CNo.VSMIndex(Rx.vsmCnt(iChannel))=iloopCnt;
                        Rx.CNo = int2str(CNoValue);
                    end
                end
                trackResults(activeChnList(iChannel)).Rx.blksize(iloopCnt)  = Rx.blksize(1,iChannel);
            end
 %%
            if (rem(iloopCnt-1,10)==0)%to sync 1ms loop and 10ms INS                
                iUpdate=iUpdate+1;                
            end
            %% INS strapdown update
            tupd = INSATsetting.kmt;%update interval
            % %update dcm from epoch k to epoch k+1 using gyro delta angles
            Rx.est_DCMbn = Rx.est_DCMbn_KF*calDCM(Rx.raw_dtheta(iUpdate,1:3)-1*INSATsetting.X0(13:15)'*tupd);
            % %rotation rate of enu relative to the ecef, expressed in enu (rad/s)
            omega_el_L = llangrate(Rx.latold,Rx.veold,Rx.vnold,Rx.heightold);
            omega_ie_L = Rx.est_DCMel_KF*Rx.omega_ie_E;% earth rotation rate relative to inertial frame expressed in ENU
            Rx.omega_il_L = omega_ie_L + omega_el_L;% enu rotation relative to inertial, expressed in ENU
            DCM_ll_I = calDCM(-Rx.omega_il_L*tupd);%enu dcm between epochs
            Rx.est_DCMbn = Rx.C*(DCM_ll_I*(Rx.C*Rx.est_DCMbn)); %estimated DCM b to n, taking local-level frame rotation into account
            del_Vl = Rx.C*(Rx.raw_dv(iUpdate,1:3))';  %  Rx.C*(Rx.raw_dv(iUpdate,1:3)-1*INSATsetting.X0(10:12)'*tupd)';
            est_DCMel=calDCM(-omega_el_L*tupd)*Rx.est_DCMel_KF;
            vtmp = [INSATsetting.INSve(iUpdate),INSATsetting.INSvn(iUpdate),INSATsetting.INSvu(iUpdate)];
            Rx.vel_l(iloopCnt+1,:) = vtmp';
            Rx.accel_L = del_Vl/tupd;
            Rx.est_height(iloopCnt+1) = Rx.est_height(iloopCnt)+Rx.vel_l(iloopCnt+1,3)*INSATsetting.kmt;
            Rx.heightold = Rx.est_height(iloopCnt+1);
            Rx.est_lat(iloopCnt+1) = asin(est_DCMel(3,3));
            Rx.est_lon(iloopCnt+1) = atan2(est_DCMel(3,2),est_DCMel(3,1));
            [F,radiusa] = Fupdate(Rx,INSATsetting,iloopCnt);
            
            % Robust Kalman Filter
            P=F*INSATsetting.P0*F'+INSATsetting.Qw;
            K=P*INSATsetting.H'/(INSATsetting.H*P*INSATsetting.H'+INSATsetting.R);
            INSATsetting.P0=(eye(INSATsetting.stateno)-K*INSATsetting.H)*P;
            X_next=F*INSATsetting.X0;
            beta=(INSATsetting.Z(:,1)-INSATsetting.H*X_next(:,1));
            alpha=K*beta;
            INSATsetting.X_est(:,iloopCnt)=X_next(:,1)+alpha;
            INSATsetting.X0=INSATsetting.X_est(:,iloopCnt);     
            c1 = 1.353; c2 = 3.019;
            AdeltaX = beta;
            INSATsetting.deltaX(1,iloopCnt) = sum(AdeltaX.^2)/sqrt(trace(P))/500;
            if abs(INSATsetting.deltaX(1,iloopCnt))<c1
                INSATsetting.alphak(1,iloopCnt) = 1;
            elseif abs(INSATsetting.deltaX(1,iloopCnt))<c2 && abs(INSATsetting.deltaX(1,iloopCnt))>c1
                INSATsetting.alphak(1,iloopCnt) = c1/INSATsetting.deltaX(1,iloopCnt)*((c2-INSATsetting.deltaX(1,iloopCnt))/(c2-c1)).^2;
            else
                INSATsetting.alphak(1,iloopCnt) = 10e-4;
            end
            %% adaptive filter
            res=beta;
            Rx.mat1(:,INSATsetting.cnt)=res(1:settings.numberOfChannels);%code
            Rx.mat2(:,INSATsetting.cnt)=res(settings.numberOfChannels+1:end);%carrier
    
            INSATsetting.cnt=INSATsetting.cnt+1;
            if INSATsetting.cnt==INSATsetting.lastn
                INSATsetting.cnt=1;
            end
            if rem(iloopCnt-1,INSATsetting.lastn)==0
                Cres1=Rx.mat1*Rx.mat1'/INSATsetting.lastn;
                Cres2=Rx.mat2*Rx.mat2'/INSATsetting.lastn;
                tmpR=diag([diag(Cres1);diag(Cres2)]+diag(INSATsetting.H*INSATsetting.P0*INSATsetting.H'));
                INSATsetting.R(1:settings.numberOfChannels,1:settings.numberOfChannels)=tmpR(1:settings.numberOfChannels,1:settings.numberOfChannels);
                INSATsetting.R(settings.numberOfChannels+1:2*settings.numberOfChannels,settings.numberOfChannels+1:2*settings.numberOfChannels)=...
                tmpR(settings.numberOfChannels+1:2*settings.numberOfChannels,settings.numberOfChannels+1:2*settings.numberOfChannels);
            end
            INSATsetting.R = INSATsetting.R/INSATsetting.alphak(1,iloopCnt);
    
            % correct errors
            Rx.est_lat(iloopCnt+1)=Rx.est_lat(iloopCnt+1)+INSATsetting.X0(2)/radiusa;
            Rx.est_lon(iloopCnt+1)=Rx.est_lon(iloopCnt+1)+INSATsetting.X0(1)/radiusa/cos(Rx.est_lat(iloopCnt+1));
            Rx.est_height(iloopCnt+1)=Rx.est_height(iloopCnt+1)+1*INSATsetting.X0(3);
            theta(1,1) = -INSATsetting.X_est(2,iloopCnt)/radiusa;
            theta(2,1) = INSATsetting.X_est(1,iloopCnt)/radiusa;
            theta(3,1) = tan(Rx.est_lat(iloopCnt+1))*theta(2);
            psi=INSATsetting.X0(7:9);
            phi_angle=psi+theta;%total attitude error
            slat=sin(Rx.est_lat(iloopCnt+1));
            clat=cos(Rx.est_lat(iloopCnt+1));
            slon=sin(Rx.est_lon(iloopCnt+1));
            clon=cos(Rx.est_lon(iloopCnt+1));
            Rx.est_DCMel_KF=[-slon -slat*clon clat*clon; clon -slat*slon clat*slon;0 clat slat]';
            Rx.latold = Rx.est_lat(iloopCnt+1);
            Rx.est_DCMbn_KF = Rx.C*(eye(3)+antisymm(phi_angle))*Rx.C*Rx.est_DCMbn; 
            eulangle = dcm2eul(Rx.est_DCMbn_KF);
            Rx.est_roll_KF(iloopCnt+1) = eulangle(1);
            Rx.est_pitch_KF(iloopCnt+1) = eulangle(2);
            Rx.est_yaw_KF(iloopCnt+1) = eulangle(3);
            Rx.veold=Rx.vel_l(iloopCnt+1,1);
            Rx.vnold=Rx.vel_l(iloopCnt+1,2);
            Rx.vuold=Rx.vel_l(iloopCnt+1,3);
            Rx.velold = Rx.vel_l(iloopCnt+1,:);
            % dt=INSATsetting.X0(16);
            % ddt=INSATsetting.X0(17);
            % ddt0=ddt0+ddt;
            dt   = INSATsetting.dt(iUpdate);
            ddt0 = INSATsetting.ddt(iUpdate);
            [Rx.pos_kf(1,1),Rx.pos_kf(1,2),Rx.pos_kf(1,3)]=geo2cart([Rx.est_lat(iloopCnt+1)*INSATsetting.r2d,0,0],[Rx.est_lon(iloopCnt+1)*INSATsetting.r2d,0,0], Rx.est_height(iloopCnt+1), 5);
            vel_kf=(Rx.est_DCMel_KF'*Rx.vel_l(iloopCnt+1,:)')';
            Rx.velenu=Rx.vel_l(iloopCnt+1,:);  
            Rx.pos_kf=vel_kf*INSATsetting.kmt+Rx.pos_kf;%estimate next pos in ecef
            Rx.transmitTime0=Rx.transmitTime;
            Rx.samplepos=Rx.samplepos+Rx.blksize;
            Rx.minpos=min(Rx.samplepos);
        iloopCnt = iloopCnt+1;
        end % for iloopCnt


       
