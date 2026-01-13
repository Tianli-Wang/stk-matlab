% =========================================================================
% STK 星座路由分析脚本 (基于时间步文件匹配)
% 功能：
% 1. 遍历文件夹中所有的 GS_Route 文件
% 2. 根据文件名自动找到同一时间步对应的 visibility 文件
% 3. 从 GS 文件读取源/目标卫星，从 visibility 文件构建拓扑并计算路由
% =========================================================================

% clear; clc; close all;

%% 1. 参数设置
% 请确保这里的参数与您生成数据时的一致，以便找到正确的文件夹
distance_limit = 2100; 
time_step_val = 5;     

% 自动推断文件夹名称
input_folder = sprintf('Results_Step%ds_Limit%dkm', time_step_val, distance_limit);

if ~exist(input_folder, 'dir')
    error('找不到数据文件夹: %s\n请先运行仿真脚本生成数据。', input_folder);
end

% 获取所有地面站路由文件 (作为主索引)
gs_files = dir(fullfile(input_folder, 'GS_Route_step*.csv'));
num_files = length(gs_files);

fprintf('在文件夹 "%s" 中找到 %d 个时间步数据。\n', input_folder, num_files);
fprintf('准备开始逐帧处理...\n');

%% 2. 逐时间步循环处理
% 预分配结果表
results_summary = table('Size', [num_files, 6], ...
    'VariableTypes', {'double', 'string', 'string', 'string', 'double', 'double'}, ...
    'VariableNames', {'StepID', 'TimeLabel', 'SourceSat', 'TargetSat', 'Hops', 'TotalDist_km'});

% 用于记录最佳路径以便后续画图
best_step_info = struct('idx', 0, 'hops', Inf, 'file_gs', '', 'file_vis', '');

wb = waitbar(0, '正在规划路由...');

for i = 1:num_files
    % --- A. 文件匹配 ---
    gs_filename = gs_files(i).name;
    full_gs_path = fullfile(input_folder, gs_filename);
    
    % 核心逻辑：根据 GS 文件名推导 visibility 文件名
    % 例如: GS_Route_step0001_....csv -> visibility_step0001_....csv
    % 只要去掉 "GS_Route_" 替换为 "visibility_" 即可
    suffix_part = strrep(gs_filename, 'GS_Route_', '');
    vis_filename = ['visibility_' suffix_part]; 
    full_vis_path = fullfile(input_folder, vis_filename);
    
    % 提取时间标签用于记录 (去掉 .csv)
    time_label = regexprep(suffix_part, '\.csv$', '');
    
    % --- B. 读取源/目标卫星 (从 GS 文件) ---
    gs_data = readtable(full_gs_path);
    
    % 确保读取为字符格式，去除潜在空格
    srcSat = strtrim(char(gs_data.SourceSat(1)));
    tgtSat = strtrim(char(gs_data.TargetSat(1)));
    
    % 初始化当前步的结果
    results_summary.StepID(i) = i;
    results_summary.TimeLabel(i) = string(time_label);
    results_summary.SourceSat(i) = string(srcSat);
    results_summary.TargetSat(i) = string(tgtSat);
    
    % --- C. 路由规划 (基于 visibility 文件) ---
    current_hops = NaN;
    current_dist = NaN;
    
    % 只有当两个地面站都连接了卫星，且对应的链路文件存在时，才计算路由
    if ~strcmp(srcSat, 'None') && ~strcmp(tgtSat, 'None') && exist(full_vis_path, 'file')
        
        link_data = readtable(full_vis_path);
        
        if ~isempty(link_data)
            % 1. 构建图 (Sat1, Sat2, Distance)
            G = graph(link_data.Sat1, link_data.Sat2, link_data.Distance_km);
            
            % 2. 检查源/目标卫星是否都在网络中
            if findnode(G, srcSat) > 0 && findnode(G, tgtSat) > 0
                % 3. Dijkstra 最短路径计算
                [pathNodes, pathDist] = shortestpath(G, srcSat, tgtSat, 'Method', 'positive');
                
                if ~isempty(pathNodes)
                    current_hops = length(pathNodes) - 1;
                    current_dist = pathDist;
                    
                    % 记录最佳时刻 (跳数最少)
                    if current_hops < best_step_info.hops
                        best_step_info.idx = i;
                        best_step_info.hops = current_hops;
                        best_step_info.file_gs = full_gs_path;
                        best_step_info.file_vis = full_vis_path;
                    end
                else
                    current_hops = Inf; % 不连通
                    current_dist = Inf;
                end
            else
                current_hops = Inf; % 节点孤立
                current_dist = Inf;
            end
        end
    end
    
    % 填入结果
    results_summary.Hops(i) = current_hops;
    results_summary.TotalDist_km(i) = current_dist;
    
    % 更新进度条
    if mod(i, 10) == 0
        waitbar(i/num_files, wb, sprintf('已处理: %d/%d (Step %d)', i, num_files, i));
    end
