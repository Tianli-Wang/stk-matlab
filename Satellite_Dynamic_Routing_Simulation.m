%% =========================================================================
% 卫星网络动态路由仿真 (包含路径节点记录)
% =========================================================================

% clear; clc; close all;

%% 1. 全局配置参数
% --------------------------------------------------------
% 数据源设置
dataDir = './Visibility_Results_Step5s_Limit1500km';                        % CSV 文件所在文件夹
filePattern = 'visibility_step*.csv';  % 文件名匹配模式

% 路由节点设置 (必须存在于 CSV 中)
startSatName = 'STARLINK_1';     % 起点卫星
endSatName   = 'STARLINK_1575';  % 终点卫星

% 物理与惩罚参数
c = 299792.458;          % 光速 (km/s)
setup_delay_ms = 1000;   % [关键参数] 路由切换产生的惩罚 (毫秒)
% --------------------------------------------------------

%% 2. 文件预处理 (搜索与排序)
files = dir(fullfile(dataDir, filePattern));
numFiles = length(files);

if numFiles == 0
    error('未找到任何符合模式 %s 的文件。', filePattern);
end

% 提取 step 数字进行正确排序
fileNames = {files.name};
stepNumbers = zeros(1, numFiles);
for i = 1:numFiles
    tokens = regexp(fileNames{i}, 'step(\d+)', 'tokens');
    if ~isempty(tokens)
        stepNumbers(i) = str2double(tokens{1}{1});
    end
end
[~, sortIdx] = sort(stepNumbers);
sortedFiles = files(sortIdx);

fprintf('共检测到 %d 个时间步文件，准备开始计算。\n', numFiles);

%% 3. 主循环：逐个时间步计算路由
% 初始化存储结构 (已添加 PathNodes 和 PathString)
results = struct('TimeStep', {}, ...
                 'PathDist_km', {}, ...
                 'TotalLatency_ms', {}, ...
                 'SwitchPenalty_ms', {}, ...
                 'IsSwitch', {}, ...
                 'PathNodes', {}, ...      % 原始节点列表 (Cell Array)
                 'PathString', {});        % 可视化路径字符串 (String)

prevPath = {}; 
hWait = waitbar(0, '正在逐帧计算路由...');

for t = 1:numFiles
    % 获取当前文件名
    currentFileName = sortedFiles(t).name;
    fullPath = fullfile(dataDir, currentFileName);
    
    % --- 读取 CSV 数据 ---
    opts = detectImportOptions(fullPath);
    opts.VariableNamingRule = 'preserve';
    linkData = readtable(fullPath, opts);
    
    % --- 数据清洗与类型转换 ---
    try
        if ismember('Sat1', linkData.Properties.VariableNames)
            rawSat1 = linkData.Sat1;
            rawSat2 = linkData.Sat2;
            rawDist = linkData.Distance_km;
        else
            rawSat1 = linkData{:, 2};
            rawSat2 = linkData{:, 3};
            rawDist = linkData{:, 4};
        end
        
        sat1_processed = safe_string_convert(rawSat1);
        sat2_processed = safe_string_convert(rawSat2);
        dist_processed = force_double_convert(rawDist);
        
    catch ME
        warning('Step %d 读取失败: %s', t, ME.message);
        continue;
    end
    
    % --- 构建图与寻路 ---
    G = graph(sat1_processed, sat2_processed, dist_processed);
    
    pathNodes = {};
    pathDist = Inf;
    
    if findnode(G, startSatName) > 0 && findnode(G, endSatName) > 0
        [pathNodes, pathDist] = shortestpath(G, startSatName, endSatName, 'Method', 'positive');
    end
    
    % --- 计算时延与惩罚 ---
    propDelay_ms = 0;
    if ~isinf(pathDist)
        propDelay_ms = (pathDist / c) * 1000;
    end
    
    penalty_ms = 0;
    isSwitch = false;
    
    if t > 1 && ~isempty(pathNodes) && ~isempty(prevPath)
        if ~isequal(pathNodes, prevPath)
            isSwitch = true;
            penalty_ms = setup_delay_ms; 
        end
    end
    
    % --- 保存结果 (在这里添加了节点信息) ---
    results(t).TimeStep = stepNumbers(sortIdx(t));
    results(t).PathDist_km = pathDist;
    results(t).PropDelay_ms = propDelay_ms;
    results(t).SwitchPenalty_ms = penalty_ms;
    results(t).TotalLatency_ms = propDelay_ms + penalty_ms;
    results(t).IsSwitch = isSwitch;
    
    % [新增] 保存详细路径信息
    results(t).PathNodes = pathNodes; 
    if isempty(pathNodes)
        results(t).PathString = "无路径";
    else
        % 将 {'A','B','C'} 转换为 "A -> B -> C" 方便查看
        results(t).PathString = strjoin(pathNodes, ' -> ');
    end
    
    % 更新上一时刻状态
    if ~isempty(pathNodes)
        prevPath = pathNodes;
    end
    
    if mod(t, 20) == 0
        waitbar(t/numFiles, hWait, sprintf('Step %d / %d', t, numFiles));
    end
end
close(hWait);

%% 4. 结果展示
fprintf('\n================ 计算完成 ================\n');
fprintf('总切换次数: %d\n', sum([results.IsSwitch]));

% 打印前5个非空的时间步路径作为示例
fprintf('\n--- 路径示例 (前5个有效步骤) ---\n');
count = 0;
for i = 1:length(results)
    if ~isempty(results(i).PathNodes)
        fprintf('Step %d: %s\n', results(i).TimeStep, results(i).PathString);
        count = count + 1;
        if count >= 5, break; end
    end
end

% 简单的绘图
steps = [results.TimeStep];
latencies = [results.TotalLatency_ms];
switches = [results.IsSwitch];

validIdx = ~isinf(latencies) & latencies > 0;

if any(validIdx)
    figure('Color', 'w');
    plot(steps(validIdx), latencies(validIdx), 'b-'); hold on;
    
    switchSteps = steps(switches);
    switchLatencies = latencies(switches);
    if ~isempty(switchSteps)
        plot(switchSteps, switchLatencies, 'rx', 'MarkerSize', 8, 'LineWidth', 2);
    end
    
    title('动态路由时延分析');
    xlabel('Time Step'); ylabel('Total Latency (ms)');
    legend('Latency', 'Route Switch');
    grid on;
else
    warning('没有找到任何有效路径，无法绘图。');
end


%% 辅助函数
function out = safe_string_convert(in)
    if iscell(in)
        out = in;
        idxNum = cellfun(@isnumeric, out);
        if any(idxNum)
            out(idxNum) = cellfun(@num2str, out(idxNum), 'UniformOutput', false);
        end
    elseif isnumeric(in)
        out = arrayfun(@num2str, in, 'UniformOutput', false);
    else
        out = cellstr(string(in));
    end
    out = strtrim(out);
end

function out = force_double_convert(in)
    if isnumeric(in)
        out = double(in);
    else
        out = str2double(string(in));
    end
end