function [MRS_struct] = MRSGABAfit(MRS_struct)
%function [MRS_struct] = MRSGABAfit(MRS_struct)
%
% Keep input and output structure names the same to add output data to 
% the exisiting MRS data structure.
%Inputs:
% MRS_struct = structure with data loaded from MRSLoadPfiles

% Dec 09: based on FitSeries.m:  Richard's GABA Fitting routine
%     Fits using GaussModel
% Feb 10: Change the quantification method for water.  Regions of poor homogeneity (e.g. limbic)
%     can produce highly asymetric lineshapes, which are fitted poorly.  Don't fit - integrate 
%     the water peak.
% March 10: 100301
%           use MRS_struct to pass loaded data data, call MRSGABAinstunits from here.  
%           scaling of fitting to sort out differences between original (RE) and my analysis of FEF data
%           change tolerance on gaba fit
% 110308:   ** BETA VERSION ON /CUBRIC/SCRATCH IN APRIL 2011 **
%     Default: Use NLINFIT for GABA, MINLSQFIT for Water
%     Estimate GABA initial conditions & BCs based on whole spectrum
%     Definitions of fit functions & inst units calc in MRSGABAfit
%     Include FIXED version of Lorentzian fitting
%     Get Navg from struct (use v110303, or above, of MRSLoadPfiles)
%     rejig the output plots - one fig per scan. 
% 110624:   ** RELEASED ON 2 AUG 2011 (MRS WORKSHOP) **
%%%%%%%%%%%%%%%%%%%%% BUG: BaselineModel wrong for water integral****************
%     Default: NLINFIT for GABA and Water
%     Estimate GABA initial & BCs based on data in _fitted_range_
%     Estimate Water initial & BCs based on data
%     set parmeter to choose fitting routine... for awkward spectra
%     linear term removed from LorentzGauss fit - caused failures.
%     report fit error (100*stdev(resid)/gabaheight), rather than "SNR"
%     can estimate this from confidence interval for nlinfit - need
%               GABA and water estimates 
% 111209: Revert to water integral with linear baseline
%         Initialise NLINFIT based on MINLSQFIT
% 111212: Fix water integral error calc
%         include raw integral calculation for water.
%         loop over 100 fits of gaba params

GABAData=MRS_struct.gabaspec;
freq=MRS_struct.freq;
WaterData=MRS_struct.waterspec;
MRS_struct.versionfit = '111212';
disp(['GABA Fit Version is ' MRS_struct.versionfit ]);

numscans=size(GABAData); 
numscans=numscans(1);

 %110624
 %epsdirname = [ 'MRSfit_' datestr(clock,'yymmdd_HHMMSS') ];
 % 111209
 epsdirname = [ 'MRSfit_' datestr(clock,'yymmdd') ];

for ii=1:numscans
    MRS_struct.pfile{ii}