end
close(wb);

% 保存汇总结果
summary_file = fullfile(input_folder, 'Routing_Analysis_Summary.csv');
writetable(results_summary, summary_file);
fprintf('批量分析完成。汇总表已保存至: %s\n', summary_file);

%% 3. [可视化] 展示最佳路径时刻的拓扑
% 画出跳数最少的那一刻的路由图

if best_step_info.idx == 0
    warning('未找到任何有效的连通路径，无法绘图。');
else
    fprintf('\n[绘图] 正在可视化最佳路径时刻 (Step %d, Hops: %d)...\n', best_step_info.idx, best_step_info.hops);
    
    % --- 重新读取最佳时刻的数据 ---
    gs_data = readtable(best_step_info.file_gs);
    startSatName = strtrim(char(gs_data.SourceSat(1)));
    endSatName   = strtrim(char(gs_data.TargetSat(1)));
    
    linkData = readtable(best_step_info.file_vis);
    G = graph(linkData.Sat1, linkData.Sat2, linkData.Distance_km);
    
    % --- 计算路径 ---
    [pathNodes, pathDist, edgeIndices] = shortestpath(G, startSatName, endSatName, 'Method', 'positive');
    
    % --- 绘图 ---
    figure('Color', 'w', 'Name', 'Optimal Path Visualization');
    
    % 绘制底图 (灰色节点和边)
    p = plot(G, 'Layout', 'force', 'NodeColor', [0.8 0.8 0.8], 'EdgeColor', [0.9 0.9 0.9], 'MarkerSize', 4); 
    
    title_str = sprintf('Step: %d | Path: %s -> %s\nDist: %.2f km | Hops: %d', ...
        best_step_info.idx, startSatName, endSatName, pathDist, length(pathNodes)-1);
    title(title_str, 'Interpreter', 'none');
    axis equal; box on;
    
    % --- 高亮路径 ---
    if ~isempty(pathNodes)
        % 高亮边 (红色粗线)
        highlight(p, 'Edges', edgeIndices, 'EdgeColor', 'r', 'LineWidth', 2);
        
        % 高亮路径节点 (红色)
        highlight(p, pathNodes, 'NodeColor', 'r', 'MarkerSize', 6);
        
        % 特别标记起点 (绿色五角星) 和 终点 (蓝色六角星)
        highlight(p, startSatName, 'NodeColor', 'g', 'MarkerSize', 12, 'Marker', 'p'); 
        highlight(p, endSatName,   'NodeColor', 'b', 'MarkerSize', 12, 'Marker', 'h'); 
        
        % 只显示路径上的卫星名称
        p.NodeLabel = {}; 
        path_indices = findnode(G, pathNodes);
        p.NodeLabel(path_indices) = pathNodes;
        
        fprintf('最佳路径序列: %s\n', strjoin(pathNodes, ' -> '));
    end
    
    legend({'网络拓扑', '最短路径', '起点 (北京接入)', '终点 (巴西利亚接入)'}, 'Location', 'best');
end

%% 4. 绘制跳数趋势图
figure('Color', 'w', 'Name', 'Hops Analysis');
valid_mask = ~isnan(results_summary.Hops) & ~isinf(results_summary.Hops);

if sum(valid_mask) > 0
    subplot(2,1,1);
    plot(results_summary.StepID(valid_mask), results_summary.Hops(valid_mask), 'b-o', 'MarkerSize', 4);
    ylabel('跳数 (Hops)');
    title('最短路径跳数随时间变化');
    grid on;
    
    subplot(2,1,2);
    plot(results_summary.StepID(valid_mask), results_summary.TotalDist_km(valid_mask), 'r-s', 'MarkerSize', 4);
    xlabel('时间步 (Step ID)');
    ylabel('总距离 (km)');
    title('最短路径总距离随时间变化');
    grid on;
else
    text(0.5, 0.5, '无连通数据', 'HorizontalAlignment', 'center');
end