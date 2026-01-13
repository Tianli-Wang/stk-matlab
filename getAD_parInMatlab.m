% =========================================================================
% STK 并行计算优化脚本 (Engine/GUI 模式整合版) - 时间序列版 (分文件保存)
% 功能：
% 1. 支持切换 Engine/GUI 模式
% 2. 快速建立 Starlink 规模星座
% 3. [优化] 一次性提取所有时间点数据
% 4. [修改] 间隔 5秒 循环计算，并将每个时间步的结果保存为独立的 CSV 文件
% =========================================================================

%% 0. 全局设置
clear; clc;
USE_ENGINE = 1;      % 1 = 使用 STK Engine (无头模式，更快); 0 = 使用 STK GUI (有界面)
distance_limit = 4000; % 距离筛选阈值 (km)
time_step_val = 5;   % 时间步长 (秒)

% [修改] 定义输出文件夹名称
output_folder = sprintf('Visibility_Results_Step%ds_Limit%dkm', time_step_val, distance_limit);

% 创建输出文件夹
if ~exist(output_folder, 'dir')
    mkdir(output_folder);
    fprintf('已创建输出文件夹: %s\n', output_folder);
else
    fprintf('输出文件夹已存在: %s\n', output_folder);
end

%% 1. 初始化 STK
% fprintf('正在初始化 STK (模式: %s)...\n', string(feval(@(x)x{x+1}, USE_ENGINE, {'GUI', 'Engine'})));

if USE_ENGINE
    try
        app = actxserver('STKX11.application');
        root = actxserver('AgStkObjects11.AgStkObjectRoot');
%         app.NoGraphics = true;
    catch ME
        error('无法启动 STK Engine。请确保已安装 STK Engine 许可。\n错误信息: %s', ME.message);
    end
else
    try
        app = actxserver('STK11.application');
        root = app.Personality2;
        app.Visible = true; 
        app.UserControl = true;
    catch ME
        error('无法启动 STK 应用程序。\n错误信息: %s', ME.message);
    end
end

%% 2. 重置与创建场景
fprintf('正在重置场景...\n');
try
    root.CloseScenario(); 
catch
end

% 时间设置
StartTime = '27 Feb 2025 00:00:00.000'; 
% StopTime  = '6 Jan 2025 12:01:00.000'; % 示例：跑10分钟
StopTime  = '27 Feb 2025 01:00:00.000'; % 跑24小时请解开此行

scenario = root.Children.New('eScenario', 'MATLAB_Parallel_Optimization');
scenario.SetTimePeriod(StartTime, StopTime);
scenario.StartTime = StartTime;
scenario.StopTime = StopTime;

if ~USE_ENGINE
    root.ExecuteCommand('BatchGraphics * On');
    root.ExecuteCommand('Animate * Reset');
end

%% 3. 星座参数设置
P = 24;  
N = 66;  
% P = 2; N = 10; % 测试用

fprintf('正在创建 %d 个平面，每个平面 %d 颗卫星 (共 %d 颗)...\n', P, N, P*N);

%% 4. 创建 Walker 星座
satObj = module.sat(); 

for i = 1:P
    seedSatelliteName = sprintf('STARLINK_%d', i);
    
    params = struct();
    params.satelliteName = seedSatelliteName;
    params.perigeeAlt    = 550;      
    params.apogeeAlt     = 550;      
    params.inclination   = 53;       
    params.argOfPerigee  = 0;        
    params.RAAN          = (i-1) * 360 / P; 
    params.Anomaly       = 0;   
    
    satObj.createSatellite(root, scenario, params);
    
    params_constellation = struct();
    params_constellation.seedSatelliteName        = seedSatelliteName;
    params_constellation.numPlanes                = 1;    
    params_constellation.numSatsPerPlane          = N;    
    params_constellation.interPlanePhaseIncrement = 0;    
    
    satObj.createWalkerConstellation_Delta(root, params_constellation);

    % 卸载种子卫星
    root.ExecuteCommand(sprintf('Unload / */Satellite/%s', seedSatelliteName));
end

% 批量重命名
fprintf('正在整理卫星名称...\n');
sat = module.sat();
satellite_original_names = sat.getSatelliteNames(scenario);
sat.batchRenameSatellitesInSTK2(root, satellite_original_names); 
satellite_names = sat.getSatelliteNames(scenario);
numSats = length(satellite_names);

% if ~USE_ENGINE
%     fprintf('正在关闭卫星标签显示 (GUI优化)...\n');
%     for k = 1:numSats
%         satName = satellite_names{k};
%         try
%             root.ExecuteCommand(sprintf('Graphics */Satellite/%s Label Show Off', satName));
%             root.ExecuteCommand(sprintf('VO */Satellite/%s Label Show Off', satName));
%         catch
%         end
%     end
%     root.ExecuteCommand('BatchGraphics * Off'); 
% end

