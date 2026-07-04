% =========================================================================
% Extract satellite state data only from STK
% Output: satellite position and velocity in Fixed frame
% No ground station, no GS_SCENARIO, no visibility calculation
% =========================================================================

%% 0. Global settings
clear; clc;

USE_ENGINE = 1;          % 1 = STK Engine, 0 = STK GUI
time_step_val = 5;       % time step in seconds
USE_MULTI_LAYER = false;  % true = two layers, false = first layer only

StartTime = '27 Feb 2025 00:00:00.000';
StopTime  = '27 Feb 2025 01:00:00.000';

base_root = 'C:\Users\Tianl\Documents\PhD\OutputFiles';

if USE_MULTI_LAYER
    layer_suffix = 'MultiLayer';
else
    layer_suffix = 'SingleLayer';
end

run_root_folder = fullfile(base_root, sprintf('RawSatelliteData_%s', layer_suffix));
sub_folder_name = sprintf('Results_Step%ds', time_step_val);
output_folder = fullfile(run_root_folder, sub_folder_name);
step_folder = fullfile(output_folder, 'Satellite_State_ByStep');

if ~exist(output_folder, 'dir'), mkdir(output_folder); end
if ~exist(step_folder, 'dir'), mkdir(step_folder); end

fprintf('Output folder: %s\n', output_folder);

%% 1. Start STK
if USE_ENGINE
    try
        app = actxserver('STKX11.application'); 
        root = actxserver('AgStkObjects11.AgStkObjectRoot');
    catch ME
        error('Failed to start STK Engine. Error: %s', ME.message);
    end
else
    try
        app = actxserver('STK11.application');
        root = app.Personality2;
        app.Visible = true;
        app.UserControl = true;
    catch ME
        error('Failed to start STK GUI. Error: %s', ME.message);
    end
end

%% 2. Create scenario
fprintf('Creating scenario...\n');
try
    root.CloseScenario();
catch
    fprintf('No old scenario to close.\n');
end

scenario = root.Children.New('eScenario', 'MATLAB_Satellite_State_Extraction');
scenario.SetTimePeriod(StartTime, StopTime);
scenario.StartTime = StartTime;
scenario.StopTime = StopTime;

if ~USE_ENGINE
    try
        root.ExecuteCommand('Animate * Reset');
    catch ME
        fprintf('Animate reset failed: %s\n', ME.message);
    end
end

%% 3. Create constellation
% Layer 1 parameters
P = 80;
N = 76;
F = 11;
altitude1_km = 550;
inclination1_deg = 53;

% Layer 2 parameters
P2 = 72;
N2 = 96;
F2 = 15;
altitude2_km = 1145;
inclination2_deg = 75;

isTestMode = false;
if isTestMode
    P = 5; N = 22;
    P2 = 2; N2 = 10;
    fprintf('Test mode enabled.\n');
end

TotalSats = P * N;
TotalSats2 = P2 * N2;

satObj = module.sat();

fprintf('Creating layer 1: %d planes, %d sats per plane...\n', P, N);
for i = 1:P
    seedName = sprintf('STARLINK_Seed_Plane%d', i);

    params = struct();
    params.satelliteName = seedName;
    params.perigeeAlt = altitude1_km;
    params.apogeeAlt = altitude1_km;
    params.inclination = inclination1_deg;
    params.argOfPerigee = 0;
    params.RAAN = (i - 1) * 360 / P;
    phaseOffset = (i - 1) * 360 * F / TotalSats;
    params.Anomaly = mod(phaseOffset, 360);

    satObj.createSatellite(root, scenario, params);

    if ~USE_ENGINE
        try
            root.ExecuteCommand(sprintf('Graphics */Satellite/%s Label Show Off', seedName));
        catch
        end
    end

    params_const = struct();
    params_const.seedSatelliteName = seedName;
    params_const.numPlanes = 1;
    params_const.numSatsPerPlane = N;
    params_const.interPlanePhaseIncrement = 0;

    satObj.createWalkerConstellation_Delta(root, params_const);

    try
        root.ExecuteCommand(sprintf('Unload / */Satellite/%s', seedName));
    catch
        fprintf('Warning: failed to unload seed satellite %s\n', seedName);
    end

    if mod(i, 5) == 0
        fprintf('Layer 1 planes finished: %d/%d\n', i, P);
    end
