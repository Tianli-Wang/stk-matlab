% =========================================================================
% STK 并行计算完整�? - 含地面站接入分析 (北京 -> 巴西利亚)
% 功能�?
% 1. 建立星座与地面站
% 2. 提取全时段位置与速度数据 (新增)
% 3. 按时间步输出�?
%    - 文件A: 地面站接入情�? (SourceSat, TargetSat)
% 3. 按时间步输出：
%    - 文件A: 地面站接入情况 (SourceSat, TargetSat)
%    - 文件B: 所有星间链路 (ISL)，包含相对角速度 (新增)
% 4. 结果存入 ../OutputFiles/Sim_Timestamp 目录 (新增)
% =======================================================================

%% 0. 全局设置
clear; clc;
USE_ENGINE = 1;       % 1 = STK Engine (无界面，快); 0 = GUI (有界面)
distance_limit = 2000; % 初始星间链路距离阈值 (km)
time_step_val = 5;    % 时间步长 (秒)

% ===== 新增：工作模式选择接口 =====
CONSTELLATION_MODE = 'MultiLayer'; % 可选: 'SingleLayer', 'MultiLayer'
SCENARIO_MODE = 'BBS';              % 可选: 'BBS', 'NLS'
% ==================================

% ================= [修改开始] 输出路径配置 =================
% 1. 生成本次运行的唯一时间戳
% current_timestamp = datestr(now, 'yyyymmdd_HHMMSS');

% 2. [关键修改] 定义绝对路径 (全局目录)
% -----------------------------------------------------------
% 请根据你的操作系统，将下面的路径修改为你实际想要存放的文件夹
% Windows 示例: 'D:\Research\STK_Project\OutputFiles'
% Linux/Mac 示例: '/home/user/data/stk_output'
% -----------------------------------------------------------
base_root = 'C:\Users\Tianl\Documents\PhD\Papers\second_paper\Algorith\OutputFiles'; 

% 3. 定义本次仿真的总文件夹
if strcmp(CONSTELLATION_MODE, 'MultiLayer')
    folder_mode_str = sprintf('%s_MultiLayer', SCENARIO_MODE);
else
    folder_mode_str = SCENARIO_MODE;
end
run_root_folder = fullfile(base_root, sprintf('RawData_%s', folder_mode_str));
% 确保总目录存在 (如果对应的文件夹不存在，Matlab会自动创建)
if ~exist(run_root_folder, 'dir')
    try
        mkdir(run_root_folder);
        fprintf('已创建本次仿真总目录: %s\n', run_root_folder);
    catch ME
        error('无法创建输出目录，请检查盘符或权限。\n错误路径: %s\n错误信息: %s', run_root_folder, ME.message);
    end
end

% 4. 定义当前参数的具体子文件夹
sub_folder_name = sprintf('Results_Step%ds_Limit%dkm', time_step_val, distance_limit);
output_folder = fullfile(run_root_folder, sub_folder_name);
% ================= [修改结束] =================

% 5. [关键修改] 定义 GS 与 Visibility 的分类文件夹
vis_folder = fullfile(output_folder, 'Visibility_Datas');  % Visibility类文件存放处

% 创建分类文件夹
if ~exist(vis_folder, 'dir'), mkdir(vis_folder); end

fprintf('输出目录已准备:\n  链路数据: %s\n', vis_folder);

%% 1. 初始化 STK
if USE_ENGINE
    try
        app = actxserver('STKX11.application');
        root = actxserver('AgStkObjects11.AgStkObjectRoot');
    catch ME
        error('无法启动 STK Engine。请检查许可证\n错误: %s', ME.message);
    end
else
    try
        app = actxserver('STK11.application');
        root = app.Personality2;
    catch ME
        error('无法启动 STK GUI。\n错误: %s', ME.message);
    end
end

%% 2. 重置与创建场景
fprintf('正在初始化场景...\n');
try
    root.CloseScenario(); % 强行关闭任何已打开的场景