fprintf('场景准备就绪。共 %d 颗卫星。\n', numSats);

%% ============================================================
%% 核心优化：批量提取所有时间点数据
%% ============================================================

fprintf('\n[阶段1] 正在批量提取所有卫星在 %s 到 %s 的位置数据 (步长 %ds)...\n', StartTime, StopTime, time_step_val);

SatDataAll = cell(numSats, 1); 
GlobalTimeStrs = {}; 

% 进度条
ppm_exist = exist('ParforProgressMonitor', 'class');
if ppm_exist
    ppm = ParforProgressMonitor(numSats, '提取位置数据');
end

for i = 1:numSats
    satName = satellite_names{i};
    try
        obj = root.GetObjectFromPath(['Satellite/' satName]);
        dp = obj.DataProviders.Item('Vectors(Fixed)').Group.Item('Position');
        res = dp.Exec(StartTime, StopTime, time_step_val);
        
        x = cell2mat(res.DataSets.GetDataSetByName('x').GetValues);
        y = cell2mat(res.DataSets.GetDataSetByName('y').GetValues);
        z = cell2mat(res.DataSets.GetDataSetByName('z').GetValues);
        
        SatDataAll{i} = [x, y, z];
        
        if i == 1
            time_vals = res.DataSets.GetDataSetByName('Time').GetValues;
            if iscell(time_vals)
                GlobalTimeStrs = string(time_vals);
            else
                GlobalTimeStrs = string(time_vals);
            end
        end
    catch
        SatDataAll{i} = [];
    end
    
    if mod(i, 200) == 0
        fprintf('已提取: %d/%d\n', i, numSats);
    end
end

numTimeSteps = length(GlobalTimeStrs);
fprintf('数据提取完成。共 %d 个时间步。\n', numTimeSteps);

%% ============================================================
%% 核心优化：时间循环 + 并行计算 + [修改] 分文件写入
%% ============================================================

fprintf('\n[阶段2] 开始时间循环计算并分文件保存...\n');

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

% 启动并行池
poolObj = gcp('nocreate');
if isempty(poolObj)
    parpool; 
end

Re = 6378.137; % 地球半径 km

total_timer = tic;

for t_idx = 1:numTimeSteps
    
    current_time_str = GlobalTimeStrs(t_idx);
    fprintf('正在处理时间步 %d/%d (%s)... ', t_idx, numTimeSteps, current_time_str);
    step_timer = tic;
    
    % --- A. 组装当前时刻位置 ---
    currentSatPositions = zeros(numSats, 3);
    for i = 1:numSats
        if ~isempty(SatDataAll{i})
            currentSatPositions(i, :) = SatDataAll{i}(t_idx, :);
        else
            currentSatPositions(i, :) = [NaN, NaN, NaN];
        end
    end
    
    % --- B. 并行计算 ---
    results_dist = zeros(totalPairs, 1);
    results_visible = false(totalPairs, 1);
    
    parfor k = 1:totalPairs
        idx1 = pairIndices(k, 1);
        idx2 = pairIndices(k, 2);
        
        pos1 = currentSatPositions(idx1, :);
        pos2 = currentSatPositions(idx2, :);
        
        dist = norm(pos1 - pos2);
        results_dist(k) = dist;
        
        isVisible = true;
        d = pos2 - pos1;
        t = -dot(pos1, d) / dot(d, d);
        
        if t > 0 && t < 1
            P_closest = pos1 + t * d;
            if norm(P_closest) < Re
                isVisible = false;
            end
        end
        results_visible(k) = isVisible;
    end
    
    % --- C. 筛选与保存 (分文件) ---
    mask = results_visible & (results_dist < distance_limit);
    
    visible_dists = results_dist(mask);
    visible_idx1 = pairIndices(mask, 1);
    visible_idx2 = pairIndices(mask, 2);
    count = length(visible_dists);
    
    if count > 0
        % 1. 构造表格
        T_col = repmat(current_time_str, count, 1);
        S1_col = satellite_names(visible_idx1)';
        S2_col = satellite_names(visible_idx2)';
        D_col = visible_dists;
        
        T_table = table(S1_col, S2_col, D_col, 'VariableNames', {'Sat1', 'Sat2', 'Distance_km'});
        
        % 2. [核心修改] 生成带时间戳的文件名
        % 将时间字符串中的非法字符 (空格, 冒号, 点) 替换为下划线
        % 例如: "6 Jan 2025 12:00:00.000" -> "6_Jan_2025_12_00_00_000"
        safe_time_str = regexprep(current_time_str, '[:. ]', '_');
        
        % 文件名格式: visibility_步骤ID_时间戳.csv
        file_name = sprintf('visibility_step%04d_%s.csv', t_idx, safe_time_str);
        full_file_path = fullfile(output_folder, file_name);
        
        % 3. 写入单独的 CSV 文件
        writetable(T_table, full_file_path);
        
        fprintf('找到 %d 条链路, 已保存至 %s (耗时 %.2fs)\n', count, file_name, toc(step_timer));
    else
        fprintf('无满足条件链路, 跳过保存 (耗时 %.2fs)\n', toc(step_timer));
    end
