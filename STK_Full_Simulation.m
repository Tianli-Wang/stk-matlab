% =========================================================================
% STK 并行计算完整�? - 含地面站接入分析 (北京 -> 巴西利亚)
% 功能�?
% 1. 建立星座与地面站
% 2. 提取全时段位置与速度数据 (新增)
% 3. 按时间步输出�?
%    - 文件A: 地面站接入情�? (SourceSat, TargetSat)
%    - 文件B: �?有星间链�? (ISL)，包含相对角速度 (新增)
% 4. 结果存入 ../OutputFiles/Sim_Timestamp 目录 (新增)
% =======================================================================

%% 0. 全局设置
clear; clc;
USE_ENGINE = 1;       % 1 = STK Engine (无界面，�?); 0 = GUI (有界�?)
distance_limit = 2000; % 初始星间链路距离阈�?? (km)
time_step_val = 5;    % 时间步长 (�?)

% ================= [修改�?始] 输出路径配置与场景�?�择 =================
% 1. 选择地面站仿真场�?
GS_SCENARIO = 'BBS'; % 可在此改�? 'BBS' �? 北京->巴西利亚; 或改�? 'NLS' �? 纽约->伦敦

% 2. 选择星座层数
USE_MULTI_LAYER = true; % <--- 是否启用多层星座可�?�开�? (true: 双层, false: 单层)

if strcmp(GS_SCENARIO, 'BBS')
    gs_suffix = 'BBS';
    % 仅保留北京�?�巴西利�?
    GS_Defs = struct('Name', {'Beijing_Source', 'Brasilia_Target'}, ...
                     'Lat', {39.9042, -15.7975}, ... 
                     'Lon', {116.4074, -47.8919});   
else
    gs_suffix = 'NLS';
    % 仅保留纽约�?�伦�?
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

% 2. 生成本次运行的唯�?时间�?
% current_timestamp = datestr(now, 'yyyymmdd_HHMMSS');

% 3. [关键修改] 定义绝对路径 (全局目录)
base_root = 'C:\Users\Tianl\Documents\PhD\Papers\second_paper\Algorith\OutputFiles'; 

% 4. 定义本次仿真的�?�文件夹 (带后�?)
run_root_folder = fullfile(base_root, sprintf('RawData_%s', run_output_suffix));

% 确保总目录存�? (如果 D�? 对应的文件夹不存在，Matlab会自动创�?)
if ~exist(run_root_folder, 'dir')
    try
        mkdir(run_root_folder);
        fprintf('已创建本次仿真�?�目�?: %s\n', run_root_folder);
    catch ME
        error('无法创建输出目录，请�?查盘符或权限。\n错误路径: %s\n错误信息: %s', run_root_folder, ME.message);
    end
end

% 4. 定义当前参数的具体子文件�?
sub_folder_name = sprintf('Results_Step%ds_Limit%dkm', time_step_val, distance_limit);
output_folder = fullfile(run_root_folder, sub_folder_name);
% ================= [修改结束] =================

% 5. [关键修改] 定义 GS �? Visibility 的分类文件夹
% gs_folder = fullfile(output_folder, 'GS_Datas');      % GS类文件存放处
vis_folder = fullfile(output_folder, 'Visibility_Datas');  % Visibility类文件存放处

% 创建分类文件�?
% if ~exist(gs_folder, 'dir'), mkdir(gs_folder); end
if ~exist(vis_folder, 'dir'), mkdir(vis_folder); end

% fprintf('输出目录已准�?:\n  GS数据: %s\n  链路数据: %s\n', gs_folder, vis_folder);

%% 1. 初始�? STK
if USE_ENGINE
    try
        app = actxserver('STKX11.application');
        root = actxserver('AgStkObjects11.AgStkObjectRoot');
        % app.NoGraphics = true; % 可�?�：完全关闭图形以极致加�?
    catch ME
        error('无法启动 STK Engine。请�?查许可�?�\n错误: %s', ME.message);
    end
else
    try
        app = actxserver('STK11.application');
        root = app.Personality2;
        % app.Visible = true; 
        % app.UserControl = true;
    catch ME
        error('无法启动 STK GUI。\n错误: %s', ME.message);
    end
end

%% 2. 重置与创建场�?
fprintf('正在初始化场�?...\n');
try
    root.CloseScenario(); % 强行关闭任何已打�?的场�?
