% =========================================================================
% STK 卫星位置提取工具 (稳定版)
% 功能：
% 1. 建立星座 (Walker)
% 2. 模式A: 提取地固坐标系 (XYZ)
% 3. 模式B: 提取经纬度 (LLA) - 通过提取XYZ后在Matlab内转换实现，防止STK死锁
% =========================================================================

%% 0. 全局设置
clear; clc;
USE_ENGINE = 0;      % 1 = STK Engine (无界面，速度快); 0 = GUI (可见，方便调试)
TimeStep   = 5;      % 时间步长 (秒)

% 定义时间范围 (1小时)
StartTime = '27 Feb 2025 00:00:00.000';
StopTime  = '27 Feb 2025 01:00:00.000';

% ！！！在此处选择输出模式 ！！！
% 1 = 输出 ECEF (X, Y, Z)
% 0 = 输出 LLA (Latitude, Longitude, Altitude)
SELECT_XYZ_LLA = 0; 

% 根据选择定义输出文件名
if SELECT_XYZ_LLA
    outputFileMat = 'SatPositions_Fixed_XYZ.mat';
    outputFileCsv = 'SatPositions_Fixed_XYZ.csv';
else
    outputFileMat = 'SatPositions_LLA.mat';
    outputFileCsv = 'SatPositions_LLA.csv';
end

%% 1. 初始化 STK
fprintf('正在启动 STK...\n');
if USE_ENGINE
    try
        app = actxserver('STKX11.application');
        root = actxserver('AgStkObjects11.AgStkObjectRoot');
        % app.NoGraphics = true; 
    catch ME
        error('无法启动 STK Engine。请检查许可。\n错误: %s', ME.message);
    end
else
    try
        app = actxserver('STK11.application');
        root = app.Personality2;
        app.Visible = true; 
        app.UserControl = true;
    catch ME
        error('无法启动 STK GUI。\n错误: %s', ME.message);
    end
end

%% 2. 重置与创建场景
fprintf('正在初始化场景...\n');
try
    root.CloseScenario(); 
catch
end

scenario = root.Children.New('eScenario', 'Sat_Pos_Extraction');
scenario.SetTimePeriod(StartTime, StopTime);
scenario.StartTime = StartTime;
scenario.StopTime  = StopTime;

if ~USE_ENGINE
    root.ExecuteCommand('BatchGraphics * On');
    root.ExecuteCommand('Animate * Reset');
end

%% 3. 创建星座 (Walker Delta)
P = 24;  % 平面数
N = 66;  % 每面卫星数
% P = 2; N = 10; % 测试用

fprintf('正在创建星座: %d 个平面，每面 %d 星 (共 %d 颗)...\n', P, N, P*N);
satObj = module.sat(); % 需确保 module.sat 类存在

for i = 1:P
    seedName = sprintf('STARLINK_%d', i);
    params = struct();
    params.satelliteName = seedName;
    params.perigeeAlt    = 550;      
    params.apogeeAlt     = 550;      
    params.inclination   = 53;        
    params.argOfPerigee  = 0;        
    params.RAAN          = (i-1) * 360 / P; 
    params.Anomaly       = 0;   
    
    satObj.createSatellite(root, scenario, params);
    
    params_const = struct();
    params_const.seedSatelliteName        = seedName;
    params_const.numPlanes                = 1;    
    params_const.numSatsPerPlane          = N;    
    params_const.interPlanePhaseIncrement = 0;    
    
    satObj.createWalkerConstellation_Delta(root, params_const);
    root.ExecuteCommand(sprintf('Unload / */Satellite/%s', seedName));
end

% 获取所有卫星名称
fprintf('正在整理卫星列表...\n');
sat = module.sat(); 
sat.batchRenameSatellitesInSTK2(root, sat.getSatelliteNames(scenario)); 
satellite_names = sat.getSatelliteNames(scenario);
numSats = length(satellite_names);

%% 4. 数据提取主循环
total_timer = tic;

