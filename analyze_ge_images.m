function analyze_ge_images(Dis_Image,LoRes_Gas_Image,HiRes_Gas_Image,H1_Image_Dis,Cal_Raw,Proton_Mask,write_path,Dis_Fid,Gas_Fid,Params,Dis_Traj,Gas_Traj)

parent_path = which('analyze_ge_images');
idcs = strfind(parent_path,filesep);%determine location of file separators
parent_path = parent_path(1:idcs(end)-1);%remove file

%% Load Things
if(exist(fullfile(parent_path,'AncillaryFiles','HealthyCohort.mat'),'file') == 2) %if Healthy cohort data exists, use
    HealthyFile = dir(fullfile(parent_path,'AncillaryFiles','HealthyCohort.mat'));%get file info
    HealthyData = load(fullfile(HealthyFile.folder,HealthyFile.name), '-regexp','^(?!Comb|Ind)...');%import all variable but figures
    VentThresh = HealthyData.thresholds.Vent;
    DissolvedThresh = HealthyData.thresholds.Dissolved;
    BarrierThresh = HealthyData.thresholds.Barrier;
    RBCThresh = HealthyData.thresholds.RBC;
    RBCBarrThresh = HealthyData.thresholds.RBCBarr;
   % RBCOscThresh = HealthyData.thresholds.RBCOsc;
    HealthyCohortNum = HealthyData.CohortTag; %Healthy Cohort Data
    HealthyDistPresent = 1;
else %use thresholds from Duke 1.5T Quantitative Analysis Paper 10.1002/mp.12264,
    VentThresh = [0.51-2*0.19,0.51-1*0.19,0.51,0.51+1*0.19,0.51+2*0.19];%6
    DissolvedThresh = [0.0075-2*0.00125,0.0075-1*0.00125,0.0075,0.0075+1*0.00125,0.0075+2*0.00125];%6
    BarrierThresh = [0.0049-2*0.0015,0.0049-1*0.0015,0.0049,0.0049+1*0.0015,0.0049+2*0.0015,0.0049+3*0.0015,0.0049+4*0.0015];%8
    RBCThresh = [0.0026-2*0.0010,0.0026-1*0.0010,0.0026,0.0026+1*0.0010,0.0026+2*0.0010];%6
    RBCBarrThresh = [0.53-2*0.18,0.53-1*0.18,0.53,0.53+1*0.18,0.53+2*0.18];%6
 %   RBCOscThresh = [8.9596-2*10.5608,8.9596-1*10.5608,8.9596,8.9596+1*10.5608,8.9596+2*10.5608,8.9596+3*10.5608,8.9596+4*10.5608];%8
    HealthyCohortNum = 'INITIAL  GUESS'; %Healthy Cohort Data
    HealthyDistPresent = 0;
end
%% Get various Parameters
TR = Params.TR;
TE = Params.TE;
ActTE90 = TE;
GasFA = Params.GasFA;
DisFA = Params.DisFA;
Dwell = Params.Dwell;
freq_jump = Params.freq_offset;
scanDateStr = Params.scandatestr;

