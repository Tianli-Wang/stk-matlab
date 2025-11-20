%% 指定目标卫星
targetSatName = 'QF_20';  % ← 修改为你要查询的卫星名称
targetSat = root.GetObjectFromPath(['Satellite/' targetSatName]);

%% 获取所有卫星名称
sat = module.sat();
satellite_names = sat.getSatelliteNames(scenario);
numSats = length(satellite_names);

% 移除目标卫星自己
otherSats = satellite_names(~strcmp(satellite_names, targetSatName));
numOtherSats = length(otherSats);

fprintf('目标卫星: %s\n', targetSatName);
fprintf('场景中其他卫星数量: %d\n', numOtherSats);

%% 设置要检查的时间
t_specific = '6 Jan 2025 12:00:00.000'; % 要查询的时刻 (UTC)
tQuery = datenum(t_specific, 'dd mmm yyyy HH:MM:SS.FFF');

fprintf('\n正在计算时刻 %s 的可见性和距离...\n\n', t_specific);

%% 初始化结果数组
satName_list = cell(numOtherSats, 1);
hasAccess_list = false(numOtherSats, 1);
distance_list = nan(numOtherSats, 1);

fprintf('开始串行计算...\n');
tic;

%% 串行计算目标卫星与所有其他卫星的关系
for idx = 1:numOtherSats
    otherSatName = otherSats{idx};
    satName_list{idx} = otherSatName;
    
    hasAccess = false;
    distance_km = NaN;
    
    try
        % 在循环内获取每个“其他”卫星的对象
        otherSat = root.GetObjectFromPath(['Satellite/' otherSatName]);
        
        %% 1. 判断可见性
        accessObj = targetSat.GetAccessToObject(otherSat);
        accessObj.ComputeAccess;
        
        dp = accessObj.DataProviders.Item('Access Data');
        res = dp.Exec(StartTime, StopTime);
        
        % 提取访问窗口
        try
            startTimes = res.DataSets.GetDataSetByName('Start Time').GetValues;
            stopTimes  = res.DataSets.GetDataSetByName('Stop Time').GetValues;
        catch
            % 兼容旧版或无数据时的回退
            if isstruct(res) && isfield(res, 'DataSets')
                startTimes = res.DataSets(1).Values;
                stopTimes  = res.DataSets(2).Values;
            else
                % 没有访问窗口
                startTimes = {};
                stopTimes = {};
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
        
        %% 2. 如果有可见性,计算距离
        if hasAccess
            % 使用之前创建的 paperFunc 实例
            distance_km = paperFunc.ab_vector_range_at_time(...
                root, targetSatName, otherSatName, t_specific);
        end
        
    catch ME
        % 在串行模式下, 打印错误信息以便调试
        fprintf('!! 卫星 %s 处理失败: %s (在第 %d 行)\n', ...
                otherSatName, ME.message, ME.stack(1).line);
    end
    
    hasAccess_list(idx) = hasAccess;
    distance_list(idx) = distance_km;
    
    % 进度提示(每50个输出一次)
    if mod(idx, 50) == 0 || idx == numOtherSats
        fprintf('已处理: %d/%d (%.1f%%)\n', idx, numOtherSats, ...
                100*idx/numOtherSats);
    end
end

elapsedTime = toc;
fprintf('串行计算完成! 用时: %.2f 秒\n\n', elapsedTime);

%% 整理结果
visibleMask = hasAccess_list & ~isnan(distance_list);
visibleCount = sum(visibleMask);

% 创建结果结构体
allResults = struct(...
    'satellite', satName_list, ...
    'hasAccess', num2cell(hasAccess_list), ...
    'distance_km', num2cell(distance_list));

% 只有可见性的结果
visibleResults = struct(...
    'satellite', satName_list(visibleMask), ...
    'distance_km', num2cell(distance_list(visibleMask)));