catch ME
    fprintf('信息:没有需要关闭的旧场景。\n');
end

StartTime = '27 Feb 2025 00:00:00.000'; 
StopTime  = '27 Feb 2025 01:00:00.000'; % 示例为1小时

scenario = root.Children.New('eScenario', 'MATLAB_Routing_Analysis');
scenario.SetTimePeriod(StartTime, StopTime);
scenario.StartTime = StartTime;
scenario.StopTime = StopTime;

%% 重置动画
if ~USE_ENGINE
    try
        root.ExecuteCommand('Animate * Reset');
        disp('动画已复位成功');
    catch ME
        disp('动画复位失败:');
        disp(ME.message);
    end
end

%% 3. 创建星座
fprintf('正在创建 %s 星座...\n', CONSTELLATION_MODE);

if strcmp(CONSTELLATION_MODE, 'SingleLayer')
    LayerConfigs = struct('P', 72, 'N', 22, 'F', 17, 'Alt', 550, 'Inc', 53, 'NamePrefix', 'STARLINK');
else
    % MultiLayer
    LayerConfigs = repmat(struct('P', 0, 'N', 0, 'F', 0, 'Alt', 0, 'Inc', 0, 'NamePrefix', ''), 2, 1);
    LayerConfigs(1) = struct('P', 80, 'N', 76, 'F', 11, 'Alt', 550, 'Inc', 53, 'NamePrefix', 'L1');
    LayerConfigs(2) = struct('P', 72, 'N', 96, 'F', 15, 'Alt', 1145, 'Inc', 75, 'NamePrefix', 'L2');
end

% 测试模式开关
isTestMode = false; 

for layer_idx = 1:length(LayerConfigs)
    P = LayerConfigs(layer_idx).P;
    N = LayerConfigs(layer_idx).N;
    F = LayerConfigs(layer_idx).F;
    Alt = LayerConfigs(layer_idx).Alt;
    Inc = LayerConfigs(layer_idx).Inc;
    prefix = LayerConfigs(layer_idx).NamePrefix;
    
    TotalSatsFull = P * N; 
    
    if isTestMode
        P = 5; N = 22; 
        fprintf('!!! 测试模式: 第 %d 层仅生成 %d 个平面 !!!\n', layer_idx, P);
    end
    
    fprintf('正在生成第 %d 层: %d 个平面, 每面 %d 颗卫星 (Alt=%d, Inc=%d, F=%d)...\n', layer_idx, P, N, Alt, Inc, F);
    
    for i = 1:P
        seedName = sprintf('%s_Seed_Plane%d', prefix, i);
        params = struct();
        params.satelliteName = seedName;
        params.perigeeAlt    = Alt;      
        params.apogeeAlt     = Alt;      
        params.inclination   = Inc;       
        params.argOfPerigee  = 0;        
        params.RAAN = (i-1) * 360 / LayerConfigs(layer_idx).P; 
        phaseOffset = (i-1) * 360 * F / TotalSatsFull; 
        params.Anomaly = mod(phaseOffset, 360); 
        
        satObj = module.sat(); 
        satObj.createSatellite(root, scenario, params);
        
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
            fprintf('已完成第 %d 层平面: %d / %d\n', layer_idx, i, P);
        end
    end
end

fprintf('星座创建完成。\n');

% 整理卫星名称
fprintf('正在整理卫星列表...\n');
sat = module.sat();
sat.batchRenameSatellitesInSTK2(root, sat.getSatelliteNames(scenario)); 
satellite_names = sat.getSatelliteNames(scenario);
numSats = length(satellite_names);

%% 4. 创建地面站
fprintf('正在配置地面站...\n');
if strcmp(SCENARIO_MODE, 'BBS')
    GS_Defs = struct('Name', {'Beijing', 'Brasilia'}, ...
                     'Lat', {39.9042, -15.7975}, ... 
                     'Lon', {116.4074, -47.8919});   
else
    GS_Defs = struct('Name', {'NewYork', 'London'}, ...
                     'Lat', {40.7128, 51.5074}, ... 
                     'Lon', {-74.0060, -0.1278});   
