% =========================================================================
% STK 并行计算完整版 - 路径定义完全前置 (预生成所有目录结构)
% 功能：
% 1. 在第0步就创建好所有需要的文件夹 (GS_Datas, Visibility_Datas)
% 2. 主循环中直接调用预设路径，不再进行 mkdir 操作
% =========================================================================

%% 0. 全局设置与全局路径定义
clear; clc;
USE_ENGINE = 1;       % 1 = STK Engine (无界面，快); 0 = GUI (有界面)
time_step_val = 5;    % 时间步长 (秒)

% --- [配置] 想要遍历的距离阈值列表 (单位: km) ---
distance_loop_array = 500:500:4000; % [500, 1000, ..., 4000]

% ================= [路径定义与预创建区域] =================
% 1. 定义绝对路径 (全局根目录)
base_root = 'C:\Users\Tianl\Documents\PhD\Papers\second_paper\Algorith\OutputFiles'; 

% 2. 定义本次仿真的总文件夹 (固定名称 RawData)
run_root_folder = fullfile(base_root, 'RawData');

% 3. 创建总目录
if ~exist(run_root_folder, 'dir')
    try
        mkdir(run_root_folder);
        fprintf('已创建总目录: %s\n', run_root_folder);
    catch ME
        error('无法创建输出目录，请检查路径或权限。\n路径: %s\n错误: %s', run_root_folder, ME.message);
    end
else
    fprintf('使用现有目录: %s\n', run_root_folder);
end

% 4. [关键修改] 预先定义并创建所有子文件夹
% 我们使用结构体数组 PathConfigs 来存储每一组距离对应的路径
fprintf('正在预生成所有子目录结构...\n');
PathConfigs = struct(); 

for idx = 1:length(distance_loop_array)
    d_val = distance_loop_array(idx);
    
    % 定义每层的名称
    sub_name = sprintf('Results_Step%ds_Limit%dkm', time_step_val, d_val);
    sub_dir  = fullfile(run_root_folder, sub_name);
    
    gs_dir   = fullfile(sub_dir, 'GS_Datas');
    vis_dir  = fullfile(sub_dir, 'Visibility_Datas');
    
    % 创建文件夹 (Fail Fast: 如果没权限现在就报错，不要等到跑了一半再报)
    if ~exist(sub_dir, 'dir'), mkdir(sub_dir); end
    if ~exist(gs_dir, 'dir'),  mkdir(gs_dir);  end
    if ~exist(vis_dir, 'dir'), mkdir(vis_dir); end
    
    % 将路径存入结构体，供后续循环直接调用
    PathConfigs(idx).Limit = d_val;
    PathConfigs(idx).GS_Folder  = gs_dir;
    PathConfigs(idx).Vis_Folder = vis_dir;
    
    fprintf('  [Limit %dkm] -> GS: ...%s | Vis: ...%s\n', ...
            d_val, '\GS_Datas', '\Visibility_Datas');
end
fprintf('目录结构初始化完成。\n');
% ==========================================================

%% 1. 初始化 STK
if USE_ENGINE
    try
        app = actxserver('STKX11.application');
        root = actxserver('AgStkObjects11.AgStkObjectRoot');
        % app.NoGraphics = true; % 可选：完全关闭图形以极致加速
    catch ME
        error('无法启动 STK Engine。请检查许可。\n错误: %s', ME.message);
    end
else
    try
        app = actxserver('STK11.application');
        root = app.Personality2;
        app.Visible = true; 
        app.UserControl = true;
    catch ME
        error('无法启动 STK GUI。\n错误: %s', ME.message);
    end
end

%% 2. 重置与创建场景
fprintf('正在初始化场景...\n');
try
    root.CloseScenario(); % 强行关闭任何已打开的场景
catch
    fprintf('信息: 没有需要关闭的旧场景。\n');
end

StartTime = '27 Feb 2025 00:00:00.000'; 
StopTime  = '27 Feb 2025 01:00:00.000'; 

scenario = root.Children.New('eScenario', 'MATLAB_Routing_Analysis');
scenario.SetTimePeriod(StartTime, StopTime);
scenario.StartTime = StartTime;
scenario.StopTime = StopTime;

%% 重置动画
if ~USE_ENGINE
    try
        root.ExecuteCommand('Animate * Reset');
    catch
    end
end

%% 3. 创建星座 (Starlink Gen1 Shell 1: Walker Delta)
% 参数定义
P = 72;   % 轨道面数 (Planes)
N = 22;   % 每面卫星数 (Sats per plane)
F = 17;   % 相位因子 (Phasing Parameter)

% 测试模式开关 (如果要跑全星座，请改为 false)
isTestMode = true; 
if isTestMode
    P = 5; N = 22; % 测试用小规模
    fprintf('!!! 测试模式: 仅生成 %d 个平面 !!!\n', P);
