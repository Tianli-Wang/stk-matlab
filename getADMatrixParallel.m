%% 获取所有卫星名称
sat = module.sat();
satellite_names = sat.getSatelliteNames(scenario);
numSats = length(satellite_names);

fprintf('场景中共有 %d 颗卫星\n', numSats);

%% 设置要检查的时间
t_specific = '6 Jan 2025 12:00:00.000'; % 要查询的时刻 (UTC)
tQuery = datenum(t_specific, 'dd mmm yyyy HH:MM:SS.FFF');

fprintf('\n正在计算时刻 %s 的所有卫星对可见性和距离...\n\n', t_specific);

%% 准备卫星对列表
totalPairs = numSats * (numSats - 1) / 2;
pairIndices = zeros(totalPairs, 2);
pairIdx = 0;
for i = 1:numSats
    for j = (i+1):numSats
        pairIdx = pairIdx + 1;
        pairIndices(pairIdx, :) = [i, j];
    end
end

fprintf('开始并行处理 %d 个卫星对...\n', totalPairs);

%% 初始化并行池
poolObj = gcp('nocreate');
if isempty(poolObj)
    fprintf('正在启动并行池...\n');
    poolObj = parpool('local');
end
fprintf('使用 %d 个工作线程\n', poolObj.NumWorkers);

%% 并行计算所有卫星对
% 初始化结果数组
satName1_list = cell(totalPairs, 1);
satName2_list = cell(totalPairs, 1);
hasAccess_list = false(totalPairs, 1);
distance_list = nan(totalPairs, 1);

% 显示进度
fprintf('正在并行计算...\n');
tic;

% 使用 parfor 并行循环
parfor pairIdx = 1:totalPairs
    i = pairIndices(pairIdx, 1);
    j = pairIndices(pairIdx, 2);
    
    satName1 = satellite_names{i};
    satName2 = satellite_names{j};
    
    satName1_list{pairIdx} = satName1;
    satName2_list{pairIdx} = satName2;
    
    hasAccess = false;
    distance_km = NaN;
    
    try
        % 每个worker需要自己的 STK 连接
        app_worker = actxserver('STK11.application');
        root_worker = app_worker.Personality2;
        
        % 获取卫星对象
        sat1 = root_worker.GetObjectFromPath(['Satellite/' satName1]);
        sat2 = root_worker.GetObjectFromPath(['Satellite/' satName2]);
        
        % 判断可见性
        accessObj = sat1.GetAccessToObject(sat2);
        accessObj.ComputeAccess;
        
        dp = accessObj.DataProviders.Item('Access Data');
        res = dp.Exec(StartTime, StopTime);
        
        % 提取访问窗口
        try
            startTimes = res.DataSets.GetDataSetByName('Start Time').GetValues;
            stopTimes  = res.DataSets.GetDataSetByName('Stop Time').GetValues;
        catch
            startTimes = res(1).DataSets(1).Values;
            stopTimes  = res(1).DataSets(2).Values;
        end
        
        % 检查指定时刻是否在访问窗口内
        for k = 1:length(startTimes)
            tStart = datenum(startTimes{k}, 'dd mmm yyyy HH:MM:SS.FFF');
            tStop  = datenum(stopTimes{k},  'dd mmm yyyy HH:MM:SS.FFF');
            if (tQuery >= tStart) && (tQuery <= tStop)
                hasAccess = true;
                break;
            end
        end
        
        % 如果有可见性,计算距离
        if hasAccess
            paperFunc_worker = module.paperfunction();
            distance_km = paperFunc_worker.ab_vector_range_at_time(...
                root_worker, satName1, satName2, t_specific);
        end
        
    catch ME
        % 并行中的错误不输出,只记录结果
    end
    
    hasAccess_list(pairIdx) = hasAccess;
    distance_list(pairIdx) = distance_km;
    
    % 进度提示(每1000个输出一次)
    if mod(pairIdx, 1000) == 0
        fprintf('已处理: %d/%d (%.1f%%)\n', pairIdx, totalPairs, ...
                100*pairIdx/totalPairs);
    end
end

elapsedTime = toc;
fprintf('并行计算完成! 用时: %.2f 秒\n', elapsedTime);

%% 整理结果
visibleMask = hasAccess_list & ~isnan(distance_list);
pairCount = sum(visibleMask);

visiblePairs = struct(...
    'sat1', satName1_list(visibleMask), ...
    'sat2', satName2_list(visibleMask), ...
    'distance_km', num2cell(distance_list(visibleMask)));

fprintf('\n========== 统计结果 ==========\n');
fprintf('分析时刻: %s\n', t_specific);
fprintf('总卫星数: %d\n', numSats);
fprintf('总卫星对数: %d\n', totalPairs);
fprintf('有可见性的卫星对数: %d (%.2f%%)\n', pairCount, 100*pairCount/totalPairs);
fprintf('处理速度: %.1f 对/秒\n', totalPairs/elapsedTime);

if pairCount > 0
    distances = distance_list(visibleMask);
    fprintf('\n距离统计:\n');
    fprintf('  最小距离: %.3f km\n', min(distances));
    fprintf('  最大距离: %.3f km\n', max(distances));
    fprintf('  平均距离: %.3f km\n', mean(distances));
    fprintf('  中位数距离: %.3f km\n', median(distances));
    
    % 显示前10个有可见性的卫星对
    fprintf('\n前10个有可见性的卫星对:\n');
    numToShow = min(10, pairCount);
    for k = 1:numToShow
        fprintf('  %s <-> %s: %.3f km\n', ...
                visiblePairs(k).sat1, visiblePairs(k).sat2, ...
                visiblePairs(k).distance_km);
    end
    
    %% 保存结果到文件
    results_table = struct2table(visiblePairs);
    writetable(results_table, 'satellite_visibility_distances.csv');
    fprintf('\n结果已保存到 satellite_visibility_distances.csv\n');
    
    %% 绘制距离分布直方图
    figure;
    histogram(distances, 20);
    xlabel('距离 (km)');
    ylabel('卫星对数量');
    title(sprintf('卫星间距离分布 (%s)', t_specific));
    grid on;
end

fprintf('\n处理完成!\n');