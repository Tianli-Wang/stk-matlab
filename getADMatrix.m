%% 获取所有卫星名称
sat = module.sat();
satellite_names = sat.getSatelliteNames(scenario);
numSats = length(satellite_names);

fprintf('场景中共有 %d 颗卫星\n', numSats);

%% 设置要检查的时间
t_specific = '6 Jan 2025 12:00:00.000'; % 要查询的时刻 (UTC)
tQuery = datenum(t_specific, 'dd mmm yyyy HH:MM:SS.FFF');

fprintf('\n正在计算时刻 %s 的所有卫星对可见性和距离...\n\n', t_specific);

%% 初始化结果存储
% 结构体数组存储所有有可见性的卫星对
visiblePairs = struct('sat1', {}, 'sat2', {}, 'distance_km', {});
pairCount = 0;

% 初始化 paperfunction 对象(用于距离计算)
paperFunc = module.paperfunction();

%% 遍历所有卫星对
totalPairs = numSats * (numSats - 1) / 2;
processedPairs = 0;

fprintf('开始处理 %d 个卫星对...\n', totalPairs);

for i = 1:numSats
    satName1 = satellite_names{i};
    
    % 获取第一颗卫星对象
    try
        sat1 = root.GetObjectFromPath(['Satellite/' satName1]);
    catch
        fprintf('?? 无法获取卫星 %s\n', satName1);
        continue;
    end
    
    for j = (i+1):numSats  % 只计算 i < j 的对,避免重复
        satName2 = satellite_names{j};
        processedPairs = processedPairs + 1;
        
        % 每处理100对输出一次进度
        if mod(processedPairs, 100) == 0
            fprintf('进度: %d/%d (%.1f%%)\n', processedPairs, totalPairs, ...
                    100*processedPairs/totalPairs);
        end
        
        % 获取第二颗卫星对象
        try
            sat2 = root.GetObjectFromPath(['Satellite/' satName2]);
        catch
            fprintf('?? 无法获取卫星 %s\n', satName2);
            continue;
        end
        
        %% 1. 判断可见性
        hasAccess = false;
        try
            % 创建 Access 对象
            accessObj = sat1.GetAccessToObject(sat2);
            accessObj.ComputeAccess;
            
            % 获取访问数据
            dp = accessObj.DataProviders.Item('Access Data');
            res = dp.Exec(StartTime, StopTime);
            
            % 提取访问窗口
            try
                % COM对象形式
                startTimes = res.DataSets.GetDataSetByName('Start Time').GetValues;
                stopTimes  = res.DataSets.GetDataSetByName('Stop Time').GetValues;
            catch
                % 结构体形式
                try
                    startTimes = res(1).DataSets(1).Values;
                    stopTimes  = res(1).DataSets(2).Values;
                catch
                    % 无法解析,跳过这对卫星
                    continue;
                end
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
            
        catch ME
            fprintf('?? 计算 %s 和 %s 的可见性时出错: %s\n', ...
                    satName1, satName2, ME.message);
            continue;
        end
        
        %% 2. 如果有可见性,计算距离
        if hasAccess
            try
                distance_km = paperFunc.ab_vector_range_at_time(root, satName1, satName2, t_specific);
                
                % 保存结果
                pairCount = pairCount + 1;
                visiblePairs(pairCount).sat1 = satName1;
                visiblePairs(pairCount).sat2 = satName2;
                visiblePairs(pairCount).distance_km = distance_km;
                
                fprintf('? %s <-> %s: 距离 = %.3f km\n', ...
                        satName1, satName2, distance_km);
                
            catch ME
                fprintf('?? 计算 %s 和 %s 的距离时出错: %s\n', ...
                        satName1, satName2, ME.message);
            end
        end
    end
end

%% 输出统计结果
fprintf('\n========== 统计结果 ==========\n');
fprintf('分析时刻: %s\n', t_specific);
fprintf('总卫星数: %d\n', numSats);
fprintf('总卫星对数: %d\n', totalPairs);
fprintf('有可见性的卫星对数: %d (%.2f%%)\n', pairCount, 100*pairCount/totalPairs);

if pairCount > 0
    distances = [visiblePairs.distance_km];
    fprintf('\n距离统计:\n');
    fprintf('  最小距离: %.3f km\n', min(distances));
    fprintf('  最大距离: %.3f km\n', max(distances));
    fprintf('  平均距离: %.3f km\n', mean(distances));
    fprintf('  中位数距离: %.3f km\n', median(distances));
    
    %% 可选: 保存结果到文件
    results_table = struct2table(visiblePairs);
    writetable(results_table, 'satellite_visibility_distances.csv');
    fprintf('\n结果已保存到 satellite_visibility_distances.csv\n');
    
    %% 可选: 绘制距离分布直方图
    figure;
    histogram(distances, 20);
    xlabel('距离 (km)');
    ylabel('卫星对数量');
    title(sprintf('卫星间距离分布 (%s)', t_specific));
    grid on;
end

fprintf('\n处理完成!\n');