%%%%%%%%%%%% GABA fit (Gaussian) %%%%%%%%%%%%%%%
  % Originally (RE version)  gabadata was rescaled to the max across all spectra 
  % in the dataset.  Now I normalised the data with a const
  % ... work in progress
  % ...from GaussModel;
  % x(1) = gaussian amplitude
  % x(2) = 1/(2*sigma^2)
  % x(3) = centre freq of peak
  % x(4) = amplitude of linear baseline
  % x(5) = constant amplitude offset

  lowerbound=17342;
  %upperbound=17961;
  upperbound=18000;
  freqbounds=lowerbound:upperbound;
  plotbounds=(lowerbound-150):(upperbound+150);

  maxinGABA=max(real(GABAData(freqbounds)));
  %maxinGABA=1;
  resnorm=zeros([numscans size(freqbounds,2)]);
  %residuals=resnorm;
  size(resnorm);
  GaussModelInit = [10*maxinGABA -90 3.026 0 0];
  
  lb = [0 -200 2.9 -40*maxinGABA -2000*maxinGABA];
  ub = [4000*maxinGABA -40 3.15 40*maxinGABA 1000*maxinGABA];
  
  % 111209 Always run LSQ to initialise    
  options = optimset('lsqcurvefit');
  options = optimset(options,'Display','off','TolFun',1e-10,'Tolx',1e-10,'MaxIter',1e5);
  
  % pass function handle to GaussModel to lsqcurvefit
  [GaussModelParam(ii,:),resnorm(ii), residg] = lsqcurvefit(@(xdummy,ydummy) GaussModel(xdummy,ydummy), ...
      GaussModelInit, ...
      freq(freqbounds),...
      real(GABAData(ii,freqbounds)), ...
      lb,ub,options);
  residg = -residg;
  
  for fit_iter = 1:100 % 111212 - loop to ensure convergence, generally converged with in 10 iterations
      GaussModelInit = GaussModelParam(ii,:); %111209
      nlinopts = statset('nlinfit');
      nlinopts = statset(nlinopts, 'MaxIter', 1e5);
      
      [GaussModelParam(ii,:), residg] = nlinfit(freq(freqbounds), real(GABAData(ii,freqbounds)), ...
          @(xdummy,ydummy) GaussModel(xdummy,ydummy), ...
          GaussModelInit, ...
          nlinopts);
  end
  
  GABAheight = GaussModelParam(ii,1);
  % FitSTD reports the standard deviation of the residuals / gaba HEIGHT
  MRS_struct.GABAFitError(ii)  =  100 * std(residg) / GABAheight;
  % x(2) = 1/(2*sigma^2).  Convert from points to Hz

  % area under gaussian is a * (2 * pi * sigma^2)^(1/2), and
  % GaussModelParam(:,2) = 1 / (2 * sigma^2)
  % This sets GabaArea as the area under the curve.
  MRS_struct.gabaArea(ii)=GaussModelParam(ii,1)./sqrt(-GaussModelParam(ii,2))*sqrt(pi);
  
  sigma = ( 1 / (2 * (abs(GaussModelParam(ii,2)))) ).^(1/2); 
  MRS_struct.GABAFWHM(ii) =  abs( (2* 42.576*3) * sigma);
  MRS_struct.GABAModelFit(ii,:)=GaussModelParam(ii,:);
 
  if(ishandle(102))
    close(102)
  end
  figure(102)
  % GABA plot
  subplot(2, 2, 1)
  % find peak of GABA plot... plot residuals above this...
  gabamin = min(real(GABAData(ii,plotbounds)));
%  resid = -resid;   % set resid to data-fit rather than fit-data
  resmax = max(residg);  
  residg = residg + gabamin - resmax;
  plot(freq(freqbounds),GaussModel(GaussModelParam(ii,:),freq(freqbounds)),'r',...
       freq(plotbounds),real(GABAData(ii,plotbounds)), 'b', ...
       freq(freqbounds),residg,'b');
  legendtxt = regexprep(MRS_struct.pfile{ii}, '_','-');
  title(legendtxt);
  set(gca,'XDir','reverse');
  set(gca,'YTick',[], 'Xgrid', 'on');
  oldaxis = axis;
  axis( [2.6 3.6 oldaxis(3) oldaxis(4) ] )
  
  %     R2(ii)=1-(resnorm(ii,1)/norm(real(GABAData(freqbounds))-mean(real(GABAData(freqbounds))))^2);
  %     GaussModelParam(ii,1)./sqrt(-GaussModelParam(ii,2))*sqrt(pi);
  
  
  %%%%%%%%%%%%%% Water Fit %%%%%%%%%%%%%%%%%%
  %estimate height and baseline from data
  maxinWater=max(real(WaterData(:)));
  waterbase = mean(real(WaterData(1:500))); % avg
  
  % 111209 need to change order to get linear term back in 
  % x(1) = Amplitude of (scaled) Lorentzian
