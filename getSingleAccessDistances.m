app = actxserver('STK11.application');
root = app.Personality2;

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
% P = 3;
% N = 36;

%% 创建 Walker 星座
for i = 1:P
    
    % ========================================
    % 1. 设置"种子卫星"参数
    % ========================================
    % 为了区分不同循环生成的卫星,给种子卫星起一个带下标的名字
    seedSatelliteName = sprintf('QF_%d', i);
    
    % 轨道与初始状态参数
    params = struct();
    params.satelliteName = seedSatelliteName;
    params.perigeeAlt    = 550;      % km
    params.apogeeAlt     = 550;      % km
    params.inclination   = 53;        % 度
    params.argOfPerigee  = 0;         % 近地点幅角
    params.RAAN          = i * 360 / P;  % 升交点赤经(可按需在循环中改)
    params.Anomaly       = i * 4.5;   % 真近点角(或平近点角)
    
    % ========================================
    % 2. 创建种子卫星
    % ========================================
    satObj = module.sat();  % 您自定义的 sat 类
    satObj.createSatellite(root, scenario, params);
    
    % ========================================
    % 3. 定义并创建 Walker 星座
    % ========================================
    % 这里设置1个轨道面、每面N颗卫星,不分面间相位增量
    params_constellation = struct();
    params_constellation.seedSatelliteName       = seedSatelliteName;
    params_constellation.numPlanes               = 1;    % 轨道平面数量
    params_constellation.numSatsPerPlane         = N;    % 每个平面的卫星数
    params_constellation.interPlanePhaseIncrement = 0;    % 平面间相位增量(此处为0)
    
    satObj.createWalkerConstellation_Delta(root, params_constellation);

    % ========================================
    % 5. 卸载种子卫星 (原第4步)
    % ========================================
    % 由于 Walker 星座已创建完,可以删除原先的种子卫星
    unloadCmd = sprintf('Unload / */Satellite/%s', seedSatelliteName);
    root.ExecuteCommand(unloadCmd);
    
end

% 批量重命名卫星并设置颜色
sat = module.sat();
satellite_names = sat.getSatelliteNames(scenario);
sat.batchRenameSatellitesInSTK2(root, satellite_names);  % 假设您使用了这个重命名函数


% 1. 定义您想要的 P 种颜色的数量

% 2. 使用 hsv(P) 生成 P x 3 的矩阵 (0-1 范围)
colors_normalized = hsv(P);

% 3. [您需要的一步] 
%    将 0-1 范围 转换为 0-255 范围, 并转为整数
colors_rgb_255 = uint8(colors_normalized * 255);

for i = 1 : P

    
    fprintf('正在为平面 %d 的 %d 颗卫星设置颜色...\n', i, N);
    for j = 1:N
        % 确定卫星名称 (STK Walker工具默认命名: SeedName + 01, 02...)
        satName = sprintf('QF_%d', (i-1)*N+j);
        
        rgb = colors_rgb_255(i, :);
        
        % 调用用户模块设置颜色
        try
            % 假设 module.setSatelliteColorRGB 是一个可以访问的静态方法或在路径中
            module.setSatelliteColorRGB(root, satName, rgb(1), rgb(2), rgb(3));
        catch ME_color
            fprintf('警告: 无法为 %s 设置颜色. 错误: %s\n', satName, ME_color.message);
            % 注意: 如果 setSatelliteColorRGB 是 satObj 的一个方法,
            % 您应使用: satObj.setSatelliteColorRGB(root, satName, rgb(1), rgb(2), rgb(3));
        end
    end
end


%% 指定被查询的两颗卫星名称（替换为你场景中的对象名）
satName1 = 'QF_1';  % 将此处改成你的卫星对象名
satName2 = 'QF_2';

% 取得卫星对象（GetObjectFromPath）：路径通常为 '/Satellite/<name>' 或 'Satellite/<name>'
try
    sat1 = root.GetObjectFromPath(['Satellite/' satName1]);
    sat2 = root.GetObjectFromPath(['Satellite/' satName2]);
catch
    error('无法找到指定的卫星对象，请确认名称和场景中对象路径是否正确。');
end


%% 获取两卫星之间的 Access 对象并计算访问
try
    accessObj = sat1.GetAccessToObject(sat2);
catch
    error('创建 access 对象失败（GetAccessToObject）。请确认对象类型正确并能建立访问。');
end

try
    accessObj.ComputeAccess;
catch
    % 如果接口没有 ComputeAccess，可能是即时计算，不影响后续 IsAccess 调用
end

dp = accessObj.DataProviders.Item('Access Data');
res = dp.Exec(StartTime, StopTime);

%% === 尝试提取访问窗口（兼容不同版本） ===
try
    % 情况1：COM对象形式
    startTimes = res.DataSets.GetDataSetByName('Start Time').GetValues;
    stopTimes  = res.DataSets.GetDataSetByName('Stop Time').GetValues;
    disp('use COM')
catch
    % 情况2：结构体/单元格
    try
        startTimes = res(1).DataSets(1).Values;
        stopTimes  = res(1).DataSets(2).Values;
    catch
        disp('? 无法解析 Access Data 结果。请运行以下命令查看结构：');
        disp('disp(class(res)); disp(res);');
        return
    end
end

%% === 设置要检查的时间 ===
% targetTimeStr = '2025-1-6 12:00:00.000'; % 你要查询的时刻（UTC）
t_specific = '6 Jan 2025 12:00:00.000'; % ← 你要查询的时刻 (UTC)

% 将时间字符串转换为 datenum（STK 时间格式通常兼容）
tQuery = datenum(t_specific, 'dd mmm yyyy HH:MM:SS.FFF');

