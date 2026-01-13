% =========================================================================
% 卫星网络最短路径规划 (Dijkstra 算法)
% 功能：
% 1. 读取之前的可见性分析结果 (CSV) 构建网络拓扑图
% 2. 使用 Dijkstra 算法计算任意两颗卫星之间的最短跳数和路径
% 3. 可视化路由结果
% =========================================================================

% clear; clc; close all;

%% 1. 配置参数
% 输入文件 (来自上一步的输出)
% 请确保此文件名与您之前生成的 distance_limit 对应
csv_filename = 'Results_Step5s_Limit1500km/appended_visibility_step0121_27_Feb_2025_00_10_00_000000000.csv'; 
% csv_filename = 'Results_Step5s_Limit1500km/visibility_step0001_27_Feb_2025_00_00_00_000000000.csv'; 
% 定义起点和终点卫星名称
% 注意：名称必须存在于 CSV 文件中
startSatName = 'STARLINK_1049';   % 起点卫星
endSatName   = 'STARLINK_544';  % 终点卫星 (建议选一个编号较远的测试跨平面链路)

%% 2. 加载数据与构建图
fprintf('正在读取网络拓扑数据: %s ...\n', csv_filename);

if ~isfile(csv_filename)
    error('未找到文件 %s。\n请先运行 "STK_Parallel_Optimization_With_Engine.m" 生成数据。', csv_filename);
end

% 读取 CSV
linkData = readtable(csv_filename);

% 检查数据是否为空
if isempty(linkData)
    error('CSV 文件为空，没有可用的连接。请检查上一步的距离阈值设置是否过小。');
end

% 构建无向图 (Undirected Graph)
% sat1 和 sat2 是节点，distance_km 是边的权重
% G = graph(linkData.Sat1, linkData.Sat2, linkData.Distance_km);
G = graph(linkData.Sat1, linkData.Sat2, linkData.Capture_Time_ms);

fprintf('网络构建完成。\n');
fprintf('节点数 (卫星): %d\n', numnodes(G));
fprintf('边数 (链路): %d\n', numedges(G));

%% 3. 检查节点是否存在
if findnode(G, startSatName) == 0
    error('起点卫星 "%s" 不在网络拓扑中（可能孤立或名称错误）。', startSatName);
end

if findnode(G, endSatName) == 0
    error('终点卫星 "%s" 不在网络拓扑中（可能孤立或名称错误）。', endSatName);
end

%% 4. 执行最短路径算法 (Dijkstra)
fprintf('\n正在计算从 %s 到 %s 的最短路径...\n', startSatName, endSatName);

% shortestpath 函数在权重非负时默认使用 Dijkstra 算法
[pathNodes, pathDist, edgeIndices] = shortestpath(G, startSatName, endSatName, 'Method', 'positive');

%% 5. 输出结果
if isempty(pathNodes)
    fprintf('警告: 无法到达！从 %s 到 %s 没有连通路径。\n', startSatName, endSatName);
else
    fprintf('--------------------------------------------------\n');
    fprintf('路由计算成功！\n');
    fprintf('--------------------------------------------------\n');
    fprintf('总距离: %.3f km\n', pathDist);
    fprintf('跳数: %d 跳 (经过 %d 颗卫星)\n', length(pathNodes)-1, length(pathNodes));
    fprintf('路径序列:\n');
    
    % 打印详细路径
    for i = 1:length(pathNodes)
        if i == length(pathNodes)
            fprintf('%s\n', pathNodes{i});
        else
            fprintf('%s -> ', pathNodes{i});
            % 为了排版美观，每5个换行
            if mod(i, 5) == 0
                fprintf('\n        ');
            end
        end
    end
end

%% 6. 可视化网络拓扑与路径
figure('Color', 'w', 'Name', 'Satellite Network Routing');

% 绘制整个图
% Force 布局会将连接紧密的节点聚在一起
p = plot(G, 'Layout', 'force'); 
title({'卫星网络路由规划 (Dijkstra)'; ...
       sprintf('路径: %s -> %s (%.0f km)', startSatName, endSatName, pathDist)});
xlabel('拓扑布局 X');
ylabel('拓扑布局 Y');
axis equal;

% 如果找到了路径，进行高亮显示
if ~isempty(pathNodes)
    % 高亮节点
    highlight(p, pathNodes, 'NodeColor', 'r', 'MarkerSize', 6);
    % 高亮连线
    highlight(p, 'Edges', edgeIndices, 'EdgeColor', 'r', 'LineWidth', 2);
    
    % 单独标记起点和终点
    highlight(p, startSatName, 'NodeColor', 'g', 'MarkerSize', 10); % 起点绿色
    highlight(p, endSatName, 'NodeColor', 'b', 'MarkerSize', 10);   % 终点蓝色
    
    legend(p, {'普通链路/卫星', '最短路径', '起点', '终点'}, 'Location', 'best');
else
    legend(p, {'普通链路/卫星'}, 'Location', 'best');
end

% 增强显示效果
p.NodeLabel = {}; % 默认隐藏所有标签，防止太乱
% 只显示路径上的标签
if ~isempty(pathNodes)
    labelNodes = pathNodes; 
    % 获取这些节点的索引
    idx = findnode(G, labelNodes);
    p.NodeLabel(idx) = labelNodes;
end

fprintf('\n可视化已生成。\n');