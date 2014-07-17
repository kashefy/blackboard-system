function [locErrors, sourceAngles] = test_blackboard

plotting = 1;

%% Add relevant paths
%
addpath('..');
add_WP_paths;
import simulator.*
import xml.*

%% Testing parameters
%
% Define angular resolution
angularResolution = 5;

% All possible azimuth angles
angles = 0:angularResolution:(360-angularResolution);

% Azimuth of speech source for testing
sourceAngles = [300 330 0 30 60];


%% Initialise simulation
%
% Distance of speech source (related to the HRTF catalog)
distSource = 3;

% Sampling frequency
fsHz = 44.1E3;

% SourceBuffer with file
sourceBuffer = buffer.FIFO();

% Speech source
speech = AudioSource(...          % define AudioSource with ...
    AudioSourceType.POINT, ...    % Point Source Type
    sourceBuffer);                % Buffer as signal source

% Sinks/Head
head = AudioSink(2);
head.set('Position',  [0; 0; 1.75]);  
head.set('UnitFront', [1; 0; 0]); % head is looking to positive x

% HRIRs
hrir = DirectionalIR(xml.dbGetFile('impulse_responses/qu_kemar_anechoic/QU_KEMAR_anechoic_3m.wav'));  

% Simulator
sim = SimulatorConvexRoom();  % simulator object

sim.set(...
    'SampleRate', fsHz, ...         % sampling frequency
    'BlockSize', 2^12, ...          % blocksize
    'NumberOfThreads', 1, ...       % number of threads
    'MaximumDelay', 0.0, ...        % maximum distance delay in seconds
    'Renderer', @ssr_binaural, ...  % SSR rendering function (do not change this!)
    'HRIRDataset', hrir, ...        % assign HRIR-Object to Simulator
    'Sources', speech, ...          % assign sources to Simulator
    'Sinks', head);                 % assign sinks to Simulator

sim.set('Init',true);
% sim.draw();

%% Initialise all WP2 related parameters
%
% Framing parameters
blockSec = 20E-3;
stepSec  = 10E-3;

% Gammatone parameters
f_low       = 80;
f_high      = 8000;
nChannels   = 32;
dimFeatures = nChannels*2; % ITD + ILD
rm_decaySec = 0;

% Request cues being extracted
WP2_requests = {'ild' 'itd_xcorr' 'ic_xcorr', 'ratemap_power'};

% Frequency range and number of channels
WP2_param = genParStruct('f_low',f_low,'f_high',f_high,...
                         'nChannels',nChannels,...
                         'rm_decaySec',rm_decaySec,...
                         'ild_wSizeSec',blockSec,...
                         'ild_hSizeSec',stepSec,'rm_wSizeSec',blockSec,...
                         'rm_hSizeSec',stepSec,'cc_wSizeSec',blockSec,...
                         'cc_hSizeSec',stepSec);                 

% Create an empty data object. It will be filled up as new ear signal
% chunks are "acquired". 
dObj = dataObject([], sim.SampleRate, 1);  % Last input (1) indicates a stereo signal
mObj = manager(dObj, WP2_requests, WP2_param);   % Instantiate a manager

   
%% Read test file lists
rootGRID = fullfile(xml.dbPath, 'sound_databases/grid_subset'); 
flist = fullfile(rootGRID, 'testset.flist');
fid = fopen(flist);
C = textscan(fid, '%s');
fclose(fid);
testFiles = C{1};
clear C;

%% Start the blackboard
%
% Name of the graphical model
gmName = 'scenario1';

