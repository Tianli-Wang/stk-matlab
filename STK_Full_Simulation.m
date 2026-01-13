% =========================================================================
% STK 并行计算完整版 - 含地面站接入分析 (北京 -> 巴西利亚)
% 功能：
% 1. 建立星座与地面站
% 2. 提取全时段位置数据
% 3. 按时间步输出：
%    - 文件A: 地面站接入情况 (SourceSat, TargetSat)
%    - 文件B: 所有星间链路 (ISL)
% =======================================================================

%% 0. 全局设置
clear; clc;
USE_ENGINE = 0;      % 1 = STK Engine (无界面，快); 0 = GUI (有界面)
distance_limit = 1000; % 星间链路距离阈值 (km)
time_step_val = 5;   % 时间步长 (秒)

% 定义输出文件夹
output_folder = sprintf('Results_Step%ds_Limit%dkm', time_step_val, distance_limit);

% 创建输出文件夹
if ~exist(output_folder, 'dir')
    mkdir(output_folder);
    fprintf('已创建输出文件夹: %s\n', output_folder);
else
    fprintf('输出文件夹已存在: %s\n', output_folder);
end

%% 1. 初始化 STK
if USE_ENGINE
    try
        app = actxserver('STKX11.application');
        root = actxserver('AgStkObjects11.AgStkObjectRoot');
%         app.NoGraphics = true; % 可选：完全关闭图形以极致加速
    catch ME
        error('无法启动 STK Engine。请检查许可。\n错误: %s', ME.message);
    end
else
    try
        app = actxserver('STK11.application');
        root = app.Personality2;
%         app.Visible = true; 
%         app.UserControl = true;
    catch ME
        error('无法启动 STK GUI。\n错误: %s', ME.message);
    end
end

%% 2. 重置与创建场景
fprintf('正在初始化场景...\n');
try
    root.CloseScenario(); % 强行关闭任何已打开的场景
catch ME
    % 如果没有打开的场景,CloseScenario 会报错,忽略这个错误
    fprintf('信息:没有需要关闭的旧场景。\n');
end

StartTime = '27 Feb 2025 00:00:00.000'; 
StopTime  = '27 Feb 2025 01:00:00.000'; % 示例跑1小时

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

%% 3. 创建星座 (Starlink Gen1 Shell 1: Walker Delta)
% 参数定义
P = 72;   % 轨道面数 (Planes)
N = 22;   % 每面卫星数 (Sats per plane)
F = 17;   % 相位因子 (Phasing Parameter)，决定相邻平面卫星的错位程度

% 测试模式开关 (如果不想一次性生成1584颗，可以将此处改为 true)
isTestMode = false; 
if isTestMode
    P = 1; N = 10; % 测试用小规模
    fprintf('!!! 测试模式: 仅生成 %d 个平面 !!!\n', P);
end

TotalSats = 72 * 22; % 注意：计算相位时必须使用真实的满星座总数(1584)，否则相位会错乱
if isTestMode, TotalSats = P * N; end % 测试时使用当前总数

fprintf('正在创建 %d 个平面，每个平面 %d 颗卫星 (F因子=%d)...\n', P, N, F);



for i = 1:P
    % 1. 定义 Seed 卫星名称 (作为生成该平面的种子)
    seedName = sprintf('STARLINK_Seed_Plane%d', i);
    
    params = struct();
    params.satelliteName = seedName;
    params.perigeeAlt    = 550;      
    params.apogeeAlt     = 550;      
    params.inclination   = 53;       
    params.argOfPerigee  = 0;        
    
    % --- 关键修改 1: 升交点赤经 (RAAN) ---
    % 均匀分布在 360 度
    params.RAAN = (i-1) * 360 / P; 
    
    % --- 关键修改 2: 平近点角 (Mean Anomaly) 的相位偏移 ---
    % Walker 星座的核心公式：相邻平面的卫星需要错开一定角度
    % Offset = (PlaneIndex * 360 * F) / TotalSats
    phaseOffset = (i-1) * 360 * F / TotalSats; 
    
    % 确保角度在 0-360 之间
    params.Anomaly = mod(phaseOffset, 360); 
    
    % 2. 创建种子卫星
    % 获取 STK 根对象 (假设 module.sat 内部需要这些，保持你原有的结构)
    satObj = module.sat(); 
    satObj.createSatellite(root, scenario, params);
    
    % 3. 利用 Walker 工具将种子扩展为一个平面
    % 注意：我们在这里是"逐平面"生成，所以 numPlanes = 1
    params_const = struct();
    params_const.seedSatelliteName        = seedName;
    params_const.numPlanes                = 1;         % 每次循环只生成当前这就这一个面
    params_const.numSatsPerPlane          = N;         % 面内卫星数
    params_const.interPlanePhaseIncrement = 0;         % 因为 numPlanes=1，平面间相位在上面 Anomaly 算过了，这里填 0
    
    % 调用你的模块生成星座
    % 假设它会在 STK 中生成名为 STARLINK_Seed_PlaneX_1...N 的卫星
    satObj.createWalkerConstellation_Delta(root, params_const);
    
    % 4. 清理种子卫星
    % 生成完该平面的 22 颗卫星后，删除原本的种子卫星，保持场景整洁
    try
        root.ExecuteCommand(sprintf('Unload / */Satellite/%s', seedName));
    catch
        fprintf('警告: 无法卸载种子卫星 %s\n', seedName);
    end
    
    % 可选：打印进度，因为 72 次循环比较慢
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

