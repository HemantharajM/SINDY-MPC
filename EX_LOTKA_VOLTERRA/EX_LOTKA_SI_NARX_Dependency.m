% LOTKA-VOLTERRA system
% System identification: NARX

clear all, close all, clc
TrainAlg = 'trainbr'; %trainlm,trainbr


DERIV_NOISE = 0;
TRACK_MODEL_BEST = 1;

%% paths & folders

figpath = ['../FIGURES/EX_LOTKA_Dependencies/NARX/',TrainAlg,'/']; mkdir(figpath)
datapath = ['../DATA/EX_LOTKA_Dependencies/NARX/',TrainAlg,'/']; mkdir(datapath)

addpath('../utils');

%% Parameters
ModelName = 'NARX';
dep_trainlength = 1;
dep_noise = 0;

stateDelays = 1;        % state delay vector
inputDelays = 1;        % input delay vector
hiddenSizes = [10];     % network structure (number of neurons per layer)

MOD_VAL = 10;

% Ntrain_vec = [5:15,20:5:95,100:100:1000];%,1500:500:3000];
Ntrain_vec = [5:15,20:5:95,100:100:1000,1250,1500,2000,3000];
eta_vec = 0.05;
Nr = 50;

% Ntrain_vec = 3000;
% eta_vec = [0.01 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5];

N_LENGTHS = length(Ntrain_vec);
N_ETA = length(eta_vec);

SAVE_MODEL = 0;
SHOW_RESULTS = 0;
SHOW_STATS = 1;
ONLY_TRAINING_LENGTH = 0; % if 0 : 3000 time unit, otherwise 1000

%% Generate Data %{'sine2', 'chirp','prbs', 'sphs'}
InputSignalType = 'sphs'; %prbs; chirp; noise; sine2; sphs; mixed
getTrainingData

DataTrain.x = x;
DataTrain.t = t;
DataTrain.tspan = tspan;
DataTrain.u = u;

xstd = std(xv(:,1));

rng(0,'twister')
close all