if SELECT_XYZ_LLA
    %% --- 模式 A: 提取 XYZ ---
    fprintf('模式: ECEF (XYZ)\n');
    fprintf('结果将保存至: %s\n', outputFileCsv);

    AllSatData = struct('Name', {}, 'Time', {}, 'Pos_Fixed_km', {});

    % 写入表头
    fid = fopen(outputFileCsv, 'w');
    if fid == -1, error('无法打开文件 %s', outputFileCsv); end
    fprintf(fid, 'Time_UTC,Satellite_Name,X_km,Y_km,Z_km\n');
    fclose(fid);

    for i = 1:numSats
        satName = satellite_names{i};
        try
            obj = root.GetObjectFromPath(['Satellite/' satName]);
            dp = obj.DataProviders.Item('Vectors(Fixed)').Group.Item('Position');
            res = dp.Exec(StartTime, StopTime, TimeStep);

            x = cell2mat(res.DataSets.GetDataSetByName('x').GetValues);
            y = cell2mat(res.DataSets.GetDataSetByName('y').GetValues);
            z = cell2mat(res.DataSets.GetDataSetByName('z').GetValues);
            time_vals = res.DataSets.GetDataSetByName('Time').GetValues;

            % 存结构体
            AllSatData(i).Name = satName;
            AllSatData(i).Time = time_vals;
            AllSatData(i).Pos_Fixed_km = [x, y, z];

            % 写 CSV
            fid = fopen(outputFileCsv, 'a');
            numRows = length(x);
            for k = 1:numRows
                fprintf(fid, '%s,%s,%.4f,%.4f,%.4f\n', time_vals{k}, satName, x(k), y(k), z(k));
            end
            fclose(fid);

        catch ME
            fprintf('  [警告] 卫星 %s 失败: %s\n', satName, ME.message);
        end
        if mod(i, 50) == 0, fprintf('  已完成: %d/%d (%.2fs)\n', i, numSats, toc(total_timer)); end
    end
    
    save(outputFileMat, 'AllSatData');

else
    %% --- 模式 B: 提取 XYZ 并转换为 LLA ---
    fprintf('模式: LLA (Lat, Lon, Alt)\n');
    fprintf('策略: 提取 XYZ -> Matlab 转换 -> LLA (避免 STK 死锁)\n');
    fprintf('结果将保存至: %s\n', outputFileCsv);

    AllSatData = struct('Name', {}, 'Time', {}, 'LLA', {});

    % 写入表头
    fid = fopen(outputFileCsv, 'w');
    if fid == -1, error('无法打开文件 %s', outputFileCsv); end
    fprintf(fid, 'Time_UTC,Satellite_Name,Latitude_deg,Longitude_deg,Altitude_km\n');
    fclose(fid);

    for i = 1:numSats
        satName = satellite_names{i};
        try
            obj = root.GetObjectFromPath(['Satellite/' satName]);
            
            % [核心技巧] 依然提取 Vectors(Fixed)，因为它最稳定
            dp = obj.DataProviders.Item('Vectors(Fixed)').Group.Item('Position');
            res = dp.Exec(StartTime, StopTime, TimeStep);

            x = cell2mat(res.DataSets.GetDataSetByName('x').GetValues);
            y = cell2mat(res.DataSets.GetDataSetByName('y').GetValues);
            z = cell2mat(res.DataSets.GetDataSetByName('z').GetValues);
            time_vals = res.DataSets.GetDataSetByName('Time').GetValues;

            % [调用转换函数] 在 Matlab 内部计算，速度极快且不卡
            [lat, lon, alt] = ecef2lla_custom(x, y, z);

            % 存结构体
            AllSatData(i).Name = satName;
            AllSatData(i).Time = time_vals;
            AllSatData(i).LLA  = [lat, lon, alt];

            % 写 CSV
            fid = fopen(outputFileCsv, 'a');
            numRows = length(x);
            for k = 1:numRows
                fprintf(fid, '%s,%s,%.6f,%.6f,%.4f\n', time_vals{k}, satName, lat(k), lon(k), alt(k));
            end
            fclose(fid);

        catch ME
            fprintf('  [警告] 卫星 %s 失败: %s\n', satName, ME.message);
        end
        if mod(i, 50) == 0, fprintf('  已完成: %d/%d (%.2fs)\n', i, numSats, toc(total_timer)); end
    end
    
    save(outputFileMat, 'AllSatData');
end

fprintf('\n全部处理完成! 总耗时: %.2f 秒\n', toc(total_timer));


%% =========================================================================
%% 附录：自定义坐标转换函数
%% =========================================================================
function [lat, lon, alt] = ecef2lla_custom(x, y, z)
% ECEF2LLA_CUSTOM 将地固坐标系(ECEF)转换为经纬度(WGS84)
% 输入: x, y, z (单位: km)
% 输出: lat (度), lon (度), alt (km)

    % WGS84 椭球常数 (单位: km)
    a = 6378.137;           % 半长轴
    f = 1 / 298.257223563;  % 扁率
    b = a * (1 - f);        % 半短轴
    e2 = f * (2 - f);       % 第一偏心率平方
    ep2 = (a^2 - b^2) / b^2;% 第二偏心率平方

    % 辅助计算
    p = sqrt(x.^2 + y.^2);
    theta = atan2(z * a, p * b);

    % 计算经度 (弧度 -> 度)
    lon = atan2(y, x) * 180 / pi;

    % 计算纬度 (弧度)
    lat_rad = atan2(z + ep2 * b * sin(theta).^3, ...
                    p - e2 * a * cos(theta).^3);
    lat = lat_rad * 180 / pi;

    % 计算高度 (km)
    N = a ./ sqrt(1 - e2 * sin(lat_rad).^2);
    alt = p ./ cos(lat_rad) - N;
end