function Rt = AutoCorr_CA(cacode)
code_length=length(cacode);
Rt=zeros(code_length,1);
for code_chips=1:code_length
    if(abs(cacode(code_chips))>1)
        Rt(code_chips,1) = 0;
    else
        Rt(code_chips,1) = 1-abs(cacode(code_chips));
    end
end