nFiles = 1; %length(testFiles);
nAngles = length(sourceAngles);
locErrors = zeros(nAngles, nFiles);
for n=1:nAngles
    srcAngle = sourceAngles(n);
    srcPosition = distSource * [cosd(srcAngle); sind(srcAngle); 0];
        
    for f=1:nFiles

        fprintf('\n---- Localising target source at %d degrees: file %d (%s)\n', srcAngle, f, testFiles{f});
        
        % Set source azimuth
        speech.set('Position', srcPosition);
        
        % Use 'ReInit' before setting the new speech file
        sim.set('ReInit',true);
        
        % Read f-th GRID sentence
        [x,fsHz_x] = audioread(fullfile(rootGRID, testFiles{f}));
        
        % Upsample speech if required
        if fsHz_x ~= fsHz
            x = resample(x, fsHz, fsHz_x);
        end
        x = x ./ max(x(:));
        
        % Fill speech buffer
        sourceBuffer.setData(x);
        
        %% Initialize blackboard, KSs and the blackboard monitor

        % Create blackboard instance
        bb = Blackboard();

        % Initialise Knowledge Sources
        ksSignalBlock = SignalBlockKS(bb, sim);
        bb.addKS(ksSignalBlock);
        
        ksPeriphery = PeripheryKS(bb, mObj, dObj);
        bb.addKS(ksPeriphery);
        
        ksAcousticCues = AcousticCuesKS(bb, dObj);
        bb.addKS(ksAcousticCues);
        
        ksLoc = LocationKS(bb, gmName, dimFeatures, angles);
        bb.addKS(ksLoc);
        
        ksConf = ConfusionKS(bb);
        bb.addKS(ksConf);
        
        ksConfSolver = ConfusionSolvingKS(bb);
        bb.addKS(ksConfSolver);
        
        ksRotate = RotationKS(bb, sim);
        bb.addKS(ksRotate);

        % Register events with a list of KSs that should be triggered
        bm = BlackboardMonitor(bb);
        bm.registerEvent('ReadyForNextBlock', ksSignalBlock);
        bm.registerEvent('NewSignalBlock', ksPeriphery);
        bm.registerEvent('NewPeripherySignal', ksAcousticCues);
        bm.registerEvent('NewAcousticCues', ksLoc);
        bm.registerEvent('NewLocationHypothesis', ksConf, ksConfSolver);
        bm.registerEvent('NewConfusionHypothesis', ksRotate);

        if plotting
            %% Add event listeners for plotting
            addlistener(bb, 'NewSignalBlock', @plotSignalBlocks);
            addlistener(bb, 'NewPeripherySignal', @plotPeripherySignal);
            addlistener(bb, 'NewAcousticCues', @plotAcousticCues);
            addlistener(bb, 'NewLocationHypothesis', @plotLocationHypothesis);
            addlistener(bb, 'NewPerceivedLocation', @plotPerceivedLocation);
            figure(1)
            movegui('northwest');
        end

        %% Start the scheduler
        bb.setReadyForNextBlock(true);
        scheduler = Scheduler(bm);
        ok = scheduler.iterate;
        while ok
            ok = scheduler.iterate;
        end

        clc;
        if plotting
            fprintf('\n---------------------------------------------------------------------------\n');
            fprintf('Reference target angle: %d degrees\n', srcAngle);
            fprintf('---------------------------------------------------------------------------\n');
            fprintf('Localised source angle:\n');
            fprintf('---------------------------------------------------------------------------\n');
            fprintf('Block\tLocation   (head orientation    relative location)\tProbability\n');
            fprintf('---------------------------------------------------------------------------\n');
        end
        
        estAngles = zeros(bb.getNumPerceivedLocations, 1);

        for m=1:bb.getNumPerceivedLocations
            if plotting
                fprintf('%d\t%d degrees\t(%d degrees\t%d degrees)\t\t%.2f\n', ...
                    bb.perceivedLocations(m).blockNo, ...
                    bb.perceivedLocations(m).location + bb.perceivedLocations(m).headOrientation, ...
                    bb.perceivedLocations(m).headOrientation, ...
                    bb.perceivedLocations(m).location, ...
                    bb.perceivedLocations(m).score);
            end
            estAngles(m) = bb.perceivedLocations(m).location + ...
                bb.perceivedLocations(m).headOrientation;
        end
        if plotting
            fprintf('---------------------------------------------------------------------------\n');
        end
        locErrors(n,f) = mean(calc_localisation_errors(srcAngle, estAngles));
    end
end


%% clean up
sim.set('ShutDown',true);