hasAccess = false;
for k = 1:length(startTimes)
    tStart = datenum(startTimes{k}, 'dd mmm yyyy HH:MM:SS.FFF');
    tStop  = datenum(stopTimes{k},  'dd mmm yyyy HH:MM:SS.FFF');
    if (tQuery >= tStart) && (tQuery <= tStop)
        hasAccess = true;
        fprintf('? 在 %s 时，两颗卫星有 access。\n', t_specific);
        fprintf('   当前访问窗口: %s  →  %s\n', startTimes{k}, stopTimes{k});
        break;
    end
end

if ~hasAccess
    fprintf('? 在 %s 时，两颗卫星没有 access。\n', t_specific);
end

if hasAccess
    fprintf('在给定时刻（EpSec = %g）两卫星之间存在 access。\n', epochEpSec);
else
    fprintf('在给定时刻（EpSec = %g）两卫星之间**没有** access。\n', epochEpSec);
end

paperFunc = module.paperfunction();

% t_specific = datetime('10 Nov 2025 12:30:45.000', 'TimeZone', 'UTC', 'InputFormat', 'dd MMM yyyy HH:mm:ss.SSS');

t_specific = '6 Jan 2025 12:00:00.000';
% t_specific = datetime(Time_str, 'InputFormat', 'dd MMM yyyy HH:mm:ss.SSS', 'TimeZone', 'UTC');

disp(['正在计算 ', satName1, ' 与 ', satName2, ' 之间的距离...']);
try
    distance_km = paperFunc.ab_vector_range_at_time(root, satName1, satName2, t_specific);
    
    fprintf('在 %s 时刻:\n', string(t_specific));
    fprintf('卫星 %s 和 %s 之间的距离是: %.3f km\n', satName1, satName2, distance_km);
    
catch ME
    disp(['计算距离时出错: ', ME.message]);
    disp('请确保卫星名称正确,并且 +module/paperfunction.m 已在 MATLAB 路径中。');
end

% %% 2) 列出可用的 DataProviders（帮助找到“Access intervals”等数据提供器名称）
% fprintf('\n可用的 DataProviders（sat1->sat2 accessObj）：\n');
% dpCollection = accessObj.DataProviders;  % Access 对象也有 DataProviders 集合
% for i=1:dpCollection.Count
%     try
%         dp = dpCollection.Item(i-1); % COM 索引通常从 0 开始
%         fprintf('  [%d] %s\n', i, dp.Name);
%     catch
%         % 有些版本可能用 dpCollection.Item(i)
%         try
%             dp = dpCollection.Item(i);
%             fprintf('  [%d] %s\n', i, dp.Name);
%         catch
%             % 跳过
%         end
%     end
% end


% %% 3) 如果想获取 access 窗口（intervals），常见做法：使用名为 "Access Interval" 或类似的 DataProvider
% % 下面演示通用调用方式（Exec），传入开始/结束时间获得表格（table）结果
% % 先取场景的起止时间以作为查询区间（也可以自定义）
% try
%     scenStart = sc.StartTime; % 可能是字符串或数值（视你的场景设置）
%     scenStop  = sc.StopTime;
% catch
%     % 如果不可用，给定一个合理的区间
%     scenStart = epochEpSec - 3600; % 1 小时前（EpSec）
%     scenStop  = epochEpSec + 3600; % 1 小时后
% end
% 
% % 尝试查找可能的 provider 名称（常见如 "Access Intervals", "Access Data", "Access"）
% candidateNames = {'Access Intervals','Access Interval','Access Data','Access','Access Time','Intervals'};
% 
% found = false;
% for k = 1:length(candidateNames)
%     try
%         prov = accessObj.DataProviders.Item(candidateNames{k});
%         % Exec 的参数签名在不同版本可能不同：常见 (start, stop) 或 (start, stop, step)
%         accessTable = prov.Exec(scenStart, scenStop);
%         % 如果成功执行并返回 table，则打印
%         fprintf('\n使用 DataProvider "%s" 获取的 access 窗口结果：\n', candidateNames{k});
%         % accessTable 结构在 MATLAB 中通常是 COM table，对其列出行列数据：
%         try
%             for r = 0:accessTable.RowCount-1
%                 rowStr = '';
%                 for c = 0:accessTable.ColumnCount-1
%                     val = accessTable.GetValue(r,c);
%                     rowStr = sprintf('%s\t%s', rowStr, num2str(val));
%                 end
%                 disp(rowStr);
%             end
%         catch
%             % 有时返回的是 struct 或 cell，直接显示
%             disp(accessTable);
%         end
%         found = true;
%         break;
%     catch
%         % 忽略失败，继续尝试下一个名字
%     end
% end
% 
% if ~found
%     fprintf('\n未能用常见名字直接取得 access 窗口。请参考上面列出的 DataProviders 名称，并用其中一个名称去调用 .Exec(start,stop)。\n');
% end
% 
% %% 小提示：如何把 EpSec 与人类时间互转（若需要）
% % 有些 STK 版本提供转换工具；如果没有，你也可以在 MATLAB 里用 datetime:
% % 假设 epochEpSec 是自 1970-01-01 UTC 的秒数：
% try
%     dt = datetime(epochEpSec,'ConvertFrom','posixtime','TimeZone','UTC');
%     fprintf('EpSec %g 对应 UTC 时间：%s\n', epochEpSec, datestr(dt,'yyyy-mm-dd HH:MM:SS'));
% catch
%     % 忽略
% end
% 
% %% 结束
% fprintf('\n完成检查。\n');