%% 4. 创建地面站 (北京 & 巴西利亚)
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
%% [阶段1] 批量提取数据 (卫星 + 地面站)
%% ============================================================ 

fprintf('\n[阶段1] 正在提取所有位置数据...\n');

% 1.1 提取卫星数据
SatDataAll = cell(numSats, 1); 
GlobalTimeStrs = {}; 

ppm_exist = exist('ParforProgressMonitor', 'class');
if ppm_exist, ppm = ParforProgressMonitor(numSats, '提取卫星数据'); end

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
            GlobalTimeStrs = string(time_vals);
        end
    catch
        SatDataAll{i} = [];
    end
    if mod(i, 200) == 0, fprintf('  卫星数据已提取: %d/%d\n', i, numSats); end
end

% 1.2 提取地面站数据
fprintf('正在提取地面站位置数据...\n');
GS_Pos_All = cell(1, 2); 
for k = 1:length(GS_Defs)
    gsObj = root.GetObjectFromPath(['Facility/' GS_Defs(k).Name]);
    % 注意：必须使用 Fixed 坐标系以便与卫星计算距离
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
%% [阶段2] 核心计算循环 (地面站接入 + 星间链路)
%% ============================================================

fprintf('\n[阶段2] 开始时间循环计算...\n');

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
if isempty(poolObj), parpool; end

Re = 6378.137; % 地球半径 km
total_timer = tic;

for t_idx = 1:numTimeSteps
    
    current_time_str = GlobalTimeStrs(t_idx);
    safe_time_str = regexprep(current_time_str, '[:. ]', '_');
    
    fprintf('处理时间步 %d/%d (%s)... ', t_idx, numTimeSteps, current_time_str);
    step_timer = tic;
    
    % --- A. 组装当前时刻卫星位置矩阵 ---
    currentSatPositions = zeros(numSats, 3);
    for i = 1:numSats
        if ~isempty(SatDataAll{i})
            currentSatPositions(i, :) = SatDataAll{i}(t_idx, :);
        else
            currentSatPositions(i, :) = [NaN, NaN, NaN];
        end
    end
    
    % =====================================================================
    % --- B. [新增] 计算地面站最近接入卫星 ---
    % =====================================================================
    gs_results = struct('SatName', {'', ''}, 'Dist', {Inf, Inf});
    
    % 循环处理两个地面站
    for k = 1:2
        % 1. 地面站当前位置
        current_gs_pos = GS_Pos_All{k}(t_idx, :);
        
        % 2. 距离计算
        vec_gs_to_sats = currentSatPositions - current_gs_pos;
        dists_gs_sats = sqrt(sum(vec_gs_to_sats.^2, 2));
        
        % 3. 可见性 (点积 > 0 表示仰角 > 0)
        dot_prods = sum(repmat(current_gs_pos, numSats, 1) .* vec_gs_to_sats, 2);
        is_visible = dot_prods > 0;
        
        % 4. 筛选最近
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
    
    % 保存地面站路由 CSV
    if ~strcmp(gs_results(1).SatName, "None") || ~strcmp(gs_results(2).SatName, "None")
        file_name_gs = sprintf('GS_Route_step%04d_%s.csv', t_idx, safe_time_str);
        full_path_gs = fullfile(output_folder, file_name_gs);
        
        T_GS = table(...
            string(GS_Defs(1).Name), string(gs_results(1).SatName), gs_results(1).Dist, ...
            string(GS_Defs(2).Name), string(gs_results(2).SatName), gs_results(2).Dist, ...
            'VariableNames', {'SourceGS', 'SourceSat', 'SourceDist_km', ...
                              'TargetGS', 'TargetSat', 'TargetDist_km'});
        writetable(T_GS, full_path_gs);
    end
    
    % =====================================================================
    % --- C. 计算星间链路 (ISL) 并行计算 ---
    % =====================================================================
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
    
    % --- D. 筛选并保存 ISL 结果 ---
    mask = results_visible & (results_dist < distance_limit);
    
    visible_dists = results_dist(mask);
    visible_idx1 = pairIndices(mask, 1);
    visible_idx2 = pairIndices(mask, 2);
    count = length(visible_dists);
    
    if count > 0
        T_col = repmat(current_time_str, count, 1);
        S1_col = satellite_names(visible_idx1)';
        S2_col = satellite_names(visible_idx2)';
        D_col = visible_dists;
        
        T_table = table(S1_col, S2_col, D_col, 'VariableNames', {'Sat1', 'Sat2', 'Distance_km'});
        
        file_name_isl = sprintf('visibility_step%04d_%s.csv', t_idx, safe_time_str);
        full_path_isl = fullfile(output_folder, file_name_isl);
        
        writetable(T_table, full_path_isl);
        fprintf('链路: %d条, GS接入: [%s, %s] (耗时 %.2fs)\n', count, gs_results(1).SatName, gs_results(2).SatName, toc(step_timer));
    else
        fprintf('无星间链路, (耗时 %.2fs)\n', toc(step_timer));
    end