end

TotalSats = 72 * 22; 
if isTestMode, TotalSats = P * N; end

fprintf('正在创建 %d 个平面，每个平面 %d 颗卫星 (F因子=%d)...\n', P, N, F);

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
    
    params_const = struct();
    params_const.seedSatelliteName        = seedName;
    params_const.numPlanes                = 1;
    params_const.numSatsPerPlane          = N;
    params_const.interPlanePhaseIncrement = 0;
    
    satObj.createWalkerConstellation_Delta(root, params_const);
    
    try
        root.ExecuteCommand(sprintf('Unload / */Satellite/%s', seedName));
    catch
    end
    
    if mod(i, 5) == 0
        fprintf('已完成平面: %d / %d\n', i, P);
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
GS_Defs = struct('Name', {'Beijing_Source', 'Brasilia_Target'}, ...
                 'Lat', {39.9042, -15.7975}, ... 
                 'Lon', {116.4074, -47.8919});    

for k = 1:length(GS_Defs)
    try
        root.ExecuteCommand(['Unload / */Facility/' GS_Defs(k).Name]);
    catch
    end
    facility = scenario.Children.New('eFacility', GS_Defs(k).Name);
    facility.Position.AssignGeodetic(GS_Defs(k).Lat, GS_Defs(k).Lon, 0);
end

fprintf('场景准备就绪。共 %d 颗卫星, 2 个地面站。\n', numSats);

%% ============================================================
%% [阶段1] 批量提取数据 (只执行一次)
%% ============================================================ 

fprintf('\n[阶段1] 正在提取所有位置和速度数据...\n');

% 1.1 提取卫星数据
SatDataAll = cell(numSats, 1); 
SatVelAll = cell(numSats, 1); 
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
        
        % --- 提取速度 ---
        dp_vel = obj.DataProviders.Item('Vectors(Fixed)').Group.Item('Velocity');
        res_vel = dp_vel.Exec(StartTime, StopTime, time_step_val);
        vx = cell2mat(res_vel.DataSets.GetDataSetByName('x').GetValues);
        vy = cell2mat(res_vel.DataSets.GetDataSetByName('y').GetValues);
        vz = cell2mat(res_vel.DataSets.GetDataSetByName('z').GetValues);
        SatVelAll{i} = [vx, vy, vz];
        
        if i == 1
            time_vals = res_pos.DataSets.GetDataSetByName('Time').GetValues;
            GlobalTimeStrs = string(time_vals);
        end
    catch
        SatDataAll{i} = [];
        SatVelAll{i} = [];
    end
    if mod(i, 200) == 0, fprintf('  卫星数据已提取: %d/%d\n', i, numSats); end
end

% 1.2 提取地面站数据
fprintf('正在提取地面站位置数据...\n');
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
%% [阶段2] 核心计算循环
%% ============================================================

fprintf('\n[阶段2] 开始批量处理... 待处理距离列表: %s\n', mat2str(distance_loop_array));

% 准备并行索引
totalPairs = numSats * (numSats - 1) / 2;
pairIndices = zeros(totalPairs, 2);
idx = 0;
for i = 1:numSats
    for j = (i+1):numSats
        idx = idx + 1;
        pairIndices(idx, :) = [i, j];
    end
end

poolObj = gcp('nocreate');
if isempty(poolObj), parpool; end

Re = 6378.137; 
total_batch_timer = tic;