end

fprintf('\n全流程处理完成! 总耗时: %.2f 秒\n', toc(total_timer));
fprintf('所有结果文件已保存在文件夹: %s\n', output_folder);




%% ============================================================
%% 核心优化：时间循环 + 并行计算 + [修改] 分文件写入
%% ============================================================
for i = 1:8
   %% ============================================================
    %% 核心优化：时间循环 + 并行计算 + [修改] 分文件写入
    %% ============================================================

    fprintf('\n[阶段2] 开始时间循环计算并分文件保存...\n');

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

    % 启动并行池
    poolObj = gcp('nocreate');
    if isempty(poolObj)
        parpool; 
    end

    Re = 6378.137; % 地球半径 km

    total_timer = tic;

    for t_idx = 1:numTimeSteps

        current_time_str = GlobalTimeStrs(t_idx);
        fprintf('正在处理时间步 %d/%d (%s)... ', t_idx, numTimeSteps, current_time_str);
        step_timer = tic;

        % --- A. 组装当前时刻位置 ---
        currentSatPositions = zeros(numSats, 3);
        for i = 1:numSats
            if ~isempty(SatDataAll{i})
                currentSatPositions(i, :) = SatDataAll{i}(t_idx, :);
            else
                currentSatPositions(i, :) = [NaN, NaN, NaN];
            end
        end

        % --- B. 并行计算 ---
        results_dist = zeros(totalPairs, 1);
        results_visible = false(totalPairs, 1);

        parfor k = 1:totalPairs
            idx1 = pairIndices(k, 1);
            idx2 = pairIndices(k, 2);

            pos1 = currentSatPositions(idx1, :);
            pos2 = currentSatPositions(idx2, :);

            dist = norm(pos1 - pos2);
            results_dist(k) = dist;

            isVisible = true;
            d = pos2 - pos1;
            t = -dot(pos1, d) / dot(d, d);

            if t > 0 && t < 1
                P_closest = pos1 + t * d;
                if norm(P_closest) < Re
                    isVisible = false;
                end
            end
            results_visible(k) = isVisible;
        end

        % --- C. 筛选与保存 (分文件) ---
        mask = results_visible & (results_dist < distance_limit);

        visible_dists = results_dist(mask);
        visible_idx1 = pairIndices(mask, 1);
        visible_idx2 = pairIndices(mask, 2);
        count = length(visible_dists);

        if count > 0
            % 1. 构造表格
            T_col = repmat(current_time_str, count, 1);
            S1_col = satellite_names(visible_idx1)';
            S2_col = satellite_names(visible_idx2)';
            D_col = visible_dists;

            T_table = table(S1_col, S2_col, D_col, 'VariableNames', {'Sat1', 'Sat2', 'Distance_km'});

            % 2. [核心修改] 生成带时间戳的文件名
            % 将时间字符串中的非法字符 (空格, 冒号, 点) 替换为下划线
            % 例如: "6 Jan 2025 12:00:00.000" -> "6_Jan_2025_12_00_00_000"
            safe_time_str = regexprep(current_time_str, '[:. ]', '_');

            % 文件名格式: visibility_步骤ID_时间戳.csv
            file_name = sprintf('visibility_step%04d_%s.csv', t_idx, safe_time_str);
            full_file_path = fullfile(output_folder, file_name);

            % 3. 写入单独的 CSV 文件
            writetable(T_table, full_file_path);

            fprintf('找到 %d 条链路, 已保存至 %s (耗时 %.2fs)\n', count, file_name, toc(step_timer));
        else
            fprintf('无满足条件链路, 跳过保存 (耗时 %.2fs)\n', toc(step_timer));
        end
    end

    fprintf('\n全流程处理完成! 总耗时: %.2f 秒\n', toc(total_timer));
    fprintf('所有结果文件已保存在文件夹: %s\n', output_folder);
end
% %% 8. 清理资源
% if USE_ENGINE
%     fprintf('关闭 STK Engine...\n');
%     try
%         root.CloseScenario();
%         delete(root);
%         delete(app);
%     catch
%     end
% end