%% Plotting functions
function plotSignalBlocks(bb, evnt)
sigBlock = bb.signalBlocks{evnt.data};
subplot(4, 4, [15, 16])
plot(sigBlock.signals(:,1));
axis tight; ylim([-1 1]);
xlabel('k');
title(sprintf('Block %d, head orientation: %d deg, left ear waveform', sigBlock.blockNo, sigBlock.headOrientation), 'FontSize', 12);

subplot(4, 4, [13, 14])
plot(sigBlock.signals(:,2));
axis tight; ylim([-1 1]);
xlabel('k');
title(sprintf('Block %d, head orientation: %d deg, right ear waveform', sigBlock.blockNo, sigBlock.headOrientation), 'FontSize', 12);


function plotPeripherySignal(bb, evnt)
sigBlock = bb.signalBlocks{evnt.data};
perSignal = bb.peripherySignals{evnt.data}.signals;

subplot(4, 4, [11, 12])
imagesc(perSignal{1}');
set(gca,'YDir','normal');
ylabel('GFB Channels');
xlabel('k');
title(sprintf('Block %d, head orientation: %d deg, left ear IHC', sigBlock.blockNo, sigBlock.headOrientation), 'FontSize', 12);

subplot(4, 4, [9, 10])
imagesc(perSignal{2}');
set(gca,'YDir','normal');
ylabel('GFB Channels');
xlabel('k');      
title(sprintf('Block %d, head orientation: %d deg, right ear IHC', sigBlock.blockNo, sigBlock.headOrientation), 'FontSize', 12);


function plotAcousticCues(bb, evnt)
acousticCue = bb.acousticCues{evnt.data};
subplot(4, 4, 5)
imagesc(acousticCue.itds);
set(gca,'YDir','normal');
ylabel('GFB Channels');
xlabel('Frame index');
caxis([-1 1]);
title(sprintf('Block %d, head orientation: %d deg, ITD', acousticCue.blockNo, acousticCue.headOrientation), 'FontSize', 12);

subplot(4, 4, 6)
imagesc(acousticCue.ilds);
set(gca,'YDir','normal');
ylabel('GFB Channels');
xlabel('Frame index');   
caxis([-10 10]);
title(sprintf('Block %d, head orientation: %d deg, ILD', acousticCue.blockNo, acousticCue.headOrientation), 'FontSize', 12);

subplot(4, 4, 7)
imagesc(acousticCue.ic);
set(gca,'YDir','normal');
ylabel('GFB Channels');
xlabel('Frame index');   
caxis([0 1]);
title(sprintf('Block %d, head orientation: %d deg, IC', acousticCue.blockNo, acousticCue.headOrientation), 'FontSize', 12);

subplot(4, 4, 8)
imagesc(acousticCue.ratemap);
set(gca,'YDir','normal');
ylabel('GFB Channels');
xlabel('Frame index');   
title(sprintf('Block %d, head orientation: %d deg, RATEMAP', acousticCue.blockNo, acousticCue.headOrientation), 'FontSize', 12);
drawnow


function plotLocationHypothesis(bb, evnt)
subplot(4, 4, [1, 2])
locHyp = bb.locationHypotheses(evnt.data);
bar(locHyp.locations, locHyp.posteriors);
xlabel('Azimuth (degrees)', 'FontSize', 12);
ylabel('Probability', 'FontSize', 12);
axis([0 361 0 1]);
title(sprintf('Block %d, head orientation: %d deg, distribution', locHyp.blockNo, locHyp.headOrientation), 'FontSize', 12);
%colormap(summer);


function plotPerceivedLocation(bb, evnt)
subplot(4, 4, [3, 4])
pLoc = bb.perceivedLocations(evnt.data(1));
bar(pLoc.location, pLoc.score);
xlabel('Azimuth (degrees)', 'FontSize', 12);
ylabel('Probability', 'FontSize', 12);
axis([0 361 0 1]);
title(sprintf('Block %d, head orientation: %d deg, perceived location', pLoc.blockNo, pLoc.headOrientation), 'FontSize', 12);