catch ME
    fprintf('信息:没有�?要关闭的旧场景�?�\n');
end

StartTime = '27 Feb 2025 00:00:00.000'; 
StopTime  = '27 Feb 2025 01:00:00.000'; % 示例�?1小时

scenario = root.Children.New('eScenario', 'MATLAB_Routing_Analysis');
scenario.SetTimePeriod(StartTime, StopTime);
scenario.StartTime = StartTime;
scenario.StopTime = StopTime;

%% 重置动画
if ~USE_ENGINE
    try
        root.ExecuteCommand('Animate * Reset');
        disp('动画已复位成�?');
    catch ME
        disp('动画复位失败:');
        disp(ME.message);
    end
end

%% 3. 创建星座 (Starlink 550km + 新增 1000km Walker)
% 参数定义 (Starlink 550km)
P = 80;   % 轨道面数 (Planes)
N = 76;   % 每面卫星�? (Sats per plane)
F = 11;   % 相位因子 (Phasing Parameter)

% 参数定义 (新增 1000km Walker)
P2 = 72;
N2 = 96;
F2 = 15;

% 测试模式�?�?
isTestMode = false; 
if isTestMode
    P = 5; N = 22; % 测试用小规模
    P2 = 2; N2 = 10;
    fprintf('!!! 测试模式: 仅生成部分平�? !!!\n');
end

TotalSats = 72 * 22; % 真实的满星座总数
if isTestMode, TotalSats = P * N; end

TotalSats2 = 10 * 10; % 1000km 满星座�?�数
if isTestMode, TotalSats2 = P2 * N2; end

fprintf('正在创建 550km�?: %d 个平面，每个平面 %d 颗卫�? (F因子=%d)...\n', P, N, F);

for i = 1:P
    seedName = sprintf('STARLINK_Seed_Plane%d', i);
    params = struct();
    params.satelliteName = seedName;
    params.perigeeAlt    = 550;      
    params.apogeeAlt     = 550;      
    params.inclination   = 53;       
    params.argOfPerigee  = 0;        
    params.RAAN = (i-1) * 360 / P; 
    phaseOffset = (i-1) * 360 * F / TotalSats; 
    params.Anomaly = mod(phaseOffset, 360); 
    
    satObj = module.sat(); 
    satObj.createSatellite(root, scenario, params);
    
    % 在克隆为整个星座前，直接关闭种子卫星的标签，确保克隆出的数千颗卫星默认均不显示标签，解决卡顿
    if ~USE_ENGINE
        try
            root.ExecuteCommand(sprintf('Graphics */Satellite/%s Label Show Off', seedName));
        catch
        end
    end
    
    params_const = struct();
    params_const.seedSatelliteName        = seedName;
    params_const.numPlanes                = 1;
    params_const.numSatsPerPlane          = N;
    params_const.interPlanePhaseIncrement = 0;
    
    satObj.createWalkerConstellation_Delta(root, params_const);
    
    try
        root.ExecuteCommand(sprintf('Unload / */Satellite/%s', seedName));
    catch
        fprintf('警告: 无法卸载种子卫星 %s\n', seedName);
    end
    
    if mod(i, 5) == 0
        fprintf('已完成平�?: %d / %d\n', i, P);
    end
end

if USE_MULTI_LAYER
    fprintf('正在创建 1000km �?: %d 个平面，每个平面 %d 颗卫�? (F因子=%d)...\n', P2, N2, F2);
    for i = 1:P2
        seedName2 = sprintf('WALKER1000_Seed_Plane%d', i);
        params2 = struct();
        params2.satelliteName = seedName2;
        params2.perigeeAlt    = 1145;      
        params2.apogeeAlt     = 1145;      
        params2.inclination   = 75;       
        params2.argOfPerigee  = 0;        
        params2.RAAN = (i-1) * 360 / P2; 
        phaseOffset2 = (i-1) * 360 * F2 / TotalSats2; 
        params2.Anomaly = mod(phaseOffset2, 360); 
        
        satObj.createSatellite(root, scenario, params2);
        
        % 在克隆为整个星座前，关闭第二层星座种子卫星的标签
        if ~USE_ENGINE
            try
                root.ExecuteCommand(sprintf('Graphics */Satellite/%s Label Show Off', seedName2));
            catch
            end
        end
        
        params_const2 = struct();
        params_const2.seedSatelliteName        = seedName2;
        params_const2.numPlanes                = 1;
        params_const2.numSatsPerPlane          = N2;
        params_const2.interPlanePhaseIncrement = 0;
        
        satObj.createWalkerConstellation_Delta(root, params_const2);
        
        try
            root.ExecuteCommand(sprintf('Unload / */Satellite/%%s', seedName2));
        catch
        end
        
        if mod(i, 5) == 0
            fprintf('已完�? 1000km�? 平面: %d / %d\n', i, P2);
        end
    end
    fprintf('多层星座创建完成。\n');