end
for k = 1:length(GS_Defs)
    try
        root.ExecuteCommand(['Unload / */Facility/' GS_Defs(k).Name]);
    catch
    end
    facility = scenario.Children.New('eFacility', GS_Defs(k).Name);
    facility.Position.AssignGeodetic(GS_Defs(k).Lat, GS_Defs(k).Lon, 0);
end

fprintf('场景准备就绪。共 %d 颗卫�?, 2 个地面站。\n', numSats);

%% ============================================================
%% [阶段1] 批量提取数据 (卫星 + 地面�?)
%% ============================================================ 

fprintf('\n[阶段1] 正在提取�?有位置和速度数据...\n');

% 1.1 提取卫星数据
SatDataAll = cell(numSats, 1); 
SatVelAll = cell(numSats, 1);  % <--- [新增] 存储速度数据
GlobalTimeStrs = {}; 

ppm_exist = exist('ParforProgressMonitor', 'class');
if ppm_exist, ppm = ParforProgressMonitor(numSats, '提取卫星数据'); end

for i = 1:numSats
    satName = satellite_names{i};
    try
        obj = root.GetObjectFromPath(['Satellite/' satName]);
        
        % --- 提取位置 ---
        dp_pos = obj.DataProviders.Item('Vectors(Fixed)').Group.Item('Position');
        res_pos = dp_pos.Exec(StartTime, StopTime, time_step_val);
        
        x = cell2mat(res_pos.DataSets.GetDataSetByName('x').GetValues);
        y = cell2mat(res_pos.DataSets.GetDataSetByName('y').GetValues);
        z = cell2mat(res_pos.DataSets.GetDataSetByName('z').GetValues);
        SatDataAll{i} = [x, y, z];
        
        % --- [新增] 提取速度 ---
        dp_vel = obj.DataProviders.Item('Vectors(Fixed)').Group.Item('Velocity');
        res_vel = dp_vel.Exec(StartTime, StopTime, time_step_val);
        vx = cell2mat(res_vel.DataSets.GetDataSetByName('x').GetValues);
        vy = cell2mat(res_vel.DataSets.GetDataSetByName('y').GetValues);
        vz = cell2mat(res_vel.DataSets.GetDataSetByName('z').GetValues);
        SatVelAll{i} = [vx, vy, vz]; % <--- [新增] 存储速度向量
        
        if i == 1
            time_vals = res_pos.DataSets.GetDataSetByName('Time').GetValues;
            GlobalTimeStrs = string(time_vals);
        end
    catch
        SatDataAll{i} = [];
        SatVelAll{i} = [];
    end
    if mod(i, 200) == 0, fprintf('  卫星数据已提�?: %d/%d\n', i, numSats); end
end

% 1.2 提取地面站数�?
fprintf('正在提取地面站位置数�?...\n');
GS_Pos_All = cell(1, 2); 
for k = 1:length(GS_Defs)
    gsObj = root.GetObjectFromPath(['Facility/' GS_Defs(k).Name]);
    dp_gs = gsObj.DataProviders.Item('Vectors(Fixed)').Group.Item('Position');
    res_gs = dp_gs.Exec(StartTime, StopTime, time_step_val);
    
    gx = cell2mat(res_gs.DataSets.GetDataSetByName('x').GetValues);
    gy = cell2mat(res_gs.DataSets.GetDataSetByName('y').GetValues);
    gz = cell2mat(res_gs.DataSets.GetDataSetByName('z').GetValues);
    GS_Pos_All{k} = [gx, gy, gz];
end

numTimeSteps = length(GlobalTimeStrs);
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
if strcmp(CONSTELLATION_MODE, 'MultiLayer')
    folder_mode_str = sprintf('%s_MultiLayer', SCENARIO_MODE);
else
    folder_mode_str = SCENARIO_MODE;
end
run_root_folder = fullfile(base_root, sprintf('RawData_%s', folder_mode_str));
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