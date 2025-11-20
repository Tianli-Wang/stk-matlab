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

%% 10种预定义颜色 (RGB)
colors = [ ...
    255, 0, 0;   % 1. 红色
    0, 255, 0;   % 2. 绿色
    0, 0, 255;   % 3. 蓝色
    255, 255, 0; % 4. 黄色
    0, 255, 255; % 5. 青色
    255, 0, 255; % 6. 洋红
    255, 128, 0; % 7. 橙色
    128, 0, 255; % 8. 紫色
    0, 128, 0;   % 9. 深绿
    255, 192, 203 % 10. 粉色
];
num_colors = size(colors, 1);

%% 星座参数设置
P = 10;  % 轨道平面数量
N = 15;  % 每个平面的卫星数量
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
    params.perigeeAlt    = 1066;      % km
    params.apogeeAlt     = 1066;      % km
    params.inclination   = 89;        % 度
    params.argOfPerigee  = 0;         % 近地点幅角
    params.RAAN          = i * 18;  % 升交点赤经(可按需在循环中改)
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


for i = 1 : P
   % ========================================
    % 4. 为该平面的卫星设置颜色 (新添加)
    % ========================================
    % 假设 createWalkerConstellation_Delta 创建的卫星命名为 QF_i01, QF_i02, ...
    % 其中 i 是平面索引 (1-P), 01-N 是卫星索引
    % i=1  -> QF_101 ... QF_115
    % i=10 -> QF_1001 ... QF_1015
    
    fprintf('正在为平面 %d 的 %d 颗卫星设置颜色...\n', i, N);
    for j = 1:N
        % 确定卫星名称 (STK Walker工具默认命名: SeedName + 01, 02...)
        satName = sprintf('QF_%d', (i-1)*N+j);
        
        rgb = colors(i, :);
        
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



%% 计算两颗卫星之间的距离
paperFunc = module.paperfunction();
satName1 = 'qf_1';  % 替换为您想查询的第一颗卫星 (原: 'QF_1101')
satName2 = 'qf_16';  % 替换为您想查询的第二颗卫星 (原: 'QF_2101')

% t_specific = datetime('10 Nov 2025 12:30:45.000', 'TimeZone', 'UTC', 'InputFormat', 'dd MMM yyyy HH:mm:ss.SSS');

t_specific = '6 Jan 2025 00:00:00.000';
% t_specific = datetime(Time_str, 'InputFormat', 'dd MMM yyyy HH:mm:ss.SSS', 'TimeZone', 'UTC');

disp(['正在计算 ', satName1, ' 与 ', satName2, ' 之间的距离...']);
try
    distance_km = paperFunc.ab_vector_range_at_time(root, satName1, satName2, t_specific);
    
    fprintf('在 %s 时刻:\n', string(t_specific));
    fprintf('卫星 %s 和 %s 之间的距离是: %.3f km\n', sat1, sat2, dist_at_t);
       
    % 绘制您刚刚计算的特定点
    figure; % 创建一个新图窗
	plot(t_specific, distance_km, 'r*', 'MarkerSize', 10, 'DisplayName', '特定时刻');
	hold on;
    legend;
    xlabel('Time');
    ylabel('Distance (km)');
    title('特定时刻的卫星距离');
    grid on;
	hold off;
    
catch ME
    disp(['计算距离时出错: ', ME.message]);
    disp('请确保卫星名称正确,并且 +module/paperfunction.m 已在 MATLAB 路径中。');
end

    % ========================================
    % 5. 绘制距离变化图
    % ========================================
%     figure;
%     plot(time_vec, distance_km);
%     title(['距离: ', satName1, ' to ', satName2], 'Interpreter', 'none');
%     xlabel('时间 (UTC)');
%     ylabel('距离 (km)');  % 幅值单位通常是 km
%     grid on;
    
    % ========================================
    % 6. (可选) 保存数据到文件
    % ========================================
    % 定义保存路径
    % save_path = 'C:\temp\distance_output.txt'; % 请修改为您希望的路径
    % 
    % % 检查目录是否存在
    % save_dir = fileparts(save_path);
    % if ~exist(save_dir, 'dir')
    %     mkdir(save_dir);
    % end
    % 
    % % 创建表格并写入文件
    % data_table = table(time_vec, distance_km, 'VariableNames', {'Time', 'Range_km'});
    % writetable(data_table, save_path, 'Delimiter', '\t');
    % disp(['数据已保存到文件:', save_path]);

% 现在设置特定卫星的颜色
% module.setSatelliteColorRGB(root, 'qf_1', 255, 0, 0);  % 假设卫星被重命名为 qf_1 (红色)
% setSatelliteColor(root, 'qf_2', 'green');            % 假设卫星被重命名为 qf_2 (绿色)