end

if USE_MULTI_LAYER
    fprintf('Creating layer 2: %d planes, %d sats per plane...\n', P2, N2);
    for i = 1:P2
        seedName2 = sprintf('WALKER1000_Seed_Plane%d', i);

        params2 = struct();
        params2.satelliteName = seedName2;
        params2.perigeeAlt = altitude2_km;
        params2.apogeeAlt = altitude2_km;
        params2.inclination = inclination2_deg;
        params2.argOfPerigee = 0;
        params2.RAAN = (i - 1) * 360 / P2;
        phaseOffset2 = (i - 1) * 360 * F2 / TotalSats2;
        params2.Anomaly = mod(phaseOffset2, 360);

        satObj.createSatellite(root, scenario, params2);

        if ~USE_ENGINE
            try
                root.ExecuteCommand(sprintf('Graphics */Satellite/%s Label Show Off', seedName2));
            catch
            end
        end

        params_const2 = struct();
        params_const2.seedSatelliteName = seedName2;
        params_const2.numPlanes = 1;
        params_const2.numSatsPerPlane = N2;
        params_const2.interPlanePhaseIncrement = 0;

        satObj.createWalkerConstellation_Delta(root, params_const2);

        try
            root.ExecuteCommand(sprintf('Unload / */Satellite/%s', seedName2));
        catch
            fprintf('Warning: failed to unload seed satellite %s\n', seedName2);
        end

        if mod(i, 5) == 0
            fprintf('Layer 2 planes finished: %d/%d\n', i, P2);
        end
    end
end

%% 4. Rename and collect satellite names
fprintf('Collecting satellite list...\n');
sat = module.sat();
sat.batchRenameSatellitesInSTK2(root, sat.getSatelliteNames(scenario));
satellite_names = sat.getSatelliteNames(scenario);
numSats = length(satellite_names);

if ~USE_ENGINE
    try
        root.ExecuteCommand('Graphics * Label Show Off');
    catch
    end
end

fprintf('Scenario ready. Total satellites: %d\n', numSats);

%% 5. Extract satellite position and velocity
fprintf('Extracting satellite position and velocity...\n');

SatPosAll = cell(numSats, 1);
SatVelAll = cell(numSats, 1);
GlobalTimeStrs = strings(0, 1);
satellite_paths = strcat("Satellite/", string(satellite_names(:)));

for i = 1:numSats
    satName = satellite_names{i};
    try
        obj = root.GetObjectFromPath(char(satellite_paths(i)));

        [sat_pos, time_vals] = extractFixedVectorSeries(obj, 'Position', StartTime, StopTime, time_step_val, true);
        sat_vel = extractFixedVectorSeries(obj, 'Velocity', StartTime, StopTime, time_step_val, false);

        SatPosAll{i} = sat_pos;
        SatVelAll{i} = sat_vel;

        if isempty(GlobalTimeStrs)
            GlobalTimeStrs = string(time_vals(:));
        end
    catch ME
        SatPosAll{i} = [];
        SatVelAll{i} = [];
        fprintf('Warning: failed to extract %s. Error: %s\n', satName, ME.message);
    end

    if mod(i, 200) == 0 || i == numSats
        fprintf('Satellites extracted: %d/%d\n', i, numSats);
    end
end

numTimeSteps = length(GlobalTimeStrs);
fprintf('Extraction finished. Time steps: %d\n', numTimeSteps);