%% 输出统计结果
fprintf('========== 统计结果 ==========\n');
fprintf('目标卫星: %s\n', targetSatName);
fprintf('分析时刻: %s\n', t_specific);
fprintf('其他卫星总数: %d\n', numOtherSats);
fprintf('有可见性的卫星数: %d (%.2f%%)\n', visibleCount, 100*visibleCount/numOtherSats);
fprintf('无可见性的卫星数: %d (%.2f%%)\n', numOtherSats-visibleCount, ...
        100*(numOtherSats-visibleCount)/numOtherSats);
fprintf('处理速度: %.1f 卫星/秒\n', numOtherSats/elapsedTime);

%% 距离统计
if visibleCount > 0
    distances = distance_list(visibleMask);
    fprintf('\n距离统计:\n');
    fprintf('  最小距离: %.3f km\n', min(distances));
    fprintf('  最大距离: %.3f km\n', max(distances));
    fprintf('  平均距离: %.3f km\n', mean(distances));
    fprintf('  中位数距离: %.3f km\n', median(distances));
    
    % 按距离排序,显示最近的10颗卫星
    [sortedDist, sortIdx] = sort(distances);
    fprintf('\n最近的10颗可见卫星:\n');
    numToShow = min(10, visibleCount);
    visibleSatNames = satName_list(visibleMask);
    for k = 1:numToShow
        fprintf('  %2d. %s: %.3f km\n', k, ...
                visibleSatNames{sortIdx(k)}, sortedDist(k));
    end
    
    % 显示最远的5颗卫星
    if visibleCount > 5
        fprintf('\n最远的5颗可见卫星:\n');
        for k = 1:min(5, visibleCount)
            fprintf('  %2d. %s: %.3f km\n', k, ...
                    visibleSatNames{sortIdx(end-k+1)}, sortedDist(end-k+1));
        end
    end
    
    %% 保存结果到文件
    % 保存所有结果(包括无可见性的)
    allResults_table = struct2table(allResults);
    filename_all = sprintf('%s_all_satellites_%s.csv', ...
                           targetSatName, datestr(now, 'yyyymmdd_HHMMSS'));
    writetable(allResults_table, filename_all);
    fprintf('\n所有结果已保存到: %s\n', filename_all);
    
    % 只保存有可见性的结果
    visibleResults_table = struct2table(visibleResults);
    filename_visible = sprintf('%s_visible_satellites_%s.csv', ...
                               targetSatName, datestr(now, 'yyyymmdd_HHMMSS'));
    writetable(visibleResults_table, filename_visible);
    fprintf('可见卫星结果已保存到: %s\n', filename_visible);
    
    %% 可视化
    figure('Position', [100, 100, 1200, 500]);
    
    % 子图1: 距离分布直方图
    subplot(1, 2, 1);
    histogram(distances, 30, 'FaceColor', [0.2 0.6 0.8]);
    xlabel('距离 (km)', 'FontSize', 12);
    ylabel('卫星数量', 'FontSize', 12);
    title(sprintf('%s 可见卫星距离分布', targetSatName), 'FontSize', 14);
    grid on;
    
    % 子图2: 可见性比例饼图
    subplot(1, 2, 2);
    pie([visibleCount, numOtherSats-visibleCount], ...
        {sprintf('可见 (%d, %.1f%%)', visibleCount, 100*visibleCount/numOtherSats), ...
         sprintf('不可见 (%d, %.1f%%)', numOtherSats-visibleCount, ...
                 100*(numOtherSats-visibleCount)/numOtherSats)});
    title(sprintf('%s 卫星可见性统计', targetSatName), 'FontSize', 14);
    
    % 保存图片
    figname = sprintf('%s_analysis_%s.png', targetSatName, datestr(now, 'yyyymmdd_HHMMSS'));
    saveas(gcf, figname);
    fprintf('可视化图表已保存到: %s\n', figname);
    
else
    fprintf('\n?? 在指定时刻,目标卫星与所有其他卫星都没有可见性!\n');
end

fprintf('\n处理完成!\n');