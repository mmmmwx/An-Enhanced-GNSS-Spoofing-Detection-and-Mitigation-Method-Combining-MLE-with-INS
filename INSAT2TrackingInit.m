function channel = INSAT2TrackingInit(trackResults,start_point)

    channel = struct();
    channel.PRN = 0;              
    channel.acquiredFreq = 0;     
    channel.codePhase = 0;         
    channel.codeFreq = 0;
    channel.remCodePhase = 0;        
    channel.remCarrPhase = 0;      
    channel.oldCodeNco = 0;      
    channel.oldCodeError = 0;      
    channel.oldCarrNco = 0;      
    channel.oldCarrError = 0;      
    channel.status = '-';          
    channel = repmat(channel, 1, size(trackResults,2));

    for i = 1:size(trackResults,2)
        channel(i).PRN = trackResults(i).PRN;
        channel(i).acquiredFreq =  trackResults(i).carrFreq(start_point); 
        channel(i).codeFreq = trackResults(i).codeFreq(start_point);  
        channel(i).codePhase = trackResults(i).absoluteSample(start_point); 
        channel(i).remCodePhase = trackResults(i).remCodePhase(start_point);        
        channel(i).remCarrPhase = trackResults(i).remCarrPhase(start_point);   
        channel(i).oldCodeError = trackResults(i).dllDiscr(start_point);     
        channel(i).oldCarrError = trackResults(i).pllDiscr(start_point);    
        channel(i).status ='T';
    end
end