%% 6. Save MAT and index CSV files
mat_file = fullfile(output_folder, 'SatelliteStates.mat');
save(mat_file, 'SatPosAll', 'SatVelAll', 'GlobalTimeStrs', 'satellite_names', ...
    'StartTime', 'StopTime', 'time_step_val', 'USE_MULTI_LAYER', '-v7.3');
fprintf('Saved MAT file: %s\n', mat_file);

sat_index = table((1:numSats)', string(satellite_names(:)), ...
    'VariableNames', {'SatIndex', 'SatName'});
writetable(sat_index, fullfile(output_folder, 'Satellite_NameIndex.csv'));

time_index = table((1:numTimeSteps)', GlobalTimeStrs(:), ...
    'VariableNames', {'TimeStep', 'Time'});
writetable(time_index, fullfile(output_folder, 'Satellite_TimeIndex.csv'));

%% 7. Save one CSV per time step
fprintf('Writing per-step CSV files...\n');

for t_idx = 1:numTimeSteps
    current_time_str = GlobalTimeStrs(t_idx);
    safe_time_str = regexprep(char(current_time_str), '[:. ]', '_');

    SatName_col = strings(numSats, 1);
    X_col = nan(numSats, 1);
    Y_col = nan(numSats, 1);
    Z_col = nan(numSats, 1);
    Vx_col = nan(numSats, 1);
    Vy_col = nan(numSats, 1);
    Vz_col = nan(numSats, 1);
    Valid_col = false(numSats, 1);

    for i = 1:numSats
        SatName_col(i) = string(satellite_names{i});
        if ~isempty(SatPosAll{i}) && ~isempty(SatVelAll{i}) && ...
                size(SatPosAll{i}, 1) >= t_idx && size(SatVelAll{i}, 1) >= t_idx
            X_col(i) = SatPosAll{i}(t_idx, 1);
            Y_col(i) = SatPosAll{i}(t_idx, 2);
            Z_col(i) = SatPosAll{i}(t_idx, 3);
            Vx_col(i) = SatVelAll{i}(t_idx, 1);
            Vy_col(i) = SatVelAll{i}(t_idx, 2);
            Vz_col(i) = SatVelAll{i}(t_idx, 3);
            Valid_col(i) = true;
        end
    end

    TimeStep_col = repmat(t_idx, numSats, 1);
    Time_col = repmat(current_time_str, numSats, 1);

    T = table(TimeStep_col, Time_col, SatName_col, ...
        X_col, Y_col, Z_col, Vx_col, Vy_col, Vz_col, Valid_col, ...
        'VariableNames', {'TimeStep', 'Time', 'SatName', ...
        'X_km', 'Y_km', 'Z_km', 'Vx_km_s', 'Vy_km_s', 'Vz_km_s', 'Valid'});

    file_name = sprintf('satellite_state_step%04d_%s.csv', t_idx, safe_time_str);
    writetable(T, fullfile(step_folder, file_name));

    if mod(t_idx, 20) == 0 || t_idx == numTimeSteps
        fprintf('CSV steps written: %d/%d\n', t_idx, numTimeSteps);
    end
end

fprintf('All satellite state data saved.\n');
fprintf('Final output folder: %s\n', output_folder);


% ========================================================================
% Local functions
% ========================================================================

function [vectorData, timeVals] = extractFixedVectorSeries(obj, vectorName, startTime, stopTime, timeStep, returnTime)
% Extract Position or Velocity vector series from STK Vectors(Fixed) provider.

if nargin < 6
    returnTime = false;
end

provider = obj.DataProviders.Item('Vectors(Fixed)').Group.Item(vectorName);
result = provider.Exec(startTime, stopTime, timeStep);

x = cell2mat(result.DataSets.GetDataSetByName('x').GetValues);
y = cell2mat(result.DataSets.GetDataSetByName('y').GetValues);
z = cell2mat(result.DataSets.GetDataSetByName('z').GetValues);

vectorData = [x, y, z];

if returnTime
    timeVals = result.DataSets.GetDataSetByName('Time').GetValues;
else
    timeVals = {};
end
end