else
    fprintf('仅使用单�? 星座。\n');
end

% 整理卫星名称
fprintf('正在整理卫星列表...\n');
sat = module.sat();
sat.batchRenameSatellitesInSTK2(root, sat.getSatelliteNames(scenario)); 
satellite_names = sat.getSatelliteNames(scenario);
numSats = length(satellite_names);

% 地面站定义已在文件开�? (�? 19-31 �?) �? GS_SCENARIO 配置中完�?

for k = 1:length(GS_Defs)
    try
        root.ExecuteCommand(['Unload / */Facility/' GS_Defs(k).Name]);
    catch
    end
    facility = scenario.Children.New('eFacility', GS_Defs(k).Name);
    facility.Position.AssignGeodetic(GS_Defs(k).Lat, GS_Defs(k).Lon, 0);
end

% 关闭 UI 中所有对象的名称标签显示，防止数千颗卫星造成视窗极其卡顿
if ~USE_ENGINE
    try
        root.ExecuteCommand('Graphics * Label Show Off');
        fprintf('已关�? STK GUI 中所有对象的名称标签显示\n');
    catch
        % 防止部分版本不支持该命令
    end
end

fprintf('场景准备就绪。共 %d 颗卫�?, %d 个地面站。\n', numSats, length(GS_Defs));

%% ============================================================
%% [阶段1] 批量提取数据 (卫星 + 地面�?)
%% ============================================================ 

fprintf('\n[阶段1] 正在提取�?有位置和速度数据...\n');

% 1.1 提取卫星数据
SatDataAll = cell(numSats, 1); 
SatVelAll = cell(numSats, 1);  % <--- [新增] 存储速度数据
GlobalTimeStrs = strings(0, 1);
satellite_paths = strcat("Satellite/", string(satellite_names(:)));
fprintf('  Optimization: native velocity from STK, static GS ECEF reuse\n');

ppm_exist = exist('ParforProgressMonitor', 'class');
if ppm_exist, ppm = ParforProgressMonitor(numSats, '提取卫星数据'); end

for i = 1:numSats
    satName = satellite_names{i};
    try
        obj = root.GetObjectFromPath(char(satellite_paths(i)));
        
        % --- 提取位置 ---
        [sat_pos, time_vals] = extractFixedVectorSeries(obj, 'Position', StartTime, StopTime, time_step_val, true);
        SatDataAll{i} = sat_pos;
        
        % --- [新增] 提取速度 ---
        SatVelAll{i} = extractFixedVectorSeries(obj, 'Velocity', StartTime, StopTime, time_step_val, false);
        
        if isempty(GlobalTimeStrs)
            GlobalTimeStrs = string(time_vals(:));
        end
    catch
        SatDataAll{i} = [];
        SatVelAll{i} = [];
    end
    if mod(i, 200) == 0, fprintf('  卫星数据已提�?: %d/%d\n', i, numSats); end
end

% 1.2 提取地面站数�?
fprintf('正在提取地面站位置数�?...\n');
numTimeSteps = length(GlobalTimeStrs);
GS_Pos_All = cell(1, length(GS_Defs)); 
for k = 1:length(GS_Defs)
    gs_pos_ecef = geodeticToECEFkm(GS_Defs(k).Lat, GS_Defs(k).Lon, 0);
    GS_Pos_All{k} = repmat(gs_pos_ecef, numTimeSteps, 1);
end

fprintf('数据提取完成。共 %d 个时间步。\n', numTimeSteps);

%% ============================================================
%% [阶段2] 核心计算循环 (地面站接�? + 星间链路)
%% ============================================================

fprintf('\n[阶段2] �?始时间循环计�?...\n');