% x(2) = 1 / hwhm of Lorentzian (hwhm = half width at half max)
% x(3) = centre freq of Lorentzian
% x(4) = linear baseline amplitude
% x(5) = constant baseline amplitude
% x(6) =  -1 / 2 * sigma^2  of gaussian
    LGModelInit = [maxinWater 20 4.7 0 waterbase -50 ]; %works
  
  lblg = [0.01*maxinWater 1 4.6 0 0 -50 ];
  ublg = [40*maxinWater 100 4.8 0.000001 1 0 ];
  freqbounds=15700:17100;
  
  % Do the water fit (Lorentz-Gauss)
  % 111209 Always do the LSQCURV fitting - to initialise 
  %Lorentz-Gauss Starters
  options = optimset('lsqcurvefit');
  options = optimset(options,'Display','off','TolFun',1e-10,'Tolx',1e-10,'MaxIter',10000);
  
  % 110308 - change the plotting.  one plot per SCAN with GABA,
  % water
  fignum = 102;
  figure(fignum)
  [LGModelParam(ii,:),residual(ii), residw] = lsqcurvefit(@(xdummy,ydummy) ...
      LorentzGaussModel(xdummy,ydummy),...
      LGModelInit, freq(freqbounds),real(WaterData(ii,freqbounds)),...
      lblg,ublg,options);
  residw = -residw;
  LGModelInit = LGModelParam(ii,:); %111209 initialise from LSQCURV
  
  % nlinfit options
  nlinopts = statset('nlinfit');
  nlinopts = statset(nlinopts, 'MaxIter', 1e5);
  
  [LGModelParam(ii,:),residw] = nlinfit(freq(freqbounds), real(WaterData(ii,freqbounds)),...
      @(xdummy,ydummy)	LorentzGaussModel(xdummy,ydummy),...
      LGModelInit, nlinopts);
  
  LGModelInit = LGModelParam(ii,:); %111212 run twice
  [LGModelParam(ii,:),residw] = nlinfit(freq(freqbounds), real(WaterData(ii,freqbounds)),...
      @(xdummy,ydummy)	LorentzGaussModel(xdummy,ydummy),...
      LGModelInit, nlinopts);
  residw = -residw;
  
  MRS_struct.WaterModelParam(ii,:) = LGModelParam(ii,:);
 
  subplot(2, 2, 3)
  
  waterheight = LGModelParam(ii,1);
  watmin = min(real(WaterData(ii,:)));
  %  resid = -resid;   % set resid to data-fit rather than fit-data
  resmax = max(residw);
  residw = residw + watmin - resmax;
  %111212 - fix water error calc
  MRS_struct.WaterFitError(ii)  =  100 * std(residw) / waterheight;
  MRS_struct.GABAIU_Error = (MRS_struct.GABAFitError .^ 2 + ...
      MRS_struct.WaterFitError .^ 2 ) .^ 0.5;
  
  plot(freq(freqbounds),real(LorentzGaussModel(LGModelParam(ii,:),freq(freqbounds))), 'r', ...
      freq(freqbounds),real(WaterData(ii,freqbounds)),'b', ...
      freq(freqbounds), residw, 'b');
  set(gca,'XDir','reverse');
  set(gca,'YTick',[], 'Xgrid', 'on');
  xlim([4.2 5.2]);
  
  baselineparams = [ LGModelParam(ii,3) 0 LGModelParam(ii,4)];
  
  Baseline(ii,:)=BaselineModel(baselineparams,freq(freqbounds));
  WaterArea(ii)=sum(real(LorentzGaussModel(LGModelParam(ii,:),freq(freqbounds))) ...
      - BaselineModel(LGModelParam(ii,3:5),freq(freqbounds)),2);

  %111212 - estimate baseline and demean water, for raw integral calc 
  baseline_est = mean([ mean(real(WaterData(ii,1:501))) mean(real(WaterData(ii,32178:32678))) ]);
  WaterDemean = real(WaterData(ii,:)) - baseline_est;
  MRS_struct.waterAreaIntegration(ii) = sum(WaterDemean) .* (freq(1) - freq(2));
  
  % convert watersum to integral
  MRS_struct.waterArea(ii)=WaterArea(ii) * (freq(1) - freq(2));
  % 110308 - assume we get this from the loaded file
  %MRS_struct.Navg=Navg;
  MRS_struct.H20 = MRS_struct.waterArea(ii) ./ std(residw);
  
  %generate scaled spectrum (for plotting) CJE Jan2011
  MRS_struct.gabaspec_scaled(ii,:) = MRS_struct.gabaspec(ii,:) .* ...
      repmat((1 ./ MRS_struct.waterArea(ii)), [1 32768]);
  
  [MRS_struct]=MRSGABAinstunits(MRS_struct, ii);
  
  % GABA info
  subplot(2,2,2)
  axis off
  tmp =       [ 'pfile        : ' MRS_struct.pfile{ii} ];
  tmp = regexprep(tmp, '_','-');
  text(0,0.9, tmp, 'FontName', 'Courier');
  tmp =       [ 'Navg         : ' num2str(MRS_struct.Navg(ii)) ];
  text(0,0.8, tmp, 'FontName', 'Courier');
  tmp = sprintf('Fit Error    : %.2f%%', MRS_struct.GABAIU_Error(ii) );
  text(0,0.7, tmp, 'FontName', 'Courier');
  tmp = sprintf('GABA+ FWHM   : %.2f Hz', MRS_struct.GABAFWHM(ii) );
  text(0,0.6, tmp, 'FontName', 'Courier');
  tmp = sprintf('GABA+ Area   : %.4f', MRS_struct.gabaArea(ii) );
  text(0,0.5, tmp, 'FontName', 'Courier');
  tmp = sprintf('H_2O Area     : %.4f', MRS_struct.waterArea(ii) );
  text(0,0.4, tmp, 'FontName', 'Courier');
  tmp = sprintf('GABA+ / H_2O  : %.4f inst. units.', MRS_struct.gabaiu(ii) );
  text(0,0.3, tmp, 'FontName', 'Courier');
  if(MRS_struct.FreqPhaseAlign)
      tmp2 = 'Aligned';
  else
      tmp2 = 'Not aligned';
  end
  tmp =       [ 'Load Version : ' MRS_struct.versionload ', ' tmp2];
  text(0,0.1, tmp, 'FontName', 'Courier');
  tmp = [       'Fit Version  : ' MRS_struct.versionfit ];
  text(0,0.0, tmp, 'FontName', 'Courier');
  tmp = sprintf('%.2f, %.2f',  MRS_struct.phase(ii),  MRS_struct.phase_firstorder(ii) );
  tmp =        ['Phase  \phi_0,\phi_1 :' tmp];
  text(0, 0.2, tmp, 'FontName', 'Courier');
  
  %%%%  Save EPS %%%%%
  pfil_nopath = MRS_struct.pfile{ii};
  %pfil_nopath = pfil_nopath( (length(pfil_nopath)-15) : (length(pfil_nopath)-9) );
  tmp = strfind(pfil_nopath,'/');
  tmp2 = strfind(pfil_nopath,'\');
  if(tmp)
      lastslash=tmp(end);
  elseif (tmp2)
      %maybe it's Windows...
      lastslash=tmp2(end);
  else
      % it's in the current dir...
      lastslash=0;
  end
  tmp = strfind(pfil_nopath, '.7');
  dot7 = tmp(end); % just in case there's another .7 somewhere else...
  pfil_nopath = pfil_nopath( (lastslash+1) : (dot7-1) );
  
  
  %110624
  epsfname=[ epsdirname '/' pfil_nopath  '.eps' ];
  
   % create dir for output
  if(exist(epsdirname,'dir') ~= 7)
    mkdir(epsdirname) 
  end

  saveas(102, epsfname, 'psc2')
  
  
end

% end of MRSGABAfit

%%%%%%%%%%%%%%%%%%%%%%%% GAUSS MODEL %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function F = GaussModel(x,freq)

% x(1) = gaussian amplitude
% x(2) = 1/(2*sigma^2)
% x(3) = centre freq of peak
% x(4) = amplitude of linear baseline
% x(5) = constant amplitude offset

F = x(1)*exp(x(2)*(freq-x(3)).*(freq-x(3)))+x(4)*(freq-x(3))+x(5);



%%%%%%%%%%%%%%%%  OLD LORENTZGAUSSMODEL %%%%%%%%%%%%%%%%%%%%
%function F = LorentzGaussModel(x,freq)
%Lorentzian Model multiplied by a Gaussian.  gaussian width determined by
%x(6). x(7) determines phase.
%F = ((ones(size(freq))./(x(2)^2*(freq-x(3)).*(freq-x(3))+1)*x(1))*cos(x(7))+(ones(size(freq))./(x(2)^2*(freq-x(3)).*(freq-x(3))+1)*x(2).*(freq-x(3)))*sin(x(7))).*(exp(x(6)*(freq-x(3)).*(freq-x(3))))+x(4)*(freq-x(3))+x(5);


%%%%%%%%%%%%%%%%  NEW LORENTZGAUSSMODEL %%%%%%%%%%%%%%%%%%%%
function F = LorentzGaussModel(x,freq)
% CJE 24Nov10 - removed phase term from fit - this is now dealt with
% by the phasing of the water ref scans in MRSLoadPfiles
%Lorentzian Model multiplied by a Gaussian.  
  % 111209 need to change order to get linear term back in 
  % x(1) = Amplitude of (scaled) Lorentzian
% x(2) = 1 / hwhm of Lorentzian (hwhm = half width at half max)
% x(3) = centre freq of Lorentzian
% x(4) = linear baseline amplitude
% x(5) = constant baseline amplitude
% x(6) =  -1 / 2 * sigma^2  of gaussian

% Lorentzian  = (1/pi) * (hwhm) / (deltaf^2 + hwhm^2)
% Peak height of Lorentzian = 4 / (pi*hwhm)
% F is a normalised Lorentzian - height independent of hwhm
%   = Lorentzian / Peak

%F =((ones(size(freq))./(x(2)^2*(freq-x(3)).*(freq-x(3))+1)*x(1))*cos(x(7))+(ones(size(freq))./(x(2)^2*(freq-x(3)).*(freq-x(3))+1)*x(2).*(freq-x(3)))*sin(x(7))).*(exp(x(6)*(freq-x(3)).*(freq-x(3))))+x(4)*(freq-x(3))+x(5);
% remove phasing
% 111209 - linear term back in (cf 110624)
F = (x(1)*ones(size(freq))./(x(2)^2*(freq-x(3)).*(freq-x(3))+1))  ... 
    .* (exp(x(6)*(freq-x(3)).*(freq-x(3)))) ... % gaussian
    + x(4)*(freq-x(3)) ... % linear baseline
    +x(5); % constant baseline

    
%%%%%%%%%%%%%%% BASELINE %%%%%%%%%%%%%%%%%%%%%%%
function F = BaselineModel(x,freq)
F = x(2)*(freq-x(1))+x(3);


%%%%%%%%%%%%%%%%%%% INST UNITS CALC %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [MRS_struct] = MRSGABAinstunits(MRS_struct,ii)
% function [MRS_struct] = MRSGABAinstunits(MRS_struct)
% Convert GABA and Water amplitudes to institutional units
% (pseudo-concentration in mmol per litre).  
% March 10: use MRS_struct.

PureWaterConc = 55000; % mmol/litre
WaterVisibility = 0.65; % This is approx the value from Ernst, Kreis, Ross
EditingEfficiency = 0.5; 
T1_GABA = 0.80 ; % "empirically determined"...! Gives same values as RE's spreadsheet
% ... and consistent with Cr-CH2 T1 of 0.8 (Traber, 2004)

T2_GABA = 0.13; % from occipital Cr-CH2, Traber 2004
T1_Water = 1.100; % average of WM and GM, estimated from Wansapura 1999
T2_Water = 0.095; % average of WM and GM, estimated from Wansapura 1999
MM=0.45;  % MM correction: fraction of GABA in GABA+ peak. (In TrypDep, 30 subjects: 55% of GABA+ was MM)
TR=1.8;
TE=0.068;
N_H_GABA=2;
N_H_Water=2;
Nspectra = length(MRS_struct.pfile);
Nwateravg=8;

T1_factor = (1-exp(-TR./T1_Water)) ./ (1-exp(-TR./T1_GABA));
T2_factor = exp(-TE./T2_Water) ./ exp(-TE./T2_GABA);

MRS_struct.gabaiu(ii) = (MRS_struct.gabaArea(ii)  ./  MRS_struct.waterArea(ii))  ...
    * PureWaterConc*WaterVisibility*T1_factor*T2_factor*(N_H_Water./N_H_GABA) ...
    * MM * (Nwateravg ./ MRS_struct.Navg(ii)) ./ EditingEfficiency;