%% Calibration
try
    disData_avg = Cal_Raw.data;
    t = double((0:(size(disData_avg,1)-1))*Cal_Raw.dwell);
    disfitObj = Spectroscopy.NMR_TimeFit_v(disData_avg,t,[1 1 1],[0 -700  -7400],[250 200 30],[0 200 0],[0 0 0],0,length(t)); % first widths lorenzian, 2nd are gauss
    disfitObj = disfitObj.fitTimeDomainSignal();
    AppendedDissolvedFit = Cal_Raw.dwell*fftshift(fft(disfitObj.calcComponentTimeDomainSignal(t),[],1),1);
    RBC2Bar = disfitObj.area(1)/disfitObj.area(2);
    RBC2TotDis = disfitObj.area(1)/(disfitObj.area(2)+disfitObj.area(1));
    %View
    DissolvedNMR = figure('Name','Dissolved Phase Spectrum');set(DissolvedNMR,'WindowState','minimized');
    set(DissolvedNMR,'color','white','Units','inches','Position',[0.25 0.25 16 9])
    hold on
    %data
    plot(disfitObj.f, abs(disfitObj.spectralDomainSignal),'b')%mag
    plot(disfitObj.f, real(disfitObj.spectralDomainSignal),'r')%real
    plot(disfitObj.f, imag(disfitObj.spectralDomainSignal),'Color',[0,0.6,0.2]')%imag
    %fits
    plot(disfitObj.f,abs(sum(AppendedDissolvedFit,2)),'Color',[0 0 1 0.33],'LineWidth',3)%mag
    plot(disfitObj.f,real(sum(AppendedDissolvedFit,2)),'Color',[1 0 0 0.33],'LineWidth',3)%real
    plot(disfitObj.f,imag(sum(AppendedDissolvedFit,2)),'Color',[0,0.6,0.2,0.33]','LineWidth',3)%imag
    %components
    area(disfitObj.f,real(AppendedDissolvedFit(:,1)),'FaceColor','r','FaceAlpha',0.33,'LineStyle','none')%rbc
    area(disfitObj.f,real(AppendedDissolvedFit(:,2)),'FaceColor','b','FaceAlpha',0.33,'LineStyle','none')%barrier
    area(disfitObj.f,real(AppendedDissolvedFit(:,3)),'FaceColor',[0,0.6,0.2]','FaceAlpha',0.33,'LineStyle','none')%gas
    %settings
    lgnd = legend({'Spectrum - Magnitude','Spectrum - Real','Spectrum - Imaginary','Fit - Magnitude','Fit - Real','Fit - Imaginary','RBC - Real','Barrier - Real','Gas - Real'},'Location','best','NumColumns',3);
    set(lgnd,'color','none');
    xlim([-8000 2000])
    set(gca, 'XDir','reverse','FontSize',24)
    title(['Dissolved Phase Spectra and Fit: RBC/Barrier = ',num2str(disfitObj.area(1)/disfitObj.area(2))])
    xlabel('Frequency (Hz)')
    ylabel('NMR Signal (a.u.)')
    hold off
    disp('Fitting Spectrum Completed.')

    %T2* Calculations
    GasT2Star = 1/(pi * disfitObj.fwhm(3))*1000; %in ms
    BarrierT2Star = 1/(pi * max([disfitObj.fwhm(2),disfitObj.fwhmG(2)]))*1000; %in ms
    BarrierLtoGRatio = disfitObj.fwhm(2)/disfitObj.fwhmG(2);
    RBCT2Star = 1/(pi * disfitObj.fwhm(1))*1000; %in ms
    %Freqs
    GasFreq = disfitObj.freq(3)+freq_jump;
    BarrierFreq = disfitObj.freq(2)+freq_jump;
    RBCFreq = disfitObj.freq(1)+freq_jump;
    %Contamination
    SpecGasPhaseContaminationPercentage = disfitObj.area(3)/(disfitObj.area(1)+disfitObj.area(2))*100;
catch
    %If no calibration is found, set some "default" values so that it will
    %run through at least.
    DissolvedNMR = figure;
    RBC2Bar = 0.5;
    GasT2Star = 15;
    BarrierT2star = 1.5;
    RBCT2Star = 1.5;
end

%% View Wiggles
%For my data, negative gives the correct wiggles (all in RBC). We do one
%extra complex conjugate between here and recon, need to use positive
%RBC/Barrier for image Dixon separation.
[Dis_Shift,~] = AllinOne_Tools.SinglePointDixon_FID(Dis_Fid,RBC2Bar,Gas_Fid);

RBC_Fid = real(Dis_Shift);
Bar_Fid = imag(Dis_Shift);

if(mean(RBC_Fid(1,:))<0)
    RBC_Fid = -RBC_Fid;
end
if(mean(Bar_Fid(1,:))<0)
    Bar_Fid = -Bar_Fid;
end

TR = Params.TR;
NProj = length(RBC_Fid);
Time_Axis = (0:(NProj-1))*TR/1000;
SampF = 1/(TR/1000);
Freq_Axis = SampF*((-(NProj/2)+1):(NProj/2))/NProj;

k0fig = figure('Name','RBC and Barrier k0');
subplot(3,2,1)
plot(Time_Axis,RBC_Fid(1,:),'.r','MarkerSize',8)
title('RBC k0')
xlabel('Time (s)')
ylabel('Intensity (Arb)')
subplot(3,2,2)
plot(Time_Axis,Bar_Fid(1,:),'.b','MarkerSize',8)
title('Barrier k0')
ylabel('Intensity (Arb)')
xlabel('Time (s)')
subplot(3,2,3)
plot(Time_Axis,smooth(RBC_Fid(1,:),20),'.r','MarkerSize',8)
title('Smoothed RBC k0')
xlabel('Time (s)')
ylabel('Intensity (Arb)')
subplot(3,2,4)
plot(Time_Axis,smooth(Bar_Fid(1,:),20),'.r','MarkerSize',8)
title('Smoothed Barrier k0')
xlabel('Time (s)')
ylabel('Intensity (Arb)')
subplot(3,2,5)
FFTRBC = abs(fftshift(fft(RBC_Fid(1,:))));
plot(Freq_Axis,FFTRBC,'r')
xlim([0.5 3])
title('FFT of RBC k0')
xlabel('Frequency (Hz)')
ylabel('Intensity (Arb)')
subplot(3,2,6)
FFTBar = abs(fftshift(fft(Bar_Fid(1,:))));
plot(Freq_Axis,FFTBar,'b')
xlim([0.5 3])
title('FFT of Barrier k0')
xlabel('Frequency (Hz)')
ylabel('Intensity (Arb)')
set(k0fig,'WindowState','minimized');

ProtonMax = prctile(abs(H1_Image_Dis(:)),99.99);

%% Separate into RBC and Barrier
[Bar_Image,RBC_Image, Delta_angle_deg, ~] = AllinOne_Tools.SinglePointDixon_V2(Dis_Image,-RBC2Bar,LoRes_Gas_Image,Proton_Mask);

%% Need to do quantitative corrections for imperfect TE90, T2star, etc... use Matt's code
disp('Correcting Image Intensities for Comparison...')
%T2* scaling
%M0 = Mt/(e^(-t/T2*))
GasImageScaled = abs(LoRes_Gas_Image)/(exp(-ActTE90/GasT2Star));
RBCfraction = disfitObj.area(1)/(disfitObj.area(2)+disfitObj.area(1));
DissolvedT2Star = BarrierT2Star*(1-RBCfraction) + RBCT2Star*RBCfraction;
DissolvedImageCorrected = Dis_Image/(exp(-ActTE90/DissolvedT2Star));
BarrierImageCorrected = Bar_Image/(exp(-ActTE90/BarrierT2Star));
RBCImageCorrected = RBC_Image/(exp(-ActTE90/RBCT2Star));

disp('Correcting Image Intensities for Comparison Completed.')
%% Scale Images appropriately
GasImageScaled = GasImageScaled*sind(DisFA)/sind(GasFA);
%Express RBC/Gas, Barrier/Gas, and Dissolved/Gas as %
RBC2Gas = abs(RBCImageCorrected)./abs(GasImageScaled).*Proton_Mask*100;
Bar2Gas = abs(BarrierImageCorrected)./abs(GasImageScaled).*Proton_Mask*100;
RBC2BarIm = abs(RBCImageCorrected)./abs(BarrierImageCorrected).*Proton_Mask;
Dis2Gas = abs(DissolvedImageCorrected)./abs(GasImageScaled).*Proton_Mask*100;

VentMax = prctile(abs(HiRes_Gas_Image(Proton_Mask(:))),99);
ScaledVentImage = abs(HiRes_Gas_Image)/VentMax;
ScaledVentImage(ScaledVentImage>1) = 1;

%% Bin Images

SixBinMap = [1 0 0; 1 0.7143 0; 0.4 0.7 0.4; 0 1 0; 0 0.57 0.71; 0 0 1]; %Used for Vent and RBC
EightBinMap = [1 0 0; 1 0.7143 0; 0.4 0.7 0.4; 0 1 0; 184/255 226/255 145/255; 243/255 205/255 213/255; 225/255 129/255 162/255; 197/255 27/255 125/255]; %Used for barrier
SixBinRBCBarMap = [ 197/255 27/255 125/255; 225/255 129/255 162/255; 0.4 0.7 0.4; 0 1 0; 1 0.7143 0; 1 0 0]; %Used for RBC/Barrier ratio

%Ventilation Binning
VentBinMap = AllinOne_Tools.BinImages(ScaledVentImage,VentThresh);
VentBinMap = VentBinMap.*Proton_Mask;
VentBinMask = logical((VentBinMap-1).*Proton_Mask); %Mask for ventilated areas only

%Dissolved Binning
DissolvedBinMap = AllinOne_Tools.BinImages(Dis2Gas, DissolvedThresh);
DissolvedBinMap = DissolvedBinMap.*VentBinMask;%Mask to ventilated volume

%Barrier Binning
BarrierBinMap = AllinOne_Tools.BinImages(Bar2Gas, BarrierThresh);
BarrierBinMap = BarrierBinMap.*VentBinMask;%Mask to ventilated volume

RBCBinMap = AllinOne_Tools.BinImages(RBC2Gas, RBCThresh);
RBCBinMap = RBCBinMap.*VentBinMask;%Mask to ventilated volume
RBC_Mask = logical((RBCBinMap-1).*VentBinMask); %Create a mask for areas with RBC signal

%RBC/Barrier Binning
RBCBarrierBinMap = AllinOne_Tools.BinImages(RBC2BarIm, RBCBarrThresh);
RBCBarrierBinMap = RBCBarrierBinMap.*VentBinMask;%Mask to ventilated volume

%% Wiggle Analysis
ImSize = size(RBC2Gas,1);
save(fullfile(write_path,'Gas_Exchange_Workspace_4_wiggles.mat'),'Dis_Fid','Gas_Fid','Dis_Traj','Gas_Traj','H1_Image_Dis','LoRes_Gas_Image','Proton_Mask','VentBinMask','RBC_Mask','RBC2Bar','TR','ImSize','scanDateStr','write_path');
AllinOne_Wiggles.wiggle_imaging_2(Dis_Fid,Gas_Fid,Dis_Traj,Gas_Traj,H1_Image_Dis,LoRes_Gas_Image,Proton_Mask,VentBinMask,RBC_Mask,-RBC2Bar,TR,size(RBC2Gas,1),scanDateStr,write_path)

%% Calculate SNR
disp('Calculating SNR...')
NoiseMask = imerode(~Proton_Mask,strel('sphere',7));%avoid edges/artifacts/partialvolume
%((mean signal) - (mean noise)) / (stddev noise)
VentSNR = (mean(abs(HiRes_Gas_Image(VentBinMask(:)))) - mean(abs(HiRes_Gas_Image(NoiseMask(:)))) ) / std(abs(HiRes_Gas_Image(NoiseMask(:))));
GasSNR = (mean(abs(LoRes_Gas_Image(VentBinMask(:)))) - mean(abs(LoRes_Gas_Image(NoiseMask(:)))) ) / std(abs(LoRes_Gas_Image(NoiseMask(:))));
DissolvedSNR = (mean(abs(Dis_Image(VentBinMask(:)))) - mean(abs(Dis_Image(NoiseMask(:)))) ) / std(abs(Dis_Image(NoiseMask(:))));
%CorrDissolvedSNR = (mean(abs(CorrDissolvedImage(HiMask(:)))) - mean(abs(CorrDissolvedImage(NoiseMask(:)))) ) / std(abs(CorrDissolvedImage(NoiseMask(:))));
BarrierSNR = (mean(Bar_Image(VentBinMask(:))) - mean(Bar_Image(NoiseMask(:))) ) / std(Bar_Image(NoiseMask(:)));
RBCSNR = (mean(RBC_Image(VentBinMask(:))) - mean(RBC_Image(NoiseMask(:))) ) / std(RBC_Image(NoiseMask(:)));
disp('Calculating SNR Completed.')

SNRS.VentSNR = VentSNR;
SNRS.GasSNR = GasSNR;
SNRS.DissolvedSNR = DissolvedSNR;
SNRS.BarrierSNR = BarrierSNR;
SNRS.RBCSNR = RBCSNR;
SNRS.RBC2Bar = RBC2Bar;

%% Display Figures
[Anatomic_Fig,Mask_Fig,VentMontage,GasMontage,DissolvedMontage,RBCMontage,BarrierMontage,VentBinMontage,DissolvedBinMontage,RBCBinMontage,BarrierBinMontage,RBCBarBinMontage] = AllinOne_Tools.disp_ge_montages(Tools.canonical2matlab(H1_Image_Dis),Tools.canonical2matlab(Proton_Mask),Tools.canonical2matlab(ScaledVentImage),Tools.canonical2matlab(LoRes_Gas_Image),Tools.canonical2matlab(Dis_Image),Tools.canonical2matlab(Bar_Image),Tools.canonical2matlab(RBC_Image),Tools.canonical2matlab(RBC2BarIm),Tools.canonical2matlab(VentBinMap),Tools.canonical2matlab(DissolvedBinMap),Tools.canonical2matlab(BarrierBinMap),Tools.canonical2matlab(RBCBinMap),Tools.canonical2matlab(RBCBarrierBinMap),SNRS);

[SumVentFig,SumDissFig,SumBarrFig,SumRBCFig,SumRBCBarFig] = AllinOne_Tools.disp_ge_sumfigs(Tools.canonical2matlab(Proton_Mask),Tools.canonical2matlab(VentBinMap),Tools.canonical2matlab(H1_Image_Dis),Tools.canonical2matlab(DissolvedBinMap),Tools.canonical2matlab(BarrierBinMap),Tools.canonical2matlab(RBCBinMap),Tools.canonical2matlab(RBCBarrierBinMap),SNRS);

%% Histograms - Copied from Matt - removed some of the elegance... should fix at some point
disp('Calculating Histograms...')
%Calculate bin ranges
VentEdges = [-0.5, linspace(0,1,100) 1.5];
BarEdges = [-100, linspace(0,BarrierThresh(3)*3,100) 100];
DissEdges = [-100, linspace(0,DissolvedThresh(3)*3,100) 100];
RBCEdges = [-100, linspace(0,RBCThresh(3)*3,100) 100];
RBCBarEdges = [-100, linspace(0,RBCBarrThresh(3)*3,100) 100];


if HealthyDistPresent
    VentHistFig = AllinOne_Tools.CalculateDissolvedHistogram(ScaledVentImage(Proton_Mask(:)),VentEdges,VentThresh,SixBinMap,HealthyData.VentEdges,HealthyData.HealthyVentFit);
    DissHistFig = AllinOne_Tools.CalculateDissolvedHistogram(Dis2Gas(VentBinMask(:)),DissEdges,DissolvedThresh,SixBinMap,HealthyData.DissolvedEdges,HealthyData.HealthyDissFit);
    BarHistFig = AllinOne_Tools.CalculateDissolvedHistogram(Bar2Gas(VentBinMask(:)),BarEdges,BarrierThresh,EightBinMap,HealthyData.BarsEdges,HealthyData.HealthyBarsFit);
    RBCHistFig = AllinOne_Tools.CalculateDissolvedHistogram(RBC2Gas(VentBinMask(:)),RBCEdges,RBCThresh,SixBinMap,HealthyData.RBCEdges,HealthyData.HealthyRBCsFit);
    RBCBarHistFig = AllinOne_Tools.CalculateDissolvedHistogram(RBC2BarIm(VentBinMask(:)),RBCBarEdges,RBCBarrThresh,SixBinRBCBarMap,HealthyData.RBCBarEdges,HealthyData.HealthyRBCBarFit);
  %  RBCOscHistFig = GasExchangeV3.CalculateDissolvedHistogram(RBCOsc(RBCBinMask(:)),RBCOscEdges,RBCOscThresh,EightBinMap,HealthyData.RBCOscEdges,HealthyData.HealthyRBCOscFit);
else
    VentHistFig = AllinOne_Tools.CalculateDissolvedHistogram(ScaledVentImage(Proton_Mask(:)),VentEdges,VentThresh,SixBinMap,[],[]);
    DissHistFig = AllinOne_Tools.CalculateDissolvedHistogram(Dis2Gas(VentBinMask(:)),DissEdges,DissolvedThresh,SixBinMap,[],[]);
    BarHistFig = AllinOne_Tools.CalculateDissolvedHistogram(Bar2Gas(VentBinMask(:)),BarEdges,BarrierThresh,EightBinMap,[],[]); 
    RBCHistFig = AllinOne_Tools.CalculateDissolvedHistogram(RBC2Gas(VentBinMask(:)),RBCEdges,RBCThresh,SixBinMap,[],[]);
    RBCBarHistFig = AllinOne_Tools.CalculateDissolvedHistogram(RBC2BarIm(VentBinMask(:)),RBCBarEdges,RBCBarrThresh,SixBinRBCBarMap,[],[]);
end

%Edit Names/Titles
set(VentHistFig,'Name','Ventilation Histogram');%title(VentHistFig.CurrentAxes,'99 Percentile Scaled Ventilation Histogram');
set(DissHistFig,'Name','Dissolved Histogram');%title(DissHistFig.CurrentAxes,'Dissolved:Gas Histogram');
set(BarHistFig,'Name','Barrier Histogram');%title(BarHistFig.CurrentAxes,'Barrier:Gas Histogram');
set(RBCHistFig,'Name','RBC Histogram');%title(RBCHistFig.CurrentAxes,'RBC:Gas Histogram');
set(RBCBarHistFig,'Name','RBC:Barrier Histogram');%title(RBCBarHistFig.CurrentAxes,'RBC:Barrier Histogram');

disp('Calculating Histograms Completed.')

%% Quantify Defects, Intensities, etc.
disp('Quantifying Images...')
%Ventilation Quantification
VentBins.VentMean = mean(ScaledVentImage(Proton_Mask(:)));
VentBins.VentStd = std(ScaledVentImage(Proton_Mask(:)));
VentBins.VentBin1Percent = sum(VentBinMap(:)==1)/sum(Proton_Mask(:)==1)*100;
VentBins.VentBin2Percent = sum(VentBinMap(:)==2)/sum(Proton_Mask(:)==1)*100;
VentBins.VentBin3Percent = sum(VentBinMap(:)==3)/sum(Proton_Mask(:)==1)*100;
VentBins.VentBin4Percent = sum(VentBinMap(:)==4)/sum(Proton_Mask(:)==1)*100;
VentBins.VentBin5Percent = sum(VentBinMap(:)==5)/sum(Proton_Mask(:)==1)*100;
VentBins.VentBin6Percent = sum(VentBinMap(:)==6)/sum(Proton_Mask(:)==1)*100;

%Dissolved/Gas Quantification
DisBins.DissolvedMean = mean(Dis2Gas(VentBinMask(:)));
DisBins.DissolvedStd = std(Dis2Gas(VentBinMask(:)));
DisBins.DissolvedBin1Percent = sum(DissolvedBinMap(:)==1)/sum(VentBinMask(:)==1)*100;
DisBins.DissolvedBin2Percent = sum(DissolvedBinMap(:)==2)/sum(VentBinMask(:)==1)*100;
DisBins.DissolvedBin3Percent = sum(DissolvedBinMap(:)==3)/sum(VentBinMask(:)==1)*100;
DisBins.DissolvedBin4Percent = sum(DissolvedBinMap(:)==4)/sum(VentBinMask(:)==1)*100;
DisBins.DissolvedBin5Percent = sum(DissolvedBinMap(:)==5)/sum(VentBinMask(:)==1)*100;
DisBins.DissolvedBin6Percent = sum(DissolvedBinMap(:)==6)/sum(VentBinMask(:)==1)*100;

%Barrier/Gas Quantification
BarBins.BarrierUptakeMean = mean(Bar2Gas(VentBinMask(:)));
BarBins.BarrierUptakeStd = std(Bar2Gas(VentBinMask(:)));
BarBins.BarrierUptakeBin1Percent = sum(BarrierBinMap(:)==1)/sum(VentBinMask(:)==1)*100;
BarBins.BarrierUptakeBin2Percent = sum(BarrierBinMap(:)==2)/sum(VentBinMask(:)==1)*100;
BarBins.BarrierUptakeBin3Percent = sum(BarrierBinMap(:)==3)/sum(VentBinMask(:)==1)*100;
BarBins.BarrierUptakeBin4Percent = sum(BarrierBinMap(:)==4)/sum(VentBinMask(:)==1)*100;
BarBins.BarrierUptakeBin5Percent = sum(BarrierBinMap(:)==5)/sum(VentBinMask(:)==1)*100;
BarBins.BarrierUptakeBin6Percent = sum(BarrierBinMap(:)==6)/sum(VentBinMask(:)==1)*100;
BarBins.BarrierUptakeBin7Percent = sum(BarrierBinMap(:)==7)/sum(VentBinMask(:)==1)*100;
BarBins.BarrierUptakeBin8Percent = sum(BarrierBinMap(:)==8)/sum(VentBinMask(:)==1)*100;

%RBC/Gas Quantification
RBCBins.RBCTransferMean = mean(RBC2Gas(VentBinMask(:)));
RBCBins.RBCTransferStd = std(RBC2Gas(VentBinMask(:)));
RBCBins.RBCTransferBin1Percent = sum(RBCBinMap(:)==1)/sum(VentBinMask(:)==1)*100;
RBCBins.RBCTransferBin2Percent = sum(RBCBinMap(:)==2)/sum(VentBinMask(:)==1)*100;
RBCBins.RBCTransferBin3Percent = sum(RBCBinMap(:)==3)/sum(VentBinMask(:)==1)*100;
RBCBins.RBCTransferBin4Percent = sum(RBCBinMap(:)==4)/sum(VentBinMask(:)==1)*100;
RBCBins.RBCTransferBin5Percent = sum(RBCBinMap(:)==5)/sum(VentBinMask(:)==1)*100;
RBCBins.RBCTransferBin6Percent = sum(RBCBinMap(:)==6)/sum(VentBinMask(:)==1)*100;

%RBC/Barrier Quantification
RBC2BarBins.RBCBarrierMean = nanmean(RBC2BarIm(VentBinMask(:)&~isinf(RBC2BarIm(:))));
RBC2BarBins.RBCBarrierStd = nanstd(RBC2BarIm(VentBinMask(:)&~isinf(RBC2BarIm(:))));
RBC2BarBins.RBCBarrierBin1Percent = sum(RBCBarrierBinMap(:)==1)/sum(VentBinMask(:)==1)*100;
RBC2BarBins.RBCBarrierBin2Percent = sum(RBCBarrierBinMap(:)==2)/sum(VentBinMask(:)==1)*100;
RBC2BarBins.RBCBarrierBin3Percent = sum(RBCBarrierBinMap(:)==3)/sum(VentBinMask(:)==1)*100;
RBC2BarBins.RBCBarrierBin4Percent = sum(RBCBarrierBinMap(:)==4)/sum(VentBinMask(:)==1)*100;
RBC2BarBins.RBCBarrierBin5Percent = sum(RBCBarrierBinMap(:)==5)/sum(VentBinMask(:)==1)*100;
RBC2BarBins.RBCBarrierBin6Percent = sum(RBCBarrierBinMap(:)==6)/sum(VentBinMask(:)==1)*100;
%% Save all Images as Nifti - compressed


GE_info = AllinOne_Tools.nifti_metadata(LoRes_Gas_Image,Params.GE_Voxel,Params.GE_FOV);
niftiwrite(abs(HiRes_Gas_Image),fullfile(write_path,'Sharp_Kernel_Lo_Res'),GE_info,'Compressed',true);
niftiwrite(abs(LoRes_Gas_Image),fullfile(write_path,'LowResGas'),GE_info,'Compressed',true);
niftiwrite(abs(Dis_Image),fullfile(write_path,'TotalDissolved'),GE_info,'Compressed',true);
niftiwrite(Bar_Image,fullfile(write_path,'Barrier'),GE_info,'Compressed',true);
niftiwrite(RBC_Image,fullfile(write_path,'RBC'),GE_info,'Compressed',true);
niftiwrite(BarrierBinMap,fullfile(write_path,'Barrier_Labeled'),GE_info,'Compressed',true);
niftiwrite(RBCBinMap,fullfile(write_path,'RBC_Labeled'),GE_info,'Compressed',true);
niftiwrite(VentBinMap,fullfile(write_path,'Vent_Labeled'),GE_info,'Compressed',true);
niftiwrite(RBCBarrierBinMap,fullfile(write_path,'RBC2Bar_Labeled'),GE_info,'Compressed',true);

%Write out some of the scaled images
niftiwrite(GasImageScaled,fullfile(write_path,'Scaled_Gas_Image'),GE_info,'Compressed',true);
niftiwrite(RBCImageCorrected,fullfile(write_path,'Corrected_RBC'),GE_info,'Compressed',true);
niftiwrite(BarrierImageCorrected,fullfile(write_path,'Corrected_Barrier'),GE_info,'Compressed',true);
niftiwrite(ScaledVentImage,fullfile(write_path,'Scaled_Vent_Image'),GE_info,'Compressed',true);
niftiwrite(RBC2Gas,fullfile(write_path,'RBC_to_Gas'),GE_info,'Compressed',true);
niftiwrite(Bar2Gas,fullfile(write_path,'Barrier_to_Gas'),GE_info,'Compressed',true);
niftiwrite(RBC2BarIm,fullfile(write_path,'RBC_to_Barrier_Im'),GE_info,'Compressed',true);

%write out images in a manner that is good for sharing with subjects - Just
%do barrier and RBC - get the Ventilation one elsewhere
if ~isfolder(fullfile(write_path,'Shareable_Figs'))
    mkdir(fullfile(write_path,'Shareable_Figs'))
end

saveas(RBCMontage,fullfile(write_path,'Shareable_Figs','Raw_RBC_Image.jpg'));
saveas(BarrierMontage,fullfile(write_path,'Shareable_Figs','Raw_Tissue_Image.jpg'));
saveas(RBCBinMontage,fullfile(write_path,'Shareable_Figs','Binned_RBC_Image.jpg'));
saveas(BarrierBinMontage,fullfile(write_path,'Shareable_Figs','Binned_Tissue_Image.jpg'));

Vent_Pts = ScaledVentImage(Proton_Mask(:));
Bar_Pts = Bar2Gas(VentBinMask(:));
RBC_Pts = RBC2Gas(VentBinMask(:));
RBC2Bar_Pts = RBC2BarIm(VentBinMask(:));

save(fullfile(write_path,'GasExchangeWorkspace.mat'),'RBC2Bar_Pts','RBC_Pts','Bar_Pts','Vent_Pts','ScaledVentImage','Proton_Mask','Dis2Gas','VentBinMask','Bar2Gas','RBC2Gas','RBC2BarIm','RBC2Bar');

%% Write Reports
try
    AllinOne_Tools.write_clin_report(write_path,scanDateStr,HealthyDistPresent,HealthyData,VentBins,SumVentFig,RBCBins,SumRBCFig,BarBins,SumBarrFig,SumRBCBarFig,RBC2BarBins,VentHistFig,BarHistFig,RBCHistFig,RBCBarHistFig,RBC2Bar)
catch
    disp('No Clinical Report Written')
end
try
    AllinOne_Tools.write_full_report(write_path,scanDateStr,HealthyDistPresent,HealthyData,VentBins,RBCBins,BarBins,RBC2BarBins,VentBinMontage,VentHistFig,RBCBinMontage,RBCHistFig,BarrierBinMontage,BarHistFig,RBCBarBinMontage,RBCBarHistFig,k0fig,DissolvedNMR,Mask_Fig,VentMontage,GasMontage,DissolvedMontage,RBCMontage,BarrierMontage);
catch
    disp('No Technical Report Written')
end
%% Write to Excel
matfile = 'All_in_One_GasExchange.mat';
excel_summary_file = fullfile(parent_path,'AncillaryFiles','AllinOne_Gas_Exchange_Summary.xlsx');
idcs = strfind(write_path,filesep);%determine location of file separators
try
    sub_ind = strfind(write_path,'Xe-');
    sub_end = find(idcs>sub_ind,1,'first');
    sub_end = idcs(sub_end);
    move = true;
    while move
        if write_path(sub_ind-1) ~= '_'
            sub_ind = sub_ind - 1;
        else
            move = false;
        end
    end
    Subject = write_path(sub_ind:(sub_end-1));
catch
    Subject = 'Unknown';
end

SubjectMatch = [];
try 
    load(fullfile(parent_path,'AncillaryFiles',matfile),'AllSubjectSummary');
    SubjectMatch = find(strcmpi(AllSubjectSummary.Subject,Subject) &...
            strcmpi(AllSubjectSummary.Scan_Date,scanDateStr));
catch
    headers = {'Subject', 'Scan_Date',...%Subject Info
                'TE90', 'Flip_Angle',...%Acquisition Info
                'Process_Date', 'Healthy_Cohort',...%Reconstruction Info
                'Gas_Frequency', 'Barrier_Frequency', 'RBC_Frequency',...%Spectro Fitting Results - Freq
                'Gas_T2star', 'Barrier_T2star', 'Barrier_LtoG_ratio', 'RBC_T2star',...%Spectro Fitting Results - T2*
                'Gas_Phase', 'Barrier_Phase', 'RBC_Phase',...%Spectro Fitting Results - Phase
                'RBC_Barrier_Ratio', 'Gas_Contamination', 'Dixon_Phase_Shift',...%Reconstruction Parameters
                'Ventilation_SNR', 'Gas_SNR', 'Dissolved_SNR', 'Barrier_SNR', 'RBC_SNR',...%SNRs
                'Ventilation_Mean', 'Ventilation_Std_Dev',...%Quantitative Distributions - Vent
                'Dissolved_Mean', 'Dissolved_Std_Dev',...%Quantitative Distributions - Dissolved
                'Barrier_Uptake_Mean', 'Barrier_Uptake_Std_Dev',...%Quantitative Distributions - Barrier
                'RBC_Transfer_Mean', 'RBC_Transfer_Std_Dev',...%Quantitative Distributions - RBC
                'RBC2Barrier_Mean', 'RBC2Barrier_Std_Dev',...%Quantitative Distributions - RBC:Barrier
                'Ventilation_Bin1_Percent', 'Ventilation_Bin2_Percent', 'Ventilation_Bin3_Percent', 'Ventilation_Bin4_Percent', 'Ventilation_Bin5_Percent', 'Ventilation_Bin6_Percent',...%Binning Results - Vent
                'Dissolved_Bin1_Percent', 'Dissolved_Bin2_Percent', 'Dissolved_Bin3_Percent', 'Dissolved_Bin4_Percent', 'Dissolved_Bin5_Percent', 'Dissolved_Bin6_Percent',...%Binning Results - Dissolved
                'Barrier_Uptake_Bin1_Percent', 'Barrier_Uptake_Bin2_Percent', 'Barrier_Uptake_Bin3_Percent', 'Barrier_Uptake_Bin4_Percent', 'Barrier_Uptake_Bin5_Percent', 'Barrier_Uptake_Bin6_Percent', 'Barrier_Uptake_Bin7_Percent', 'Barrier_Uptake_Bin8_Percent',...%Binning Results - Barrier
                'RBC_Transfer_Bin1_Percent', 'RBC_Transfer_Bin2_Percent', 'RBC_Transfer_Bin3_Percent', 'RBC_Transfer_Bin4_Percent', 'RBC_Transfer_Bin5_Percent', 'RBC_Transfer_Bin6_Percent',...%Binning Results - RBC
                'RBC2Barrier_Bin1_Percent', 'RBC2Barrier_Bin2_Percent', 'RBC2Barrier_Bin3_Percent', 'RBC2Barrier_Bin4_Percent', 'RBC2Barrier_Bin5_Percent', 'RBC2Barrier_Bin6_Percent',...%Binning Results - RBC:Barrier
                };
    AllSubjectSummary = cell2table(cell(0,size(headers,2)));
    AllSubjectSummary.Properties.VariableNames = headers;
end
NewData = {Subject,scanDateStr,...
            ActTE90,DisFA,...
            datestr(date,29),HealthyCohortNum,...
            GasFreq, BarrierFreq, RBCFreq,...%Spectro Fitting Results - Freq
            GasT2Star, BarrierT2Star, BarrierLtoGRatio, RBCT2Star,...%Spectro Fitting Results - T2*
            disfitObj.phase(3), disfitObj.phase(2), disfitObj.phase(1),...%Spectro Fitting Results - Phase
            RBC2Bar, SpecGasPhaseContaminationPercentage, Delta_angle_deg,...%Reconstruction Parameters
            VentSNR, GasSNR, DissolvedSNR, BarrierSNR, RBCSNR,...%SNRs
            VentBins.VentMean, VentBins.VentStd,...%Quantitative Distributions - Vent
            DisBins.DissolvedMean, DisBins.DissolvedStd,...%Quantitative Distributions - Dissolved
            BarBins.BarrierUptakeMean, BarBins.BarrierUptakeStd,...%Quantitative Distributions - Barrier
            RBCBins.RBCTransferMean, RBCBins.RBCTransferStd,...%Quantitative Distributions - RBC
            RBC2BarBins.RBCBarrierMean, RBC2BarBins.RBCBarrierStd,...%Quantitative Distributions - RBC:Barrier
            VentBins.VentBin1Percent, VentBins.VentBin2Percent, VentBins.VentBin3Percent, VentBins.VentBin4Percent, VentBins.VentBin5Percent, VentBins.VentBin6Percent,...%Binning Results - Vent
            DisBins.DissolvedBin1Percent, DisBins.DissolvedBin2Percent, DisBins.DissolvedBin3Percent, DisBins.DissolvedBin4Percent, DisBins.DissolvedBin5Percent, DisBins.DissolvedBin6Percent,...%Binning Results - Dissolved
            BarBins.BarrierUptakeBin1Percent, BarBins.BarrierUptakeBin2Percent, BarBins.BarrierUptakeBin3Percent, BarBins.BarrierUptakeBin4Percent, BarBins.BarrierUptakeBin5Percent, BarBins.BarrierUptakeBin6Percent, BarBins.BarrierUptakeBin7Percent, BarBins.BarrierUptakeBin8Percent,...%Binning Results - Barrier
            RBCBins.RBCTransferBin1Percent, RBCBins.RBCTransferBin2Percent, RBCBins.RBCTransferBin3Percent, RBCBins.RBCTransferBin4Percent, RBCBins.RBCTransferBin5Percent, RBCBins.RBCTransferBin6Percent,...%Binning Results - RBC
            RBC2BarBins.RBCBarrierBin1Percent, RBC2BarBins.RBCBarrierBin2Percent, RBC2BarBins.RBCBarrierBin3Percent, RBC2BarBins.RBCBarrierBin4Percent,RBC2BarBins.RBCBarrierBin5Percent, RBC2BarBins.RBCBarrierBin6Percent,...%Binning Results - RBC:Barrier
            };
if (isempty(SubjectMatch))%if no match
    AllSubjectSummary = [AllSubjectSummary;NewData];%append
else
    AllSubjectSummary(SubjectMatch,:) = NewData;%overwrite
end
save(fullfile(parent_path,'AncillaryFiles',matfile),'AllSubjectSummary')
writetable(AllSubjectSummary,excel_summary_file,'Sheet',1)
