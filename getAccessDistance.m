USE_ENGINE = 1;

% 初始化 STK
if USE_ENGINE
    % 初始化 STK Engine
    app = actxserver('STKX11.application');
    root = actxserver('AgStkObjects11.AgStkObjectRoot');
else
    % 初始化 STK 应用程序
    app = actxserver('STK11.application');
    root = app.Personality2;
end

%% 重置 STK 场景
fprintf('正在重置 STK 场景,以确保环境干净...\n');
try
    root.CloseScenario(); % 强行关闭任何已打开的场景
catch ME
    % 如果没有打开的场景,CloseScenario 会报错,忽略这个错误
    fprintf('信息:没有需要关闭的旧场景。\n');
end

%% 创建场景并设置时间范围
StartTime = '6 Jan 2025 00:00:00.000';
StopTime = '7 Jan 2025 00:00:00.000';
scenario = root.Children.New('eScenario', 'MATLAB_PredatorMission');
scenario.SetTimePeriod(StartTime, StopTime);
scenario.StartTime = StartTime;
scenario.StopTime = StopTime;

%% 重置动画
try
    root.ExecuteCommand('Animate * Reset');
    disp('动画已复位成功');
catch ME
    disp('动画复位失败:');
    disp(ME.message);
end

%% 星座参数设置
P = 24;  % 轨道平面数量
N = 66;  % 每个平面的卫星数量

%% 创建 Walker 星座
for i = 1:P
    
    % ========================================
    % 1. 设置"种子卫星"参数
    % ========================================
    seedSatelliteName = sprintf('STARLINK_%d', i);
    
    % 轨道与初始状态参数
    params = struct();
    params.satelliteName = seedSatelliteName;
    params.perigeeAlt    = 550;      % km
    params.apogeeAlt     = 550;      % km
    params.inclination   = 53;        % 度
    params.argOfPerigee  = 0;         % 近地点幅角
    params.RAAN          = i * 360 / P;  % 升交点赤经
    params.Anomaly       = i * 4.5;   % 真近点角
    
    % ========================================
    % 2. 创建种子卫星
    % ========================================
    satObj = module.sat(); 
    satObj.createSatellite(root, scenario, params);
    
    % ========================================
    % 3. 定义并创建 Walker 星座
    % ========================================
    params_constellation = struct();
    params_constellation.seedSatelliteName        = seedSatelliteName;
    params_constellation.numPlanes                = 1;    % 轨道平面数量
    params_constellation.numSatsPerPlane          = N;    % 每个平面的卫星数
    params_constellation.interPlanePhaseIncrement = 0;    % 平面间相位增量
    
    satObj.createWalkerConstellation_Delta(root, params_constellation);

    % ========================================
    % 5. 卸载种子卫星
    % ========================================
    unloadCmd = sprintf('Unload / */Satellite/%s', seedSatelliteName);
    root.ExecuteCommand(unloadCmd);
    
end

%% 批量重命名卫星并设置颜色 + 取消显示 Label (修改部分)
sat = module.sat();
satellite_names = sat.getSatelliteNames(scenario);
sat.batchRenameSatellitesInSTK2(root, satellite_names); 
numSats = length(satellite_names);

fprintf('场景中共有 %d 颗卫星\n', numSats);

% ==========================================================
% [新增] 遍历所有卫星，取消显示 Label
% ==========================================================
fprintf('正在取消显示所有卫星的标签...\n');
% 为了提高速度，可以先暂停动画刷新（可选，但推荐）
root.ExecuteCommand('BatchGraphics * On'); 

for k = 1:numSats
    satName = satellite_names{k};
    
    % 1. 关闭 2D 窗口 (Graphics) 中的 Label
    cmd2D = sprintf('Graphics */Satellite/%s Label Show Off', satName);
    try
        root.ExecuteCommand(cmd2D);
    catch
    end
    
    % 2. 关闭 3D 窗口 (VO) 中的 Label
    cmd3D = sprintf('VO */Satellite/%s Label Show Off', satName);
    try
        root.ExecuteCommand(cmd3D);
    catch
    end
end
% 恢复图形刷新
root.ExecuteCommand('BatchGraphics * Off');
% ==========================================================

%% 设置要检查的时间
t_specific = '6 Jan 2025 12:00:00.000'; % 要查询的时刻 (UTC)
tQuery = datenum(t_specific, 'dd mmm yyyy HH:MM:SS.FFF');

fprintf('\n正在计算时刻 %s 的所有卫星对可见性和距离...\n\n', t_specific);

%% 初始化结果存储
visiblePairs = struct('sat1', {}, 'sat2', {}, 'distance_km', {});
pairCount = 0;

paperFunc = module.paperfunction();

%% 遍历所有卫星对
totalPairs = numSats * (numSats - 1) / 2;
processedPairs = 0;

fprintf('开始处理 %d 个卫星对...\n', totalPairs);

for i = 1:numSats
    satName1 = satellite_names{i};
    
    try
        sat1 = root.GetObjectFromPath(['Satellite/' satName1]);
    catch
        fprintf('?? 无法获取卫星 %s\n', satName1);
        continue;
    end
    
    for j = (i+1):numSats
        satName2 = satellite_names{j};
        processedPairs = processedPairs + 1;
        
        if mod(processedPairs, 100) == 0
            fprintf('进度: %d/%d (%.1f%%)\n', processedPairs, totalPairs, ...
                    100*processedPairs/totalPairs);
        end
        
        try
            sat2 = root.GetObjectFromPath(['Satellite/' satName2]);
        catch
            fprintf('?? 无法获取卫星 %s\n', satName2);
            continue;
        end
        
        %% 1. 判断可见性
        hasAccess = false;
        try
            accessObj = sat1.GetAccessToObject(sat2);
            accessObj.ComputeAccess;
            
            dp = accessObj.DataProviders.Item('Access Data');
            res = dp.Exec(StartTime, StopTime);
            
            try
                startTimes = res.DataSets.GetDataSetByName('Start Time').GetValues;
                stopTimes  = res.DataSets.GetDataSetByName('Stop Time').GetValues;
            catch
                try
                    startTimes = res(1).DataSets(1).Values;
                    stopTimes  = res(1).DataSets(2).Values;
                catch
                    continue;
                end
            end
            
            for k = 1:length(startTimes)
                tStart = datenum(startTimes{k}, 'dd mmm yyyy HH:MM:SS.FFF');
                tStop  = datenum(stopTimes{k},  'dd mmm yyyy HH:MM:SS.FFF');
                if (tQuery >= tStart) && (tQuery <= tStop)
                    hasAccess = true;
                    break;
                end
            end
            
        catch ME
            continue;
        end
        
        %% 2. 如果有可见性,计算距离
        if hasAccess
            try
                distance_km = paperFunc.ab_vector_range_at_time(root, satName1, satName2, t_specific);
                
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
    
    results_table = struct2table(visiblePairs);
    writetable(results_table, 'satellite_visibility_distances.csv');
    fprintf('\n结果已保存到 satellite_visibility_distances.csv\n');
    
    figure;
    histogram(distances, 20);
    xlabel('距离 (km)');
    ylabel('卫星对数量');
    title(sprintf('卫星间距离分布 (%s)', t_specific));
    grid on;
end

fprintf('\n处理完成!\n');