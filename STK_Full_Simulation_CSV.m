function STK_Full_Simulation_CSV(cfg)
% =========================================================================
% CSV-driven version of STK_Full_Simulation
%
% This function does not use STK COM.
% It expects satellite state data to be exported to CSV first, then reads:
%   Time, SatelliteName, X, Y, Z, VX, VY, VZ
%
% Supported input modes:
%   1. One combined CSV file with all satellites
%   2. A folder that contains one CSV per satellite
%
% Supported column aliases include examples such as:
%   Time / Time_UTC / Epoch
%   Satellite_Name / Satellite / SatName / ObjectName
%   X / X_km / PositionX / ECEF_X
%   VX / VX_km_s / VelocityX / ECEF_VX
%
% Outputs:
%   - Visibility_Datas/*.csv
%   - Visibility_LimitXXXXkm/*.csv
% Each visibility CSV contains:
%   Sat1, Sat2, Distance_km, AngularVelocity_rad_s, RelativeSpeed_km_s
% Usage:
%   STK_Full_Simulation_CSV
%   STK_Full_Simulation_CSV(struct('STATE_SOURCE', "C:\path\sat_states.csv"))
% =========================================================================

%% 0. Global settings
if nargin < 1 || isempty(cfg)
    cfg = struct();
end

clc;

% 这里的输入是已经导出的状态 CSV，因此整个函数不再依赖 STK COM。
distance_limit = getConfigValue(cfg, 'distance_limit', 1000);
time_step_val = getConfigValue(cfg, 'time_step_val', []);
distance_limit_batch = getConfigValue(cfg, 'distance_limit_batch', 1000:500:4000);

STATE_SOURCE = getConfigValue(cfg, 'STATE_SOURCE', ...
    "C:\Users\Tianl\Documents\PhD\Papers\second_paper\Algorith\stk-matlab\ExportedStates");
STATE_SOURCE_MODE = getConfigValue(cfg, 'STATE_SOURCE_MODE', "auto"); % auto | file | folder

GS_SCENARIO = getConfigValue(cfg, 'GS_SCENARIO', 'BBS');      % BBS or NLS
USE_MULTI_LAYER = getConfigValue(cfg, 'USE_MULTI_LAYER', true);
ENABLE_PARALLEL = getConfigValue(cfg, 'ENABLE_PARALLEL', true);

base_root = getConfigValue(cfg, 'base_root', ...
    'C:\Users\Tianl\Documents\PhD\Papers\second_paper\Algorith\OutputFiles\test');

%% 1. Ground-station scenario config
if strcmp(GS_SCENARIO, 'BBS')
    gs_suffix = 'BBS';
    GS_Defs = struct('Name', {'Beijing_Source', 'Brasilia_Target'}, ...
                     'Lat', {39.9042, -15.7975}, ...
                     'Lon', {116.4074, -47.8919});
else
    gs_suffix = 'NLS';
    GS_Defs = struct('Name', {'NewYork', 'London'}, ...
                     'Lat', {40.7128, 51.5074}, ...
                     'Lon', {-74.0060, -0.1278});
end

if USE_MULTI_LAYER
    layer_suffix = 'MultiLayer';
else
    layer_suffix = 'SingleLayer';
end

run_output_suffix = sprintf('%s_%s', gs_suffix, layer_suffix);

%% 2. Load satellite states from CSV
fprintf('[Stage 0] Loading satellite states from CSV source...\n');
[SatPositions, SatVelocities, satellite_names, GlobalTimeStrs, time_step_val] = ...
    loadSatelliteStatesFromCsv(STATE_SOURCE, STATE_SOURCE_MODE, time_step_val);

numSats = numel(satellite_names);
numTimeSteps = numel(GlobalTimeStrs);
numGS = numel(GS_Defs);

fprintf('  Loaded %d satellites and %d time steps.\n', numSats, numTimeSteps);
fprintf('  Time step used for naming/output: %.3f s\n', time_step_val);

GS_Positions = buildGroundStationSeries(GS_Defs, numTimeSteps);
allNodeNames = [string(satellite_names(:)); string({GS_Defs.Name})'];

% 这里预先构建所有节点对，后面每个时间步只需要复用这份配对索引。
%% 3. Output folder setup
run_root_folder = fullfile(base_root, sprintf('RawDataCSV_%s', run_output_suffix));
ensureFolderExists(run_root_folder);

sub_folder_name = makeOutputSubfolderName(time_step_val, distance_limit);
output_folder = fullfile(run_root_folder, sub_folder_name);
ensureFolderExists(output_folder);

vis_folder = fullfile(output_folder, 'Visibility_Datas');
ensureFolderExists(vis_folder);

%% 4. Prepare pair indices and optional parallel pool
totalNodes = numSats + numGS;
pairIndices = nchoosek(1:totalNodes, 2);
Re = 6378.137;
useParallel = ENABLE_PARALLEL && tryStartParallelPool();

fprintf('[Stage 1] Exporting visibility snapshots for %d km...\n', distance_limit);
total_timer = tic;
exportVisibilitySeries(vis_folder, distance_limit, GlobalTimeStrs, ...
    SatPositions, SatVelocities, GS_Positions, allNodeNames, pairIndices, Re, useParallel);
fprintf('  Primary export finished in %.2f s.\n', toc(total_timer));

%% 5. Batch export for multiple distance limits
fprintf('[Stage 2] Batch export for limits: %s\n', mat2str(distance_limit_batch));

for limitValue = distance_limit_batch
    vis_folder_limit = fullfile(output_folder, sprintf('Visibility_Limit%dkm', limitValue));
    ensureFolderExists(vis_folder_limit);

    fprintf('  Running limit = %d km...\n', limitValue);
    limit_timer = tic;
    exportVisibilitySeries(vis_folder_limit, limitValue, GlobalTimeStrs, ...
        SatPositions, SatVelocities, GS_Positions, allNodeNames, pairIndices, Re, useParallel);
    fprintf('  Limit %d km finished in %.2f s.\n', limitValue, toc(limit_timer));
end

fprintf('\nAll CSV-driven processing finished.\n');
fprintf('Results saved to: %s\n', output_folder);
fprintf('No STK COM objects were created in this function.\n');
end

function [SatPositions, SatVelocities, satelliteNames, timeKeys, timeStepSeconds] = ...
    loadSatelliteStatesFromCsv(stateSource, stateSourceMode, timeStepHint)

% 支持两种输入：
% 1. 一个汇总状态 CSV
% 2. 一个包含多颗卫星 CSV 的文件夹
stateSource = string(stateSource);
stateSourceMode = lower(string(stateSourceMode));

if stateSourceMode == "auto"
    if isfolder(stateSource)
        stateSourceMode = "folder";
    elseif isfile(stateSource)
        stateSourceMode = "file";
    else
        error(['STATE_SOURCE does not exist: %s\n', ...
               'Please set cfg.STATE_SOURCE to:\n', ...
               '  1. a combined state CSV file, or\n', ...
               '  2. a folder containing one CSV per satellite.\n', ...
               'Expected columns include: Time, Satellite_Name, X, Y, Z, VX, VY, VZ'], stateSource);
    end
end

switch stateSourceMode
    case "file"
        rawTable = canonicalizeStateTable(readStateCsvFile(stateSource), "");
    case "folder"
        csvFiles = dir(fullfile(stateSource, '*.csv'));
        if isempty(csvFiles)
            error('No CSV files found under folder: %s', stateSource);
        end

        tableList = cell(numel(csvFiles), 1);
        for i = 1:numel(csvFiles)
            filePath = fullfile(csvFiles(i).folder, csvFiles(i).name);
            fallbackSatName = erase(string(csvFiles(i).name), ".csv");
            tableList{i} = canonicalizeStateTable(readStateCsvFile(filePath), fallbackSatName);
        end
        rawTable = vertcat(tableList{:});
    otherwise
        error('Unsupported STATE_SOURCE_MODE: %s', stateSourceMode);
end

satelliteNames = unique(rawTable.SatelliteName, 'stable');
timeKeys = unique(rawTable.TimeKey, 'stable');

numSats = numel(satelliteNames);
numTimeSteps = numel(timeKeys);

if numSats == 0 || numTimeSteps == 0
    error('The input CSV does not contain any satellite/time records.');
end

satIdx = indexIntoStableUnique(rawTable.SatelliteName, satelliteNames);
timeIdx = indexIntoStableUnique(rawTable.TimeKey, timeKeys);
linearIdx = sub2ind([numSats, numTimeSteps], satIdx, timeIdx);

if numel(unique(linearIdx)) ~= numel(linearIdx)
    error(['Duplicate satellite/time rows detected in CSV input. ', ...
           'Please ensure each satellite has at most one row per time step.']);
end

X = nan(numSats, numTimeSteps);
Y = nan(numSats, numTimeSteps);
Z = nan(numSats, numTimeSteps);
VX = nan(numSats, numTimeSteps);
VY = nan(numSats, numTimeSteps);
VZ = nan(numSats, numTimeSteps);

X(linearIdx) = rawTable.X;
Y(linearIdx) = rawTable.Y;
Z(linearIdx) = rawTable.Z;
VX(linearIdx) = rawTable.VX;
VY(linearIdx) = rawTable.VY;
VZ(linearIdx) = rawTable.VZ;

SatPositions = cat(3, X, Y, Z);
SatVelocities = cat(3, VX, VY, VZ);

timeStepSeconds = timeStepHint;
if isempty(timeStepSeconds)
    timeStepSeconds = inferTimeStepSeconds(timeKeys);
end
if ~isfinite(timeStepSeconds) || timeStepSeconds <= 0
    timeStepSeconds = 0;
end
end

function T = readStateCsvFile(filePath)
filePath = char(filePath);
if ~isfile(filePath)
    error('CSV file not found: %s', filePath);
end

try
    T = readtable(filePath, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    return;
catch
end

try
    T = readtable(filePath, 'TextType', 'string', 'PreserveVariableNames', true);
    return;
catch
end

try
    T = readtable(filePath, 'PreserveVariableNames', true);
    T = normalizeCompatTableTextColumns(T);
    return;
catch
end

T = readtable(filePath);
T = normalizeCompatTableTextColumns(T);

if isempty(T)
    error('CSV file is empty: %s', filePath);
end
end

function T = normalizeCompatTableTextColumns(T)
for i = 1:width(T)
    varName = T.Properties.VariableNames{i};
    oneColumn = T.(varName);

    if isstring(oneColumn) || iscellstr(oneColumn) || ischar(oneColumn) || iscategorical(oneColumn)
        T.(varName) = string(oneColumn);
    end
end
end

function Tcanon = canonicalizeStateTable(T, fallbackSatName)
varNames = string(T.Properties.VariableNames);

idxTime = findColumnIndex(varNames, {'time', 'timeutc', 'timeutcg', 'timegregutc', 'timegregorianutc', 'utctime', 'utcg', 'epoch', 'epochutc', 'timestamp'});
idxSat = findColumnIndex(varNames, {'satellitename', 'satellite', 'satname', 'objectname', 'object', 'name'});
idxX = findColumnIndex(varNames, {'x', 'xkm', 'positionx', 'posx', 'ecefx', 'fixedx'});
idxY = findColumnIndex(varNames, {'y', 'ykm', 'positiony', 'posy', 'ecefy', 'fixedy'});
idxZ = findColumnIndex(varNames, {'z', 'zkm', 'positionz', 'posz', 'ecefz', 'fixedz'});
idxVX = findColumnIndex(varNames, {'vx', 'vxkms', 'velocityx', 'velx', 'xdot', 'xdotkms', 'ecefvx', 'fixedvx'});
idxVY = findColumnIndex(varNames, {'vy', 'vykms', 'velocityy', 'vely', 'ydot', 'ydotkms', 'ecefvy', 'fixedvy'});
idxVZ = findColumnIndex(varNames, {'vz', 'vzkms', 'velocityz', 'velz', 'zdot', 'zdotkms', 'ecefvz', 'fixedvz'});

requiredIdx = [idxTime, idxX, idxY, idxZ, idxVX, idxVY, idxVZ];
if any(isnan(requiredIdx))
    error(['Unable to find the required state columns in CSV. ', ...
           'Expected Time, X, Y, Z, VX, VY, VZ and optionally SatelliteName.']);
end

timeKey = strtrim(string(T{:, idxTime}));
if isnan(idxSat)
    if strlength(string(fallbackSatName)) == 0
        error('Satellite name column is missing and filename fallback is empty.');
    end
    satelliteName = repmat(string(fallbackSatName), height(T), 1);
else
    satelliteName = strtrim(string(T{:, idxSat}));
end

Tcanon = table( ...
    timeKey, ...
    satelliteName, ...
    toNumericColumn(T{:, idxX}), ...
    toNumericColumn(T{:, idxY}), ...
    toNumericColumn(T{:, idxZ}), ...
    toNumericColumn(T{:, idxVX}), ...
    toNumericColumn(T{:, idxVY}), ...
    toNumericColumn(T{:, idxVZ}), ...
    'VariableNames', {'TimeKey', 'SatelliteName', 'X', 'Y', 'Z', 'VX', 'VY', 'VZ'});
end

function idx = findColumnIndex(varNames, candidateTokens)
normalizedNames = strings(size(varNames));
for i = 1:numel(varNames)
    normalizedNames(i) = normalizeToken(varNames(i));
end
candidateTokens = string(candidateTokens);

idx = NaN;
for k = 1:numel(candidateTokens)
    matchIdx = find(normalizedNames == normalizeToken(candidateTokens(k)), 1);
    if ~isempty(matchIdx)
        idx = matchIdx;
        return;
    end
end
end

function token = normalizeToken(value)
token = regexprep(lower(string(value)), '[^a-z0-9]', '');
end

function numericValues = toNumericColumn(rawValues)
if isnumeric(rawValues)
    numericValues = double(rawValues);
elseif islogical(rawValues)
    numericValues = double(rawValues);
elseif isdatetime(rawValues)
    numericValues = posixtime(rawValues);
else
    numericValues = str2double(string(rawValues));
end

if any(isnan(numericValues))
    error('A required numeric state column contains NaN or non-numeric values.');
end
end

function indices = indexIntoStableUnique(values, uniqueValues)
[isFound, indices] = ismember(values, uniqueValues);
if ~all(isFound)
    error('Internal indexing failure while mapping unique values.');
end
end

function timeStepSeconds = inferTimeStepSeconds(timeKeys)
timeStepSeconds = NaN;

if numel(timeKeys) < 2
    return;
end

dt = tryParseTimeKeys(timeKeys);
if ~isempty(dt)
    diffs = seconds(diff(dt));
else
    numericTime = str2double(timeKeys);
    if any(isnan(numericTime))
        return;
    end
    diffs = diff(numericTime);
end

diffs = diffs(isfinite(diffs) & diffs > 0);
if isempty(diffs)
    return;
end

timeStepSeconds = median(diffs);
end

function dt = tryParseTimeKeys(timeKeys)
timeKeys = string(timeKeys);

formats = [ ...
    "dd MMM yyyy HH:mm:ss.SSS", ...
    "dd MMM yyyy HH:mm:ss", ...
    "yyyy-MM-dd HH:mm:ss.SSS", ...
    "yyyy-MM-dd HH:mm:ss", ...
    "yyyy/MM/dd HH:mm:ss.SSS", ...
    "yyyy/MM/dd HH:mm:ss", ...
    "MM/dd/yyyy HH:mm:ss.SSS", ...
    "MM/dd/yyyy HH:mm:ss"];

for i = 1:numel(formats)
    try
        dt = datetime(timeKeys, 'InputFormat', formats(i), 'Locale', 'en_US');
        if all(~isnat(dt))
            return;
        end
    catch
    end
end

try
    parsed = datetime(timeKeys);
    if any(isnat(parsed))
        dt = [];
    else
        dt = parsed;
    end
catch
    dt = [];
end
end

function GS_Positions = buildGroundStationSeries(GS_Defs, numTimeSteps)
numGS = numel(GS_Defs);
GS_Positions = zeros(numGS, numTimeSteps, 3);

for k = 1:numGS
    gsEcef = geodeticToECEFkm(GS_Defs(k).Lat, GS_Defs(k).Lon, 0);
    GS_Positions(k, :, 1) = gsEcef(1);
    GS_Positions(k, :, 2) = gsEcef(2);
    GS_Positions(k, :, 3) = gsEcef(3);
end
end

function exportVisibilitySeries(outputDir, distanceLimit, timeKeys, SatPositions, SatVelocities, ...
    GS_Positions, allNodeNames, pairIndices, Re, useParallel)

% 每个时间步都会单独生成一个 visibility_step*.csv。
numSats = size(SatPositions, 1);
numTimeSteps = size(SatPositions, 2);
numGS = size(GS_Positions, 1);

for t_idx = 1:numTimeSteps
    current_time_str = string(timeKeys(t_idx));
    safe_time_str = makeSafeTimeToken(current_time_str, t_idx);

    fprintf('    Step %d/%d (%s)... ', t_idx, numTimeSteps, current_time_str);
    step_timer = tic;

    satPosNow = reshape(SatPositions(:, t_idx, :), [numSats, 3]);
    satVelNow = reshape(SatVelocities(:, t_idx, :), [numSats, 3]);
    gsPosNow = reshape(GS_Positions(:, t_idx, :), [numGS, 3]);

    allPositions = [satPosNow; gsPosNow];
    allVelocities = [satVelNow; zeros(numGS, 3)];

    % 对当前时间步的所有节点对统一计算：
    % 距离、相对角速度、相对速度、可见性。
    [results_dist, results_omega, results_rel_speed, results_visible] = computeLinkMetrics( ...
        allPositions, allVelocities, pairIndices, Re, useParallel);

    mask = results_visible & (results_dist < distanceLimit);
    visible_idx1 = pairIndices(mask, 1);
    visible_idx2 = pairIndices(mask, 2);
    visible_dists = results_dist(mask);
    visible_omegas = results_omega(mask);
    visible_rel_speeds = results_rel_speed(mask);
    fileName = sprintf('visibility_step%04d_%s.csv', t_idx, safe_time_str);
    outputPath = fullfile(outputDir, fileName);

    if ~isempty(visible_dists)
        T_out = table( ...
            allNodeNames(visible_idx1), ...
            allNodeNames(visible_idx2), ...
            visible_dists, ...
            visible_omegas, ...
            visible_rel_speeds, ...
            'VariableNames', {'Sat1', 'Sat2', 'Distance_km', 'AngularVelocity_rad_s', 'RelativeSpeed_km_s'});
        writetable(T_out, outputPath);
        fprintf('%d links (%.2f s)\n', height(T_out), toc(step_timer));
    else
        T_out = table( ...
            strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
            'VariableNames', {'Sat1', 'Sat2', 'Distance_km', 'AngularVelocity_rad_s', 'RelativeSpeed_km_s'});
        writetable(T_out, outputPath);
        fprintf('0 links (%.2f s)\n', toc(step_timer));
    end
end
end

function [results_dist, results_omega, results_rel_speed, results_visible] = ...
    computeLinkMetrics(allPositions, allVelocities, pairIndices, Re, useParallel)

% 这一层负责遍历所有节点对，并把单对计算结果收集起来。
totalPairs = size(pairIndices, 1);
results_dist = nan(totalPairs, 1);
results_omega = nan(totalPairs, 1);
results_rel_speed = nan(totalPairs, 1);
results_visible = false(totalPairs, 1);

if useParallel
    parfor k = 1:totalPairs
        [results_dist(k), results_omega(k), results_rel_speed(k), results_visible(k)] = ...
            evaluatePair(pairIndices(k, 1), pairIndices(k, 2), allPositions, allVelocities, Re);
    end
else
    for k = 1:totalPairs
        [results_dist(k), results_omega(k), results_rel_speed(k), results_visible(k)] = ...
            evaluatePair(pairIndices(k, 1), pairIndices(k, 2), allPositions, allVelocities, Re);
    end
end
end

function [dist, omega, relSpeed, isVisible] = evaluatePair(idx1, idx2, allPositions, allVelocities, Re)
% 对单个节点对计算：
% 1. 欧氏距离
% 2. 相对角速度
% 3. 相对速度模长
% 4. 是否被地球遮挡
pos1 = allPositions(idx1, :);
pos2 = allPositions(idx2, :);
vel1 = allVelocities(idx1, :);
vel2 = allVelocities(idx2, :);

if any(~isfinite(pos1)) || any(~isfinite(pos2)) || any(~isfinite(vel1)) || any(~isfinite(vel2))
    dist = nan;
    omega = nan;
    relSpeed = nan;
    isVisible = false;
    return;
end

d_vec = pos2 - pos1;
dist = norm(d_vec);

if dist <= 0 || ~isfinite(dist)
    omega = nan;
    relSpeed = nan;
    isVisible = false;
    return;
end

v_vec = vel2 - vel1;
omega = norm(cross(d_vec, v_vec)) / (dist^2 + eps);
relSpeed = norm(v_vec);

isVisible = true;
t_val = -dot(pos1, d_vec) / (dot(d_vec, d_vec) + eps);
if t_val > 0 && t_val < 1
    closest_point = pos1 + t_val * d_vec;
    if norm(closest_point) < Re
        isVisible = false;
    end
end
end

function tf = tryStartParallelPool()
tf = false;

try
    poolObj = gcp('nocreate');
    if isempty(poolObj)
        parpool;
    end
    tf = ~isempty(gcp('nocreate'));
catch ME
    fprintf('  Parallel disabled: %s\n', ME.message);
end
end

function token = makeSafeTimeToken(timeKey, indexValue)
token = regexprep(char(timeKey), '[:. /\\-]', '_');
token = regexprep(token, '_+', '_');
token = strtrim(token);

if isempty(token)
    token = sprintf('step_%04d', indexValue);
end
end

function folderName = makeOutputSubfolderName(timeStepSeconds, distanceLimit)
if isfinite(timeStepSeconds) && timeStepSeconds > 0
    folderName = sprintf('Results_Step%gs_Limit%dkm_CSV', timeStepSeconds, distanceLimit);
else
    folderName = sprintf('Results_Limit%dkm_CSV', distanceLimit);
end
end

function ensureFolderExists(folderPath)
if ~exist(folderPath, 'dir')
    mkdir(folderPath);
end
end

function ecef = geodeticToECEFkm(latDeg, lonDeg, altKm)
a = 6378.137;
f = 1 / 298.257223563;
e2 = f * (2 - f);

lat = deg2rad(latDeg);
lon = deg2rad(lonDeg);
sinLat = sin(lat);
cosLat = cos(lat);
cosLon = cos(lon);
sinLon = sin(lon);

N = a / sqrt(1 - e2 * sinLat^2);
ecef = [(N + altKm) * cosLat * cosLon, ...
        (N + altKm) * cosLat * sinLon, ...
        (N * (1 - e2) + altKm) * sinLat];
end

function value = getConfigValue(cfg, fieldName, defaultValue)
if isstruct(cfg) && isfield(cfg, fieldName)
    value = cfg.(fieldName);
else
    value = defaultValue;
end
end