% 准备并行索引 (包含卫星与地面站)
numGS = length(GS_Defs);
totalNodes = numSats + numGS;
allNodeNames = [string(satellite_names(:)); string({GS_Defs.Name})'];

totalPairs = totalNodes * (totalNodes - 1) / 2;
pairIndices = zeros(totalPairs, 2);
idx = 0;
for i = 1:totalNodes
    for j = (i+1):totalNodes
        idx = idx + 1;
        pairIndices(idx, :) = [i, j];
    end
end

% 启动并行�?
poolObj = gcp('nocreate');
if isempty(poolObj), parpool; end

Re = 6378.137; % 地球半径 km
total_timer = tic;

for t_idx = 1:numTimeSteps
    
    current_time_str = GlobalTimeStrs(t_idx);
    safe_time_str = regexprep(current_time_str, '[:. ]', '_');
    
    fprintf('处理时间�? %d/%d (%s)... ', t_idx, numTimeSteps, current_time_str);
    step_timer = tic;
    
    % --- A. 组装当前时刻�?有节�? (卫星+地面�?) 的位置和速度矩阵 ---
    allPositions = zeros(totalNodes, 3);
    allVelocities = zeros(totalNodes, 3);
    
    % 填充卫星数据
    for i = 1:numSats
        if ~isempty(SatDataAll{i})
            allPositions(i, :) = SatDataAll{i}(t_idx, :);
            allVelocities(i, :) = SatVelAll{i}(t_idx, :);
        else
            allPositions(i, :) = [NaN, NaN, NaN];
            allVelocities(i, :) = [NaN, NaN, NaN];
        end
    end
    
    % 填充地面站数�? (视为不动的卫�?)
    for k = 1:numGS
        allPositions(numSats + k, :) = GS_Pos_All{k}(t_idx, :);
        allVelocities(numSats + k, :) = [0, 0, 0]; % 地面站相对地心地固坐标系速度�?0
    end
    
    % =====================================================================
    % --- B. 计算�?有节点间的全拓扑链路 (ISL + 星地) ---
    % =====================================================================
    results_dist = zeros(totalPairs, 1);
    results_omega = zeros(totalPairs, 1);
    results_visible = false(totalPairs, 1);
    
    parfor k = 1:totalPairs
        idx1 = pairIndices(k, 1);
        idx2 = pairIndices(k, 2);
        
        pos1 = allPositions(idx1, :);
        pos2 = allPositions(idx2, :);
        vel1 = allVelocities(idx1, :);
        vel2 = allVelocities(idx2, :);
        
        d_vec = pos2 - pos1; % 相对位置向量 r
        dist = norm(d_vec);
        results_dist(k) = dist;
        
        % --- 计算相对角�?�度 Omega ---
        v_vec = vel2 - vel1; % 相对速度向量 v
        cross_prod = cross(d_vec, v_vec);
        cross_norm = norm(cross_prod);
        omega = cross_norm / (dist^2 + eps); 
        results_omega(k) = omega;
        
        isVisible = true;
        % 遮挡�?�?
        t = -dot(pos1, d_vec) / (dot(d_vec, d_vec) + eps);
        if t > 0 && t < 1
            P_closest = pos1 + t * d_vec;
            if norm(P_closest) < Re
                isVisible = false;
            end
        end
        results_visible(k) = isVisible;
    end
    
    % --- D. 筛�?�并保存结果 ---
    mask = results_visible & (results_dist < distance_limit);
    
    visible_dists = results_dist(mask);
    visible_omegas = results_omega(mask);
    visible_idx1 = pairIndices(mask, 1);
    visible_idx2 = pairIndices(mask, 2);
    count = length(visible_dists);
    
    if count > 0
        S1_col = allNodeNames(visible_idx1);
        S2_col = allNodeNames(visible_idx2);
        D_col = visible_dists;
        O_col = visible_omegas;
        
        T_table = table(S1_col, S2_col, D_col, O_col, ...
            'VariableNames', {'Sat1', 'Sat2', 'Distance_km', 'AngularVelocity_rad_s'});
        
        file_name_isl = sprintf('visibility_step%04d_%s.csv', t_idx, safe_time_str);
        full_path_isl = fullfile(vis_folder, file_name_isl);
        
        writetable(T_table, full_path_isl);
        fprintf('总链�?: %d�? (星际+星地), (耗时 %.2fs)\n', count, toc(step_timer));
    else
        fprintf('无有效链�?, (耗时 %.2fs)\n', toc(step_timer));
    end
end

fprintf('\n全流程处理完�?! 总�?�时: %.2f 秒\n', toc(total_timer));
fprintf('结果保存�?: %s\n', output_folder);


%% ============================================================
%% Additioncal Option 批量核心计算循环 (不同距离阈�??)
%% ============================================================
%% ============================================================
%% [阶段3] 批量核心计算循环 (针对不同距离阈�?�，使用统一 GS 节点逻辑)
%% ============================================================
base_root = 'C:\Users\Tianl\Documents\PhD\Papers\second_paper\Algorith\OutputFiles'; 
run_root_folder = fullfile(base_root, sprintf('RawData_%s', run_output_suffix));
sub_folder_name = sprintf('Results_Step%ds_Limit%dkm', time_step_val, distance_limit);
output_folder = fullfile(run_root_folder, sub_folder_name);
for i = 2:8
    distance_limit = i * 500; % 1000km, 1500km, ..., 4000km
    
    % 定义该距离下的专用输出文件夹 (GS 已经并在 Visibility 里，不需�? GS_Datas �?)
    vis_folder_limit = fullfile(output_folder, sprintf('Visibility_Limit%dkm', distance_limit));
    if ~exist(vis_folder_limit, 'dir'), mkdir(vis_folder_limit); end
    
    fprintf('\n[阶段3] �?始批量循�? (Limit=%d km)...\n', distance_limit);
    fprintf('  数据将存�?: %s\n', vis_folder_limit);

    % 重新计算并行索引 (包含卫星 + 地面�?)
    numGS = length(GS_Defs);
    totalNodes = numSats + numGS;
    % 这里�? allNodeNames 已经在前面定义过了，直接使用
    
    % 计算全排列组合数
    totalPairs = totalNodes * (totalNodes - 1) / 2;
    pairIndices = nchoosek(1:totalNodes, 2);

    total_timer_batch = tic;

    for t_idx = 1:numTimeSteps
        current_time_str = GlobalTimeStrs(t_idx);
        safe_time_str = regexprep(current_time_str, '[:. ]', '_');

        fprintf('Limit %dkm | 步数 %d/%d... ', distance_limit, t_idx, numTimeSteps);
        step_timer = tic;

        % --- A. 组装当前时刻�?有节�? (卫星+地面�?) 的位置和速度矩阵 ---
        allPositions = zeros(totalNodes, 3);
        allVelocities = zeros(totalNodes, 3);
        
        % 填充卫星数据
        for ii = 1:numSats
            if ~isempty(SatDataAll{ii})
                allPositions(ii, :) = SatDataAll{ii}(t_idx, :);
                allVelocities(ii, :) = SatVelAll{ii}(t_idx, :);
            end
        end
        % 填充地面站数�? (视为不动的卫�?)
        for k = 1:numGS
            allPositions(numSats + k, :) = GS_Pos_All{k}(t_idx, :);
            allVelocities(numSats + k, :) = [0, 0, 0];
        end

        % --- B. 并行计算�?有链�? (ISL + 星地) ---
        results_dist = zeros(totalPairs, 1);
        results_omega = zeros(totalPairs, 1);
        results_visible = false(totalPairs, 1);

        parfor k_pair = 1:totalPairs
            idx1 = pairIndices(k_pair, 1);
            idx2 = pairIndices(k_pair, 2);

            pos1 = allPositions(idx1, :);
            pos2 = allPositions(idx2, :);
            vel1 = allVelocities(idx1, :);
            vel2 = allVelocities(idx2, :);

            d_vec = pos2 - pos1;
            dist = norm(d_vec);
            results_dist(k_pair) = dist;

            % 计算相对角�?�度
            v_vec = vel2 - vel1;
            results_omega(k_pair) = norm(cross(d_vec, v_vec)) / (dist^2 + eps);

            % 遮挡�?�?
            isVisible = true;
            t_val = -dot(pos1, d_vec) / (dot(d_vec, d_vec) + eps);
            if t_val > 0 && t_val < 1
                P_closest = pos1 + t_val * d_vec;
                if norm(P_closest) < Re
                    isVisible = false;
                end
            end
            results_visible(k_pair) = isVisible;
        end

        % --- C. 筛�?�并保存 ---
        mask = results_visible & (results_dist < distance_limit);
        
        visible_dists = results_dist(mask);
        visible_omegas = results_omega(mask);
        visible_idx1 = pairIndices(mask, 1);
        visible_idx2 = pairIndices(mask, 2);
        count = length(visible_dists);

        if count > 0
            S1_col = allNodeNames(visible_idx1);
            S2_col = allNodeNames(visible_idx2);
            
            T_table = table(S1_col, S2_col, visible_dists, visible_omegas, ...
                'VariableNames', {'Sat1', 'Sat2', 'Distance_km', 'AngularVelocity_rad_s'});

            file_name_isl = sprintf('visibility_step%04d_%s.csv', t_idx, safe_time_str);
            full_path_isl = fullfile(vis_folder_limit, file_name_isl);
            writetable(T_table, full_path_isl);
            fprintf('总链�?: %d�? (耗时 %.2fs)\n', count, toc(step_timer));
        else
            fprintf('无有效链�? (耗时 %.2fs)\n', toc(step_timer));
        end
    end

    fprintf('\nBatch Limit=%d km 执行完毕! 总�?�时: %.2f 秒\n', distance_limit, toc(total_timer_batch));
end

%% =========================================================================
%% [可视化功能] 根据 calculated_routes.csv 绘制红色链路
%% =========================================================================
% 注意：此功能�?要外部生成的 calculated_routes.csv 存在�? MATLAB 当前目录�?
fprintf('\n[可视化] 正在尝试根据 calculated_routes.csv 绘制红色链路...\n');
route_file = 'calculated_routes.csv'; 

if exist(route_file, 'file')
    T_route = readtable(route_file);
    for row_idx = 1:height(T_route)
        path_str = char(T_route.Path{row_idx});       
        source_gs = char(T_route.SourceGS{row_idx});  
        target_gs = char(T_route.TargetGS{row_idx});  
        source_sat = char(T_route.SourceSat{row_idx});
        target_sat = char(T_route.TargetSat{row_idx});
        
        fprintf('  正在绘制路径 %d: %s -> %s\n', row_idx, source_gs, target_gs);
        sat_list = strsplit(path_str, ' -> ');

        color_red = 255; 
        line_width = 3; 

        % A. SourceGS -> SourceSat
        try
            obj_gs = root.GetObjectFromPath(['Facility/' source_gs]);
            obj_sat = root.GetObjectFromPath(['Satellite/' source_sat]);
            access_obj = obj_gs.GetAccessToObject(obj_sat);
            access_obj.ComputeAccess(); 
            access_obj.Graphics.Color = color_red;
            access_obj.Graphics.LineWidth = line_width;
        catch ME
            fprintf('    警告: 无法连接 %s �? %s\n', source_gs, source_sat);
        end

        % B. ISL
        for i = 1:length(sat_list)-1
            s1_name = strtrim(sat_list{i});
            s2_name = strtrim(sat_list{i+1});
            try
                obj1 = root.GetObjectFromPath(['Satellite/' s1_name]);
                obj2 = root.GetObjectFromPath(['Satellite/' s2_name]);
                access_obj = obj1.GetAccessToObject(obj2);
                access_obj.ComputeAccess();
                access_obj.Graphics.Color = color_red;
                access_obj.Graphics.LineWidth = line_width;
            catch 
                fprintf('    警告: 无法建立星间链路 %s <-> %s\n', s1_name, s2_name);
            end
        end

        % C. TargetSat -> TargetGS
        try
            obj_sat = root.GetObjectFromPath(['Satellite/' target_sat]);
            obj_gs = root.GetObjectFromPath(['Facility/' target_gs]);
            access_obj = obj_sat.GetAccessToObject(obj_gs);
            access_obj.ComputeAccess();
            access_obj.Graphics.Color = color_red;
            access_obj.Graphics.LineWidth = line_width;
        catch ME
            fprintf('    警告: 无法连接 %s �? %s\n', target_sat, target_gs);
        end
    end
    
    fprintf('[可视化] 全部完成！请切换�? STK 3D 窗口查看红色链路。\n');
    if ~USE_ENGINE
        root.ExecuteCommand('Graphics * Draw'); 
    end
else
    fprintf('提示: 未找�? %s，跳过可视化步骤。\n', route_file);
end

function [vectorData, timeVals] = extractFixedVectorSeries(obj, vectorName, startTime, stopTime, timeStep, returnTime)
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