% --- 核心：距离阈值循环 ---
for d_idx = 1:length(distance_loop_array)
    
    % ================= [从预设配置中读取路径] =================
    % 不再进行 mkdir 或 fullfile 操作，直接读取 Section 0 生成的配置
    current_dist_limit = PathConfigs(d_idx).Limit;
    gs_folder          = PathConfigs(d_idx).GS_Folder;
    vis_folder         = PathConfigs(d_idx).Vis_Folder;
    % =========================================================
    
    fprintf('\n>>> [Loop %d/%d] 距离阈值 = %d km <<<\n', ...
            d_idx, length(distance_loop_array), current_dist_limit);

    loop_timer = tic;
    
    for t_idx = 1:numTimeSteps
        
        current_time_str = GlobalTimeStrs(t_idx);
        safe_time_str = regexprep(current_time_str, '[:. ]', '_');
        
        if mod(t_idx, 50) == 0 || t_idx == 1
            fprintf('  处理时间步 %d/%d (%s)...\n', t_idx, numTimeSteps, current_time_str);
        end
        
        % --- A. 组装数据 ---
        currentSatPositions = zeros(numSats, 3);
        currentSatVelocities = zeros(numSats, 3); 
        
        for i = 1:numSats
            if ~isempty(SatDataAll{i})
                currentSatPositions(i, :) = SatDataAll{i}(t_idx, :);
                currentSatVelocities(i, :) = SatVelAll{i}(t_idx, :);
            else
                currentSatPositions(i, :) = [NaN, NaN, NaN];
                currentSatVelocities(i, :) = [NaN, NaN, NaN];
            end
        end
        
        % --- B. 地面站接入计算 ---
        gs_results = struct('SatName', {'', ''}, 'Dist', {Inf, Inf});
        for k = 1:2
            current_gs_pos = GS_Pos_All{k}(t_idx, :);
            vec_gs_to_sats = currentSatPositions - current_gs_pos;
            dists_gs_sats = sqrt(sum(vec_gs_to_sats.^2, 2));
            
            % 可见性
            dot_prods = sum(repmat(current_gs_pos, numSats, 1) .* vec_gs_to_sats, 2);
            is_visible = dot_prods > 0;
            
            valid_dists = dists_gs_sats;
            valid_dists(~is_visible) = Inf;
            
            [min_dist, min_idx] = min(valid_dists);
            
            if ~isinf(min_dist)
                gs_results(k).SatName = satellite_names{min_idx};
                gs_results(k).Dist = min_dist;
            else
                gs_results(k).SatName = "None";
                gs_results(k).Dist = NaN;
            end
        end
        
        % [保存] GS 数据
        if ~strcmp(gs_results(1).SatName, "None") || ~strcmp(gs_results(2).SatName, "None")
            file_name_gs = sprintf('GS_Route_step%04d_%s.csv', t_idx, safe_time_str);
            full_path_gs = fullfile(gs_folder, file_name_gs); % 直接使用 PathConfigs 中的路径
            
            T_GS = table(...
                string(GS_Defs(1).Name), string(gs_results(1).SatName), gs_results(1).Dist, ...
                string(GS_Defs(2).Name), string(gs_results(2).SatName), gs_results(2).Dist, ...
                'VariableNames', {'SourceGS', 'SourceSat', 'SourceDist_km', ...
                                  'TargetGS', 'TargetSat', 'TargetDist_km'});
            writetable(T_GS, full_path_gs);
        end
        
        % --- C. 星间链路计算 (Parallel) ---
        results_dist = zeros(totalPairs, 1);
        results_omega = zeros(totalPairs, 1);
        results_visible = false(totalPairs, 1);
        
        parfor k = 1:totalPairs
            idx1 = pairIndices(k, 1);
            idx2 = pairIndices(k, 2);
            
            pos1 = currentSatPositions(idx1, :);
            pos2 = currentSatPositions(idx2, :);
            vel1 = currentSatVelocities(idx1, :);
            vel2 = currentSatVelocities(idx2, :);
            
            d_vec = pos2 - pos1;
            dist = norm(d_vec);
            results_dist(k) = dist;
            
            v_vec = vel2 - vel1;
            omega = norm(cross(d_vec, v_vec)) / (dist^2 + eps);
            results_omega(k) = omega;
            
            isVisible = true;
            t = -dot(pos1, d_vec) / dot(d_vec, d_vec);
            if t > 0 && t < 1
                P_closest = pos1 + t * d_vec;
                if norm(P_closest) < Re
                    isVisible = false;
                end
            end
            results_visible(k) = isVisible;
        end
        
        % --- D. 筛选并保存 ---
        mask = results_visible & (results_dist < current_dist_limit);
        
        visible_dists = results_dist(mask);
        visible_omegas = results_omega(mask);
        visible_idx1 = pairIndices(mask, 1);
        visible_idx2 = pairIndices(mask, 2);
        count = length(visible_dists);
        
        % [保存] Visibility 数据
        if count > 0
            S1_col = satellite_names(visible_idx1)';
            S2_col = satellite_names(visible_idx2)';
            
            T_table = table(S1_col, S2_col, visible_dists, visible_omegas, ...
                'VariableNames', {'Sat1', 'Sat2', 'Distance_km', 'AngularVelocity_rad_s'});
            
            file_name_isl = sprintf('visibility_step%04d_%s.csv', t_idx, safe_time_str);
            full_path_isl = fullfile(vis_folder, file_name_isl); % 直接使用 PathConfigs 中的路径
            writetable(T_table, full_path_isl);
        end
        
    end % End Time Loop
    
    fprintf('>>> 完成 Loop (Limit=%d km). 耗时: %.2f 秒\n', current_dist_limit, toc(loop_timer));

end % End Distance Loop

fprintf('\n========================================\n');
fprintf('全流程结束! 总耗时: %.2f 秒\n', toc(total_batch_timer));
fprintf('结果保存在: %s\n', run_root_folder);
fprintf('========================================\n');