errBest = inf*ones(N_LENGTHS,N_ETA);
% BestModels(1:N_LENGTHS,1:N_ETA) = struct('name', [], 'polyorder', [], 'usesine', [], 'Xi', [], ...
%     'dt', [], 'N', [], 'Ttraining', [], 'Err', [], 'ErrM', []);
BestModelsList = zeros(N_LENGTHS,N_ETA);
%% NARX: Training
for iN = 1:N_LENGTHS
    for iNoise = 1:N_ETA
        disp(['Running for noise case ', num2str(iNoise), ' of ', num2str(N_ETA)])
        
        Results = struct('err', zeros(Nr,1), 'errM', zeros(Nr,1), 'xA', zeros(length(tv),2), 'xB', zeros(length(tv),2,Nr),'Ttraining',zeros(Nr,1));
        
        for iR = 1:Nr
            
            % Setup data
            x = DataTrain.x(1:Ntrain_vec(iN),:);
            u = DataTrain.u(1:Ntrain_vec(iN));
            t = DataTrain.t(1:Ntrain_vec(iN));
            tspan = DataTrain.tspan(1:Ntrain_vec(iN));
            
            % Add noise
            eps = eta_vec(iNoise)*xstd;
            x = x + eps*randn(size(x));
            
            %rng(2,'twister')
            
            % prepare training data
            yt = con2seq(x');
            yi = con2seq(u);
            
            % Nonlinear autoregressive neural network
            net = narxnet(inputDelays,stateDelays, hiddenSizes);
            
            % Training parameters %nnstart
            net.trainFcn = TrainAlg;%'trainbr' (noisy); %'trainlm'; trainscg (large-scale)
            net.trainParam.min_grad = 1e-10;
            net.trainParam.showCommandLine = 1;
            net.trainParam.showWindow = false;
            net.trainParam.epochs = 1000;
            
            % Prepares training data (shifting, copying feedback targets into inputs as needed, etc.)
            [Us,Ui,Si,Ss] = preparets(net,yi,{},yt); %yt
            
            % Train net with prepared training data in open-loop
            tic
            net = train(net,Us,Ss,Ui,Si);
            
            % Close loop for recursive prediction
            netc = closeloop(net);
            
            telapsed = toc
            %% Prediction over training phase
            % prepare training data
            yt = con2seq(DataTrain.x');
            yi = con2seq(DataTrain.u);
            
            % Prepare validation data / Get initial state from training data
            [Us,Ui,Si,So] = preparets(netc,yi,{},yt);
            
            % Predict on validation data
            predict = netc(Us,Ui,Si);
            xNARX = [x(1,:);cell2mat(predict)'];
            
            % Error
            e = cell2mat(gsubtract(So,predict));
            
            % Show validation
            SHOW_PREDICTION_FOR_TRAINING_PHASE
            
            %% Prediction
            % prepare validation data
            yt_valid = con2seq([DataTrain.x(end,:)',xv']);
            yi_valid = con2seq([DataTrain.u(end),uv]);
            [Us,Ui,Si,So] = preparets(netc,yi_valid,{},yt_valid);
            
            % Reference
            xA      = xv;
            tA      = tv;
            
            % Predict on validation data
            predict = netc(Us,Ui,Si);
            xB = [DataTrain.x(end,:);cell2mat(predict)'];
            tB = [DataTrain.t(end);tA];
            
            % Show training and prediction
            if SHOW_RESULTS == 1
                if mod(iR,MOD_VAL) == 0 || iR == 1
                    clear ph
                    f1 = figure('visible','off');box on, hold on,
                    ccolors = get(gca,'colororder');
                    plot([tB(1),tB(1)],[-15 260],':','Color',[0.4,0.4,0.4],'LineWidth',1.5)
                    plot([t(end),t(end)],[-15 260],':','Color',[0.4,0.4,0.4],'LineWidth',1.5)
                    ylim([0 250])
                    text(5,230,'Training', 'FontSize',12)
                    %                     text(10+tA(1),230,'Validation', 'FontSize',12)
                    text(3+tA(1),230,'Validation', 'FontSize',12)
                    
                    if eps~=0
                        ph(3) = plot(tspan,x(:,1),'-','Color',0.7*ones(1,3),'LineWidth',1); %ccolors(1,:)+[0.15 0.3 0.25]
                        plot(tspan,x(:,2),'-','Color',0.7*ones(1,3),'LineWidth',1); %ccolors(2,:)+[0.15 0.3 0.25]
                        ph(1) = plot([DataTrain.t;tA],[DataTrain.x(:,1);xA(:,1)],'-','Color',ccolors(1,:),'LineWidth',0.5);
                        ph(2) = plot([DataTrain.t;tA],[DataTrain.x(:,2);xA(:,2)],'-','Color',ccolors(2,:),'LineWidth',0.5);
                    else
                        ph(1) = plot([DataTrain.t;tA],[DataTrain.x(:,1);xA(:,1)],'-','Color',ccolors(1,:),'LineWidth',1);
                        ph(2) = plot([DataTrain.t;tA],[DataTrain.x(:,2);xA(:,2)],'-','Color',ccolors(2,:),'LineWidth',1);
                        ph(3) = plot(t,x(:,1),'--','Color',[0 1 0],'LineWidth',1); % Training data
                        plot(t,x(:,2),'--','Color',[0 1 0],'LineWidth',1);
                    end
                    
                    ph(4) = plot(tB,xB(:,1),'-.','Color',ccolors(1,:)-[0 0.2 0.2],'LineWidth',2);
                    ph(5) = plot(tB,xB(:,2),'-.','Color',ccolors(2,:)-[0.1 0.2 0.09],'LineWidth',2);
                    grid off
                    xlim([0 tv(end)])
                    xlabel('Time')
                    ylabel('Population size')
                    set(gca,'LineWidth',1, 'FontSize',14)
                    set(gcf,'Position',[100 100 300 200])
                    set(gcf,'PaperPositionMode','auto')
                    print('-depsc2', '-loose','-cmyk', [figpath,'EX_LOTKA_SI_',ModelName,'_',InputSignalType,'_Validation_N',sprintf('%04g',Ntrain_vec(iN)),'_Eta',sprintf('%03g',100*eta_vec(iNoise)),'_iR',num2str(iR),'_noleg.eps']);
                    
                    if eps~=0
                        lh = legend(ph([1,3,4]),'Truth','Training',ModelName,'Location','NorthWest');
                        %                         lh.Position = [lh.Position(1)+0.13,lh.Position(2)-0.2,lh.Position(3:4)];
                        lh.Position = [lh.Position(1)+0.02,lh.Position(2)-0.06,lh.Position(3:4)];
                    else
                        lh = legend(ph([1,3,4]),'Truth','Training',ModelName,'Location','NorthWest');
                        lh.Position = [lh.Position(1)+0.13,lh.Position(2)-0.2,lh.Position(3:4)];
                    end
                    print('-depsc2', '-loose','-cmyk', [figpath,'EX_LOTKA_SI_',ModelName,'_',InputSignalType,'_Validation_N',sprintf('%04g',Ntrain_vec(iN)),'_Eta',sprintf('%03g',100*eta_vec(iNoise)),'_iR',num2str(iR),'.eps']);
                    close(f1);
                end
            end
            %% Error
            err = mean(sum((xB(2:end,:)-xA).^2,2));
            errM = mean(sum((xB(2:250+1,:)-xA(1:250,:)).^2,2));
            
            %% Save Data
            Model.name = 'NARX';
            Model.net = netc;
            Model.stateDelays = stateDelays;
            Model.inputDelays = inputDelays;
            Model.hiddenSizes = hiddenSizes;
            Model.dt = dt;
            Model.Ttraining = telapsed;
            Model.Err = err;
            Model.ErrM = errM;
            
            if SAVE_MODEL == 1
                if mod(iR,MOD_VAL) == 0 || iR == 1
                    
                    save(fullfile(datapath,['EX_LOTKA_SI_',ModelName,'_',InputSignalType,'_N',sprintf('%04g',Ntrain_vec(iN)),'_Eta',sprintf('%03g',100*eta_vec(iNoise)),'_iR',num2str(iR),'.mat']),'Model')
                end
            end
            
            Results.err(iR) = err;
            Results.errM(iR) = errM;
            Results.xA = xA;
            Results.xB(:,1:2,iR) = xB(2:end,:);
            Results.Ttraining(iR) = telapsed;
            
            %% Track best model
            % errBest = 10^12*ones(N_LENGTHS,N_ETA)
            if TRACK_MODEL_BEST == 1
                if Results.err(iR)<errBest(iN,iNoise) || iR == 1
                    errBest(iN,iNoise) = Results.err(iR);
                    
                    BestModel = Model;
                    save(fullfile(datapath,['EX_LOTKA_SI_',ModelName,'_',InputSignalType,'_N',sprintf('%04g',Ntrain_vec(iN)),'_Eta',sprintf('%03g',100*eta_vec(iNoise)),'_BEST_MODEL.mat']),'Model')
                    
                    %BestModels(iN,iNoise) = Model;
                    BestModelsList(iN,iNoise) = iR;
                    
                    clear ph
                    f1 = figure('visible','off');box on, hold on,
                    ccolors = get(gca,'colororder');
                    plot([tB(1),tB(1)],[-15 260],':','Color',[0.4,0.4,0.4],'LineWidth',1.5)
                    plot([t(end),t(end)],[-15 260],':','Color',[0.4,0.4,0.4],'LineWidth',1.5)
                    ylim([0 250])
                    text(5,230,'Training', 'FontSize',12)
                    %                     text(10+tA(1),230,'Validation', 'FontSize',12)
                    text(3+tA(1),230,'Validation', 'FontSize',12)
                    
                    if eps~=0
                        ph(3) = plot(tspan,x(:,1),'-','Color',0.7*ones(1,3),'LineWidth',1); %ccolors(1,:)+[0.15 0.3 0.25]
                        plot(tspan,x(:,2),'-','Color',0.7*ones(1,3),'LineWidth',1); %ccolors(2,:)+[0.15 0.3 0.25]
                        ph(1) = plot([DataTrain.t;tA],[DataTrain.x(:,1);xA(:,1)],'-','Color',ccolors(1,:),'LineWidth',0.5);
                        ph(2) = plot([DataTrain.t;tA],[DataTrain.x(:,2);xA(:,2)],'-','Color',ccolors(2,:),'LineWidth',0.5);
                    else
                        ph(1) = plot([DataTrain.t;tA],[DataTrain.x(:,1);xA(:,1)],'-','Color',ccolors(1,:),'LineWidth',1);
                        ph(2) = plot([DataTrain.t;tA],[DataTrain.x(:,2);xA(:,2)],'-','Color',ccolors(2,:),'LineWidth',1);
                        ph(3) = plot(t,x(:,1),'--','Color',[0 1 0],'LineWidth',1); % Training data
                        plot(t,x(:,2),'--','Color',[0 1 0],'LineWidth',1);
                    end
                    
                    ph(4) = plot(tB,xB(:,1),'-.','Color',ccolors(1,:)-[0 0.2 0.2],'LineWidth',2);
                    ph(5) = plot(tB,xB(:,2),'-.','Color',ccolors(2,:)-[0.1 0.2 0.09],'LineWidth',2);
                    grid off
                    xlim([0 tv(end)])
                    xlabel('Time')
                    ylabel('Population size')
                    set(gca,'LineWidth',1, 'FontSize',14)
                    set(gcf,'Position',[100 100 300 200])
                    set(gcf,'PaperPositionMode','auto')
                    print('-depsc2', '-loose','-cmyk', [figpath,'EX_LOTKA_SI_',ModelName,'_',InputSignalType,'_Validation_BEST_MODEL_N',sprintf('%04g',Ntrain_vec(iN)),'_Eta',sprintf('%03g',100*eta_vec(iNoise)),'_noleg.eps']);
                    
                    if eps~=0
                        lh = legend(ph([1,3,4]),'Truth','Training',ModelName,'Location','NorthWest');
                        %                         lh.Position = [lh.Position(1)+0.13,lh.Position(2)-0.2,lh.Position(3:4)];
                        lh.Position = [lh.Position(1)+0.02,lh.Position(2)-0.06,lh.Position(3:4)];
                    else
                        lh = legend(ph([1,3,4]),'Truth','Training',ModelName,'Location','NorthWest');
                        lh.Position = [lh.Position(1)+0.13,lh.Position(2)-0.2,lh.Position(3:4)];
                    end
                    print('-depsc2', '-loose','-cmyk', [figpath,'EX_LOTKA_SI_',ModelName,'_',InputSignalType,'_Validation_BEST_MODEL_N',sprintf('%04g',Ntrain_vec(iN)),'_Eta',sprintf('%03g',100*eta_vec(iNoise)),'.eps']);
                    close(f1);
                end
            end
        end
        disp('===========================================================')
        disp('===========================================================')
        if SHOW_STATS == 1
            %%
            xBmin = min(Results.xB(:,1:2,:),[],3);
            xBmax = max(Results.xB(:,1:2,:),[],3);
            clear ph
            f1 = figure('visible','off');box on, hold on,
            ccolors = get(gca,'colororder');
            plot([tB(1),tB(1)],[-15 260],':','Color',[0.4,0.4,0.4],'LineWidth',1.5)
            plot([t(end),t(end)],[-15 260],':','Color',[0.4,0.4,0.4],'LineWidth',1.5)
            ylim([0 250])
            t1 = text(5,230,'Training', 'FontSize',12);
            t2 = text(5+tA(1),230,'Validation', 'FontSize',12);
            
            
            X=[tB(2:end)',fliplr(tB(2:end)')];                %#create continuous x value array for plotting
            Y=[xBmin(:,1)',flipud(xBmax(:,1))'];              %#create y values for out and then back
            fillh1 = fill(X,Y,ccolors(1,:)-[0 0.2 0.2]);                  %#plot filled area
            fillh1.EdgeColor = ccolors(1,:)-[0 0.2 0.2]; fillh1.FaceAlpha = 0.5;
            
            X=[tB(2:end)',fliplr(tB(2:end)')];                %#create continuous x value array for plotting
            Y=[xBmin(:,2)',flipud(xBmax(:,2))'];              %#create y values for out and then back
            fillh = fill(X,Y,ccolors(2,:)-[0.1 0.2 0.09]);                  %#plot filled area
            fillh.EdgeColor = ccolors(2,:)-[0.1 0.2 0.09]; fillh.FaceAlpha = 0.5;
            
            %             plot(tB(2:end),xBmin(:,1),'-k','LineWidth',2)
            %             plot(tB(2:end),xBmin(:,1),'--g','LineWidth',2)
            
            if eps~=0
                ph(3) = plot(tspan,x(:,1),'-','Color',0.7*ones(1,3),'LineWidth',1); %ccolors(1,:)+[0.15 0.3 0.25]
                plot(tspan,x(:,2),'-','Color',0.7*ones(1,3),'LineWidth',1); %ccolors(2,:)+[0.15 0.3 0.25]
                ph(1) = plot([DataTrain.t;tA],[DataTrain.x(:,1);xA(:,1)],'-','Color',ccolors(1,:),'LineWidth',1);
                ph(2) = plot([DataTrain.t;tA],[DataTrain.x(:,2);xA(:,2)],'-','Color',ccolors(2,:),'LineWidth',1);
            else
                ph(1) = plot([DataTrain.t;tA],[DataTrain.x(:,1);xA(:,1)],'-','Color',ccolors(1,:),'LineWidth',1);
                ph(2) = plot([DataTrain.t;tA],[DataTrain.x(:,2);xA(:,2)],'-','Color',ccolors(2,:),'LineWidth',1);
                ph(3) = plot(t,x(:,1),'--','Color',[0 1 0],'LineWidth',1); % Training data
                plot(t,x(:,2),'--','Color',[0 1 0],'LineWidth',1);
            end
            
            %             ph(4) = plot(tB,xB(:,1),'-.','Color',ccolors(1,:)-[0 0.2 0.2],'LineWidth',2);
            %             ph(5) = plot(tB,xB(:,2),'-.','Color',ccolors(2,:)-[0.1 0.2 0.09],'LineWidth',2);
            grid off
            xlim([0 tv(end)])
            xlabel('Time')
            ylabel('Population size')
            set(gca,'LineWidth',1, 'FontSize',14)
            set(gcf,'Position',[100 100 300 200])
            set(gcf,'PaperPositionMode','auto');
            
            if eps~=0
                lh = legend([ph([1,3]),fillh1],'Truth','Training',ModelName,'Location','NorthWest');
                %             lh.Position = [lh.Position(1)+0.13,lh.Position(2)-0.2,lh.Position(3:4)];
                lh.Position = [lh.Position(1)+0.02,lh.Position(2)-0.06,lh.Position(3:4)];
            else
                lh = legend(ph([1,3,4]),'Truth','Training',ModelName,'Location','NorthWest');
                lh.Position = [lh.Position(1)+0.13,lh.Position(2)-0.2,lh.Position(3:4)];
            end
            print('-depsc2', '-painters','-loose','-cmyk', [figpath,'EX_LOTKA_SI_',ModelName,'_',InputSignalType,'_Validation_N',sprintf('%04g',Ntrain_vec(iN)),'_Eta',sprintf('%03g',100*eta_vec(iNoise)),'_STATS_noleg.eps']);
            
            delete(lh), delete(t1), delete(t2)
            print('-depsc2', '-painters','-loose','-cmyk', [figpath,'EX_LOTKA_SI_',ModelName,'_',InputSignalType,'_Validation_N',sprintf('%04g',Ntrain_vec(iN)),'_Eta',sprintf('%03g',100*eta_vec(iNoise)),'_STATS.eps']);
            close(f1);
        end
        %%
        save(fullfile(datapath,['EX_LOTKA_SI_',ModelName,'_',InputSignalType,'_N',sprintf('%04g',Ntrain_vec(iN)),'_Eta',sprintf('%03g',100*eta_vec(iNoise)),'_STATS.mat']),'Results')
    end
end
% save(fullfile(datapath,['EX_LOTKA_SI_',ModelName,'_',InputSignalType,'_BEST_MODELS.mat']),'BestModels')
save(fullfile(datapath,['EX_LOTKA_SI_',ModelName,'_',InputSignalType,'_BEST_MODELS_LIST.mat']),'BestModelsList')


%%
if ONLY_TRAINING_LENGTH == 1
    length_vec = 5:2:Ntrain-1;
    Results = struct('err', zeros(length(length_vec),2),'RelErr', zeros(length(length_vec),2), 'Ttraining', zeros(length(length_vec),1));
    Results.Ntrain_vec = length_vec;
    for iL = 1:length(length_vec)
        iN = length_vec(iL);
        if mod(iN,50)
            disp(['Running for length ', num2str(iN), 'of ', num2str(Ntrain-1)])
        end
        % Setup data
        x = DataTrain.x(1:iN,:);
        u = DataTrain.u(1:iN);
        t = DataTrain.t(1:iN);
        tspan = DataTrain.tspan(1:iN);
        
        rng(2,'twister')
        
        % prepare training data
        yt = con2seq(x');
        yi = con2seq(u);
        
        % Nonlinear autoregressive neural network
        net = narxnet(inputDelays,stateDelays, hiddenSizes);
        
        % Training parameters %nnstart
        net.trainFcn = TrainAlg;%'trainbr' (noisy); %'trainlm'; trainscg (large-scale)
        net.trainParam.min_grad = 1e-10;
        net.trainParam.showCommandLine = 1;
        net.trainParam.showWindow = false;
        net.trainParam.epochs = 1000;
        
        % Prepares training data (shifting, copying feedback targets into inputs as needed, etc.)
        [Us,Ui,Si,Ss] = preparets(net,yi,{},yt); %yt
        
        % Train net with prepared training data in open-loop
        tic
        net = train(net,Us,Ss,Ui,Si);
        telapsed = toc
        
        % Close loop for recursive prediction
        netc = closeloop(net);
        
        %% Prediction over training phase
        % prepare training data
        yt = con2seq(DataTrain.x');
        yi = con2seq(DataTrain.u);
        
        % Prepare validation data / Get initial state from training data
        [Us,Ui,Si,So] = preparets(netc,yi,{},yt);
        
        % Predict on validation data
        predict = netc(Us,Ui,Si);
        xNARX = [x(1,:);cell2mat(predict)'];
        
        %% Error over training phase
        Results.err(iL,1) = mean(sum((xNARX(1:end,:)-DataTrain.x).^2,2));
        Results.RelErr(iL,1) = mean( abs(sum( (DataTrain.x - xNARX)./DataTrain.x ,2)) );
        
        %% Prediction
        % prepare validation data
        yt_valid = con2seq([DataTrain.x(end,:)',xv']);
        yi_valid = con2seq([DataTrain.u(end),uv]);
        [Us,Ui,Si,So] = preparets(netc,yi_valid,{},yt_valid);
        
        % Reference
        xA      = xv;
        tA      = tv;
        
        % Predict on validation data
        predict = netc(Us,Ui,Si);
        xB = [cell2mat(predict)'];
        tB = [tA];
        %         xB = [DataTrain.x(end,:);cell2mat(predict)'];
        %         tB = [DataTrain.t(end);tA];
        
        
        %% Error over training phase
        Results.err(iL,2) = mean(sum((xB-xA).^2,2));
        Results.RelErr(iL,2) = mean( abs(sum( (xA - xB)./xA ,2)) );
        Results.Ttraining(iL) = telapsed;
    end
    
    Results.DataTrain = DataTrain;
    Results.DataValid.x = xv;
    Results.DataValid.u = uv;
    Results.DataValid.t = tv;
    Results.DataValid.tspan = tspanv;
    save(fullfile(datapath,['EX_LOTKA_SI_',ModelName,'_',InputSignalType,'_Nevol','_STATS.mat']),'Results')
end
