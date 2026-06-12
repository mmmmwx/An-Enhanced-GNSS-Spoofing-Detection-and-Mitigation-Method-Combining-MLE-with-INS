<<<<<<< HEAD
disp ('   Starting processing...');
settings_mitigation=initSettings_mitigation();
[fid, message] = fopen(settings_mitigation.fileName, 'rb');

%Initialize the multiplier to adjust for the data type
if (settings_mitigation.fileType==1)
    dataAdaptCoeff=1;
else
    dataAdaptCoeff=2;
end

%If success, then process the data
if (fid > 0)

    % Move the starting point of processing. Can be used to start the
    % signal processing at any point in the data record (e.g. good for long
    % records or for signal processing in blocks).
    fseek(fid, dataAdaptCoeff*settings_mitigation.skipNumberOfSamples, 'bof');

    %% Acquisition ============================================================

    % Do acquisition if it is not disabled in settings or if the variable
    % acqResults does not exist.
    if ((settings_mitigation.skipAcquisition == 0))
        % Find number of samples per spreading code
        samplesPerCode = round(settings_mitigation.samplingFreq / ...
            (settings_mitigation.codeFreqBasis / settings_mitigation.codeLength));
        %--- Do the acquisition -------------------------------------------
        disp ('   Acquiring satellites...');
        % Read the required amount of data depending on the data file type
        % and the number of code period of coherent and non-coherent 
        % integration and invoke the acquisition function
        data = fread(fid, dataAdaptCoeff*(settings_mitigation.acquisition.cohCodePeriods* ...
            settings_mitigation.acquisition.nonCohSums+1)*samplesPerCode*6, settings_mitigation.dataType)';
        if (dataAdaptCoeff==2)
            data1=data(1:2:end);
            data2=data(2:2:end);
            data=data1 + 1i .* data2;
         end
        acqResults = acquisition(data, settings_mitigation);
       % Plot the acquisition results
        plotAcquisition(acqResults);
    end
end
    %% Initialize channels and prepare for the run ============================
    % Start further processing only if a GNSS signal was acquired (the
    % field FREQUENCY will be set to 0 for all not acquired signals)
    if (any(acqResults.peakMetric>settings_mitigation.acqThreshold))
        channel = preRun(acqResults, settings_mitigation);
        showChannelStatus(channel, settings_mitigation);
    else
        % No satellites to track, exit
        disp('   No GNSS signals detected, signal processing finished.');
        trackResults = [];
        return;
    end
    %% Track the signal =======================================================
    if ~settings_mitigation.INSAT
        startTime = now;
        disp (['   Tracking started at ', datestr(startTime)]);
        [trackResults_ds6, channel] = tracking_mitigation(fid, channel, settings_mitigation);
        % Close the data file
        fclose(fid);
        disp(['   Tracking is over (elapsed time ',datestr(now - startTime, 13), ')'] )
        disp('   Saving Acq & Tracking results to file "trackingResults.mat"')
        save([settings.dir '\acqResults.mat'], 'acqResults');
        save([settings.dir '\trkResults.mat'], 'trackResults', 'settings', 'acqResults', 'channel');
    else
        disp('   skip scalar tracking, load exisiting results')
        trackResults = load([settings.dir '\trkResults.mat']).trkResults;
    end
  %%  Calculate navigation solutions =========================================
    if ~settings.INSAT
        disp('   Calculating navigation solutions...');
        settings = initSettings();
        trackResults = load([settings.dir '\trkResults.mat']).trackResults;
        [navSolutions, eph, svTimeTable,activeChnList] = postNavigationNomial(trackResults, settings);
        save([settings.dir '\navSolutions.mat'],'navSolutions','eph','svTimeTable','activeChnList')
    end
    %% INSAT/MLE architecture
    [INSATsetting,Rx,trackResults_INSAT_ds6] = INSAT_MLE(fid, channel,trackResults_ds6,navSolutions,eph,activeChnList,svTimeTable, settings_mitigation);
    %% 
    [navSolutions_mitigation, eph, svTimeTable,activeChnList] = postNavigationNomial(trackResults_INSAT_ds6, settings_mitigation);

