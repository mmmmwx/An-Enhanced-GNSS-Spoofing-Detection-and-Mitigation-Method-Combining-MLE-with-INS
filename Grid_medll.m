<<<<<<< HEAD
function [min_index,theta00]=Grid_medll(U,L_2chips,H_2chips,inv_Q_2chips)
M=20;
min_value = 3.2e38;
min_index = [1,1];
theta00 = [0,0];
for index_A = (1.9*M):(2.1*M)
    L_pointer = 0;   
    for index_S=1:(4*M+1)   
        if ((index_S == index_A))  
            L_pointer = L_pointer + 1;
            line_base = (index_A-1)*(4*M+1)*(4*M+1)+(L_pointer-1)*(4*M+1);
            H_buf = H_2chips(line_base+1:line_base+(4*M+1),:);
            L_buf=inv(H_buf(:,1)'*inv_Q_2chips*H_buf(:,1))*H_buf(:,1)'*inv_Q_2chips;
            value = abs((U-H_buf(:,1)*(L_buf*U))'*inv_Q_2chips*(U-H_buf(:,1)*(L_buf*U)));
            if(value<min_value)
                min_value = value;
                min_index = [index_A,index_S];
                theta00 = (L_buf*U);
            end
        else
            L_pointer = L_pointer + 1;
            line_base = (index_A-1)*(4*M+1)*2+(L_pointer-1)*2;
            L_buf = L_2chips(line_base+1:line_base+2,:); 
            line_base = (index_A-1)*(4*M+1)*(4*M+1)+(L_pointer-1)*(4*M+1);
            H_buf = H_2chips(line_base+1:line_base+(4*M+1),:);
            value = abs((U-H_buf*(L_buf*U))'*inv_Q_2chips*(U-H_buf*(L_buf*U)));
            if(value<min_value)
                min_value = value;
                min_index = [index_A,index_S];
                theta00 = (L_buf*U);
            end
         end
    end
end
=======
function [min_index,theta00]=Grid_medll(U,L_2chips,H_2chips,inv_Q_2chips)
M=20;
min_value = 3.2e38;
min_index = [1,1];
theta00 = [0,0];
for index_A = (1.9*M):(2.1*M)
    L_pointer = 0;   
    for index_S=1:(4*M+1)   
        if ((index_S == index_A))  
            L_pointer = L_pointer + 1;
            line_base = (index_A-1)*(4*M+1)*(4*M+1)+(L_pointer-1)*(4*M+1);
            H_buf = H_2chips(line_base+1:line_base+(4*M+1),:);
            L_buf=inv(H_buf(:,1)'*inv_Q_2chips*H_buf(:,1))*H_buf(:,1)'*inv_Q_2chips;
            value = abs((U-H_buf(:,1)*(L_buf*U))'*inv_Q_2chips*(U-H_buf(:,1)*(L_buf*U)));
            if(value<min_value)
                min_value = value;
                min_index = [index_A,index_S];
                theta00 = (L_buf*U);
            end
        else
            L_pointer = L_pointer + 1;
            line_base = (index_A-1)*(4*M+1)*2+(L_pointer-1)*2;
            L_buf = L_2chips(line_base+1:line_base+2,:); 
            line_base = (index_A-1)*(4*M+1)*(4*M+1)+(L_pointer-1)*(4*M+1);
            H_buf = H_2chips(line_base+1:line_base+(4*M+1),:);
            value = abs((U-H_buf*(L_buf*U))'*inv_Q_2chips*(U-H_buf*(L_buf*U)));
            if(value<min_value)
                min_value = value;
                min_index = [index_A,index_S];
                theta00 = (L_buf*U);
            end
         end
    end
end
>>>>>>> dd185dbd3df17ab91cd383b9d2fdb82a32048e8f