end

fprintf('\n全流程处理完成! 总耗时: %.2f 秒\n', toc(total_timer));
fprintf('结果保存在: %s\n', output_folder);


   
%% ============================================================
%% [阶段3] 批量核心计算循环 (地面站接入 + 星间链路)
%% ============================================================
for i = 1:8
   distance_limit = i * 500;
    % 定义输出文件夹
    output_folder = sprintf('Results_Step%ds_Limit%dkm', time_step_val, distance_limit);

    % 创建输出文件夹
    if ~exist(output_folder, 'dir')
        mkdir(output_folder);
        fprintf('已创建输出文件夹: %s\n', output_folder);
    else
        fprintf('输出文件夹已存在: %s\n', output_folder);
    end

    fprintf('\n[阶段2] 开始时间循环计算...\n');

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
    if isempty(poolObj), parpool; end

    Re = 6378.137; % 地球半径 km
    total_timer = tic;

    for t_idx = 1:numTimeSteps

        current_time_str = GlobalTimeStrs(t_idx);
        safe_time_str = regexprep(current_time_str, '[:. ]', '_');

        fprintf('处理时间步 %d/%d (%s)... ', t_idx, numTimeSteps, current_time_str);
        step_timer = tic;

        % --- A. 组装当前时刻卫星位置矩阵 ---
        currentSatPositions = zeros(numSats, 3);
        for i = 1:numSats
            if ~isempty(SatDataAll{i})
                currentSatPositions(i, :) = SatDataAll{i}(t_idx, :);
            else
                currentSatPositions(i, :) = [NaN, NaN, NaN];
            end
        end

        % =====================================================================
        % --- B. [新增] 计算地面站最近接入卫星 ---
        % =====================================================================
        gs_results = struct('SatName', {'', ''}, 'Dist', {Inf, Inf});

        % 循环处理两个地面站
        for k = 1:2
            % 1. 地面站当前位置
            current_gs_pos = GS_Pos_All{k}(t_idx, :);

            % 2. 距离计算
            vec_gs_to_sats = currentSatPositions - current_gs_pos;
            dists_gs_sats = sqrt(sum(vec_gs_to_sats.^2, 2));

            % 3. 可见性 (点积 > 0 表示仰角 > 0)
            dot_prods = sum(repmat(current_gs_pos, numSats, 1) .* vec_gs_to_sats, 2);
            is_visible = dot_prods > 0;

            % 4. 筛选最近
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

        % 保存地面站路由 CSV
        if ~strcmp(gs_results(1).SatName, "None") || ~strcmp(gs_results(2).SatName, "None")
            file_name_gs = sprintf('GS_Route_step%04d_%s.csv', t_idx, safe_time_str);
            full_path_gs = fullfile(output_folder, file_name_gs);

            T_GS = table(...
                string(GS_Defs(1).Name), string(gs_results(1).SatName), gs_results(1).Dist, ...
                string(GS_Defs(2).Name), string(gs_results(2).SatName), gs_results(2).Dist, ...
                'VariableNames', {'SourceGS', 'SourceSat', 'SourceDist_km', ...
                                  'TargetGS', 'TargetSat', 'TargetDist_km'});
            writetable(T_GS, full_path_gs);
        end

        % =====================================================================
        % --- C. 计算星间链路 (ISL) 并行计算 ---
        % =====================================================================
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

        % --- D. 筛选并保存 ISL 结果 ---
        mask = results_visible & (results_dist < distance_limit);

        visible_dists = results_dist(mask);
        visible_idx1 = pairIndices(mask, 1);
        visible_idx2 = pairIndices(mask, 2);
        count = length(visible_dists);

        if count > 0
            T_col = repmat(current_time_str, count, 1);
            S1_col = satellite_names(visible_idx1)';
            S2_col = satellite_names(visible_idx2)';
            D_col = visible_dists;

            T_table = table(S1_col, S2_col, D_col, 'VariableNames', {'Sat1', 'Sat2', 'Distance_km'});

            file_name_isl = sprintf('visibility_step%04d_%s.csv', t_idx, safe_time_str);
            full_path_isl = fullfile(output_folder, file_name_isl);

            writetable(T_table, full_path_isl);
            fprintf('链路: %d条, GS接入: [%s, %s] (耗时 %.2fs)\n', count, gs_results(1).SatName, gs_results(2).SatName, toc(step_timer));
        else
            fprintf('无星间链路, (耗时 %.2fs)\n', toc(step_timer));
        end
    end

    fprintf('\n全流程处理完成! 总耗时: %.2f 秒\n', toc(total_timer));
    fprintf('结果保存在: %s\n', output_folder);

