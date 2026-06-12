function lficp = LFICP(CPD, L)

    N = length(CPD);  
 
    fluct_thres = 10*20;   
    fluct_thres2 = 10*20;    
    w_small =1;       
    w_middle=1;
    w_large = 1;     
    
    K = floor(N / L); 
    
    for k = 1:K
        seg_start = (k - 1) * L + 1;
        seg_end = k * L;
        CPD_seg = CPD(seg_start:seg_end);  
     
   
        tau_ref = (1 /L) * sum(CPD_seg);  
        a_l = zeros(L, 1);  
        for l = 1:L

            if abs(CPD_seg(l) - tau_ref) <= fluct_thres
                a_l(l) = w_small; 
            elseif abs(CPD_seg(l) - tau_ref) > fluct_thres && abs(CPD_seg(l) - tau_ref) <= fluct_thres2
                a_l(l) = w_middle; 
            else
                a_l(l) = w_large;  
            end
        end
        abs_deviation = abs(CPD_seg - tau_ref);  
        weighted_sum = sum(abs_deviation .* a_l); 
        tmccpd_vec(k) = weighted_sum / (L); 
    end
    lficp=tmccpd_vec;
end