=======
disp ('   Starting processing...');
settings_mitigation=initSettings_mitigation();
[fid, message] = fopen(settings_mitigation.fileName, 'rb');

%Initialize the multiplier to adjust for the data type
if (settings_mitigation.fileType==1)
    dataAdaptCoeff=1;
else
    dataAdaptCoeff=2;
end

%If success, then process the data
if (fid > 0)

    % Move the starting point of processing. Can be used to start the
    % signal processing at any point in the data record (e.g. good for long
    % records or for signal processing in blocks).
    fseek(fid, dataAdaptCoeff*settings_mitigation.skipNumberOfSamples, 'bof');

    %% Acquisition ============================================================

    % Do acquisition if it is not disabled in settings or if the variable
    % acqResults does not exist.
    if ((settings_mitigation.skipAcquisition == 0))
        % Find number of samples per spreading code
        samplesPerCode = round(settings_mitigation.samplingFreq / ...
            (settings_mitigation.codeFreqBasis / settings_mitigation.codeLength));
        %--- Do the acquisition -------------------------------------------
        disp ('   Acquiring satellites...');
        % Read the required amount of data depending on the data file type
        % and the number of code period of coherent and non-coherent 
        % integration and invoke the acquisition function
        data = fread(fid, dataAdaptCoeff*(settings_mitigation.acquisition.cohCodePeriods* ...
            settings_mitigation.acquisition.nonCohSums+1)*samplesPerCode*6, settings_mitigation.dataType)';
        if (dataAdaptCoeff==2)
            data1=data(1:2:end);
            data2=data(2:2:end);
            data=data1 + 1i .* data2;
         end
        acqResults = acquisition(data, settings_mitigation);
       % Plot the acquisition results
        plotAcquisition(acqResults);
    end
end
    %% Initialize channels and prepare for the run ============================
    % Start further processing only if a GNSS signal was acquired (the
    % field FREQUENCY will be set to 0 for all not acquired signals)
    if (any(acqResults.peakMetric>settings_mitigation.acqThreshold))
        channel = preRun(acqResults, settings_mitigation);
        showChannelStatus(channel, settings_mitigation);
    else
        % No satellites to track, exit
        disp('   No GNSS signals detected, signal processing finished.');
        trackResults = [];
        return;
    end
    %% Track the signal =======================================================
    if ~settings_mitigation.INSAT
        startTime = now;
        disp (['   Tracking started at ', datestr(startTime)]);
        [trackResults_ds6, channel] = tracking_mitigation(fid, channel, settings_mitigation);
        % Close the data file
        fclose(fid);
        disp(['   Tracking is over (elapsed time ',datestr(now - startTime, 13), ')'] )
        disp('   Saving Acq & Tracking results to file "trackingResults.mat"')
        save([settings.dir '\acqResults.mat'], 'acqResults');
        save([settings.dir '\trkResults.mat'], 'trackResults', 'settings', 'acqResults', 'channel');
    else
        disp('   skip scalar tracking, load exisiting results')
        trackResults = load([settings.dir '\trkResults.mat']).trkResults;
    end
  %%  Calculate navigation solutions =========================================
    if ~settings.INSAT
        disp('   Calculating navigation solutions...');
        settings = initSettings();
        trackResults = load([settings.dir '\trkResults.mat']).trackResults;
        [navSolutions, eph, svTimeTable,activeChnList] = postNavigationNomial(trackResults, settings);
        save([settings.dir '\navSolutions.mat'],'navSolutions','eph','svTimeTable','activeChnList')
    end
    %% INSAT/MLE architecture
    [INSATsetting,Rx,trackResults_INSAT_ds6] = INSAT_MLE(fid, channel,trackResults_ds6,navSolutions,eph,activeChnList,svTimeTable, settings_mitigation);
    %% 
    [navSolutions_mitigation, eph, svTimeTable,activeChnList] = postNavigationNomial(trackResults_INSAT_ds6, settings_mitigation);

>>>>>>> dd185dbd3df17ab91cd383b9d2fdb82a32048e8f
