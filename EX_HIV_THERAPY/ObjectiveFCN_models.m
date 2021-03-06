function J = ObjectiveFCN_models(uopt,x,N,Nu,xref,u0,p,Q,R,Ru, select_model)
%% Cost function of nonlinear MPC for HIV system
%
% Inputs:
%   u:      optimization variable, from time k to time k+N-1
%   x:      current state at time k
%   Ts:     controller sample time
%   N:      prediction horizon
%   xref:   state references, constant from time k+1 to k+N
%   u0:     previous controller output at time k-1
%
% Output:
%   J:      objective function cost
%

Nvar = length(x);
%% Nonlinear MPC design parameters
% Q = diag([1,1,1]);
% R = 0.01;

u = uopt;
% u = zeros(N,1);
% u(1:Nu) = uopt;
% if Nu<N
%     u(1:Nu+1:N) = uopt(end);
% end
%% Integrate system
if strcmp(select_model,'DelayDMDc')
    Uinput = getHankelMatrix_MV([p.udelay(2:end)';u],p.Ndelay)';
    [xk,~] = lsim(p.sys,Uinput,[0:N-1].*p.dt,p.xdelay);
    xk = xk(:,end-Nvar+1:end);
    xk = xk + repmat(p.xmean',[N 1]); xk = xk';
elseif strcmp(select_model,'DMDc')
    [xk,~] = lsim(p.sys,[u' 0],[0:N].*p.dt,x-p.xmean);
    xk = xk(2:end,:) + repmat(p.xmean',[N 1]); xk = xk';
elseif strcmp(select_model,'eDMDc')
    Y0 = poolData((x-p.xmean)',Nvar,p.polyorder,p.usesine)';
    [xk,~] = lsim(p.sys,[u' 0],[0:N].*p.dt,Y0(2:end));
    xk = xk(2:end,1:Nvar) + repmat(p.xmean',[N 1]); xk = xk';   
elseif strcmp(select_model,'SINDYc')
    Ns = size(x,1);
    xk = zeros(Ns,N+1); xk(:,1) = x;
    for ct=1:N
        % Obtain plant state at next prediction step.
        xk(:,ct+1) = rk4u(@sparseGalerkinControl_Discrete,xk(:,ct),u(ct),p.dt,1,[],p);
    end
    xk = xk(:,2:N+1);
elseif strcmp(select_model,'partialSINDYc')
    Ns = size(x,1);
    xk = zeros(Ns,N+1); xk(:,1) = x;
    for ct=1:N
        % Obtain plant state at next prediction step.
        xk_tmp = rk4u(@sparseGalerkinControl_Discrete,xk(p.SelectVars,ct),u(ct),p.dt,1,[],p);
        xk(p.SelectVars,ct+1) = xk_tmp;
    end
    xk = xk(:,2:N+1);    
elseif strcmp(select_model,'NARX')
    Hu = [u',0];
    Hx = zeros(Nvar,length(Hu)); 
    Hx(:,1) = x;
    if p.TRANSFORM_LOG == 1
        Hx = log(Hx);
    end
    [Us,Ui,Si] = preparets(p.net,con2seq(Hu),{},con2seq(Hx));
    xk = p.net(Us,Ui,Si);
    xk = cell2mat(xk); 
    if p.TRANSFORM_LOG == 1
        xk = exp(xk);
    end
end


%% Cost Calculation
% Set initial plant states, controller output and cost.
uk = u(1);
J = 0;
% Loop through each prediction step.
for ct=1:N
    % Obtain plant state at next prediction step.
    xk1 = xk(:,ct);

    % accumulate state tracking cost from x(k+1) to x(k+N).
    J = J + (xk1-xref')'*Q*(xk1-xref');
    % accumulate MV rate of change cost from u(k) to u(k+N-1).
    if ct==1
        J = J + (uk-u0)'*R*(uk-u0) + Ru*abs(uk);
    else
        J = J + (uk-u(ct-1))'*R*(uk-u(ct-1)) +Ru*abs(uk);
    end
    % Update uk for the next prediction step.
    if ct<N
        uk = u(ct+1);
    end
end

t=0;