end


%% =========================================================================
%% [新增功能] 4. 可视化 CSV 中的路径链路 (标红)
%% =========================================================================
fprintf('\n[可视化] 正在根据 calculated_routes.csv 绘制红色链路...\n');

% 1. 读取 CSV 文件
% 请确保 'calculated_routes.csv' 在 MATLAB 当前工作目录下
route_file = 'calculated_routes.csv'; 

if exist(route_file, 'file')
    T_route = readtable(route_file);
    
    % --- 循环处理每一条路径 (如果 CSV 有多行) ---
    % 这里默认处理第一行，如果需要全部画出，请保留 for 循环
    for row_idx = 1:height(T_route)
        
        % 获取路径信息
        path_str = char(T_route.Path{row_idx});       % 路径字符串
        source_gs = char(T_route.SourceGS{row_idx});  % 源地面站
        target_gs = char(T_route.TargetGS{row_idx});  % 目标地面站
        source_sat = char(T_route.SourceSat{row_idx});% 入口卫星
        target_sat = char(T_route.TargetSat{row_idx});% 出口卫星
        
        fprintf('  正在绘制路径 %d: %s -> %s\n', row_idx, source_gs, target_gs);

        % 分割字符串获取卫星列表 (分隔符 " -> ")
        sat_list = strsplit(path_str, ' -> ');

        % 定义红色 (STK 中 255 对应 0x0000FF，即红色)
        color_red = 255; 
        line_width = 3; % 线条加粗

        % -----------------------------------------------------------
        % A. 绘制 SourceGS -> SourceSat (源地面站到第一颗卫星)
        % -----------------------------------------------------------
        try
            obj_gs = root.GetObjectFromPath(['Facility/' source_gs]);
            obj_sat = root.GetObjectFromPath(['Satellite/' source_sat]);
            
            % 创建 Access 对象
            access_obj = obj_gs.GetAccessToObject(obj_sat);
            access_obj.ComputeAccess(); % 计算可见性
            
            % 修改图形属性
            access_obj.Graphics.Color = color_red;
            access_obj.Graphics.LineWidth = line_width;
        catch ME
            fprintf('    警告: 无法连接 %s 和 %s (可能名称不匹配)\n', source_gs, source_sat);
        end

        % -----------------------------------------------------------
        % B. 绘制星间链路 (Satellite -> Satellite)
        % -----------------------------------------------------------
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

        % -----------------------------------------------------------
        % C. 绘制 TargetSat -> TargetGS (最后一颗卫星到目标地面站)
        % -----------------------------------------------------------
        try
            obj_sat = root.GetObjectFromPath(['Satellite/' target_sat]);
            obj_gs = root.GetObjectFromPath(['Facility/' target_gs]);
            
            access_obj = obj_sat.GetAccessToObject(obj_gs);
            access_obj.ComputeAccess();
            
            access_obj.Graphics.Color = color_red;
            access_obj.Graphics.LineWidth = line_width;
        catch ME
            fprintf('    警告: 无法连接 %s 和 %s\n', target_sat, target_gs);
        end
    end
    
    fprintf('[可视化] 全部完成！请切换到 STK 3D 窗口查看红色链路。\n');
    
    % 可选：刷新一下 STK 视图
    if ~USE_ENGINE
        root.ExecuteCommand('Graphics * Draw'); 
    end
else
    fprintf('错误: 未找到 %s，无法进行可视化。\n', route_file);
end