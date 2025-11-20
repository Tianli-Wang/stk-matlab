


function F = paperfunction
    F.ab_vector_range = @ab_vector_range;
    F.ab_vector_range_at_time = @ab_vector_range_at_time;
    F.is_visible_at_time = @is_visible_at_time;
 
 
   
end

function [t, mag] = ab_vector_range(root, satAName, satBName, timestep)
% AB_VECTOR_RANGE  获取两颗卫星间位移向量 AB 的时间与幅值（距离）
% 用法：
%   [t, mag] = ab_vector_range(root, 'QF_01_17', 'QF_02_17', 1);
% 参数：
%   root      : STK Application 的 Personality2 句柄（如 uiapp.Personality2）
%   satAName  : 源卫星名称（如 'QF_01_17'）
%   satBName  : 目标卫星名称（如 'QF_02_17'）
%   timestep  : (可选) 采样步长，单位秒，默认 1
% 返回：
%   t   : 时间轴（优先 UTC datetime；若 Time 为相对秒，则由 StartTime 推为绝对 datetime）
%   mag : 距离幅值（与 STK Vectors(Fixed) Magnitude 单位一致，常见为 km）

    if nargin < 4 || isempty(timestep), timestep = 1; end

    % —— 取场景与对象 ——
    scenario = root.CurrentScenario;
    satA = root.GetObjectFromPath(['Satellite/' char(satAName)]);
    satB = root.GetObjectFromPath(['Satellite/' char(satBName)]);
    pA   = satA.vgt.Points.Item('Center');
    pB   = satB.vgt.Points.Item('Center');

    % —— 在 A 上创建/复用位移向量（唯一名，避免冲突）——
    vecName = ['AB_' sanitizeName(satAName) '_to_' sanitizeName(satBName)];
    createdHere = false;
    try
        satA.vgt.Vectors.Item(vecName);          % 存在则复用
    catch
        satA.vgt.Vectors.Factory.CreateDisplacementVector(vecName, pA, pB);
        createdHere = true;
    end

    % —— 数据提供器（Fixed 坐标系）——
    dp  = satA.DataProviders.Item('Vectors(Fixed)').Group.Item(vecName);
    res = dp.Exec(scenario.StartTime, scenario.StopTime, timestep);

    % —— 取 Time 与 Magnitude —— 
    tRaw   = res.DataSets.GetDataSetByName('Time').GetValues;
    magRaw = res.DataSets.GetDataSetByName('Magnitude').GetValues;

    % Magnitude -> double 列向量
    if isnumeric(magRaw)
        mag = double(magRaw(:));
    elseif iscell(magRaw)
        mag = cellfun(@double, magRaw(:));
    else
        mag = double(magRaw(:));
    end

    % —— 构造时间轴（自动识别 UTC 字符串/相对秒）——
    fmt1 = 'dd MMM yyyy HH:mm:ss.SSS';
    fmt2 = 'dd MMM yyyy HH:mm:ss';

    if isnumeric(tRaw)
        % 相对场景起点秒数
        secs = double(tRaw(:));
        t0   = tryParseDt(string(scenario.StartTime), fmt1, fmt2);
        t    = t0 + seconds(secs);                 % 绝对时间（UTC）
    else
        % 英文 UTC 字符串
        if iscell(tRaw)
            tVals = string(tRaw(:));
        else
            tVals = string(tRaw(:));
        end
        t = tryParseDt(tVals, fmt1, fmt2);         % 绝对时间（UTC）
    end

    % —— 清理：仅删除本函数新建的临时矢量 —— 
    if createdHere
        try
            satA.vgt.Vectors.Remove(vecName);
        catch
            % 忽略清理失败（通常不会发生）
        end
    end
end


% --- 在 paperfunction.m 文件中，将其添加为另一个本地函数 ---

% -----------------------------------------------------------------
% 新增函数 (用于特定时刻) - 【已更新错误处理】
% -----------------------------------------------------------------
function [distance] = ab_vector_range_at_time(root, satAName, satBName, targetTimeStr)
% AB_VECTOR_RANGE_AT_TIME ... (说明不变) ...
% ... (参数说明不变) ...

    % --- [核心修改] 稳健的输入检查 ---
    if nargin < 4, error('需要 4 个输入参数: root, satAName, satBName, targetTimeStr'); end

    localTimeStr = targetTimeStr; % 复制一份用于操作

    % 1. 检查是否是 Cell 数组
    if iscell(localTimeStr)
        if isempty(localTimeStr)
            error('输入错误: targetTimeStr (cell) 为空。');
        end
        if numel(localTimeStr) > 1
            warning('targetTimeStr (cell) 包含多个值，仅使用第一个值。');
        end
        % [修正] 使用 {} 从 cell 中提取内容
        localTimeStr = localTimeStr{1}; 
    end

    % 2. 检查是否是 String 数组 (区别于 char)
    if isstring(localTimeStr)
         if isempty(localTimeStr)
            error('输入错误: targetTimeStr (string) 为空。');
         end
        if numel(localTimeStr) > 1
            warning('targetTimeStr (string) 包含多个值，仅使用第一个值。');
        end
        % [修正] 使用 () 从 string 数组中提取第一个 string 标量
        localTimeStr = localTimeStr(1);
    end

    % 3. 此时, localTimeStr 应该是 char 或 string scalar. 
    %    最后检查它是否是字符类型
    if ~ischar(localTimeStr) && ~isstring(localTimeStr)
         error('输入错误: targetTimeStr 必须是一个字符串 (string), 字符向量 (char array) 或包含它们的中 cell。');
    end
    % --- [修改结束] ---


    % --- 取对象 (无修改) ---
    satA = root.GetObjectFromPath(['Satellite/' char(satAName)]);
    satB = root.GetObjectFromPath(['Satellite/' char(satBName)]);
    pA = satA.vgt.Points.Item('Center');
    pB = satB.vgt.Points.Item('Center');

    % --- 在 A 上创建/复用位移向量 (无修改) ---
    vecName = ['AB_' sanitizeName(satAName) '_to_' sanitizeName(satBName)];
    createdHere = false;
    try
        satA.vgt.Vectors.Item(vecName); % 存在则复用
    catch
        satA.vgt.Vectors.Factory.CreateDisplacementVector(vecName, pA, pB);
        createdHere = true;
    end

    % ---【核心修改】---
    
    % 1. [已删除]
    
    % 2. 获取数据提供器
    dp = satA.DataProviders.Item('Vectors(Fixed)').Group.Item(vecName);
    
    % 3. [修正] 使用处理过的 localTimeStr, 并用 char() 确保是字符向量
    res = dp.ExecSingle(char(localTimeStr)); 

    % 4. 提取单个幅值
    magRaw = res.DataSets.GetDataSetByName('Magnitude').GetValues;
    distance = double(magRaw{1}); 

    % --- 清理 (无修改) ---
    if createdHere
        try
            satA.vgt.Vectors.Remove(vecName);
        catch
            % 忽略清理失败
        end
    end
end


% -----------------------------------------------------------------
% 【新增函数】检查特定时刻的可见性 (Access)
% -----------------------------------------------------------------
function [isVisible] = is_visible_at_time(root, satAName, targetObjName, targetTimeStr)
% IS_VISIBLE_AT_TIME 检查一个对象到另一个对象在特定时刻是否可见 (有 Access)
%    此版本使用【正确】的瞬时数据提供器 'Access'。
%    它【不】使用 GetAccessToObject。
%
% 用法：
%   t_str = '6 Jan 2025 00:00:00.000';
% ? isVisible = is_visible_at_time(root, 'qf_1', 'qf_16', t_str);
%   isVisible = is_visible_at_time(root, 'qf_1', 'MyFacility', t_str); % 也可用于地面站
%
% 参数：
% ? root ? ? ?  : STK Application 的 Personality2 句柄
% ? satAName ?  : 源卫星名称 (如 'qf_1')
% ? targetObjName : 目标对象名称 (如 'qf_16' 或 'MyFacility')
% ? targetTimeStr : (string 或 char) 您想要求解的特定时刻, 必须是 STK 接受的英文格式
%
% 返回：
% ? isVisible : (logical) true (可见) 或 false (不可见)

    % --- 稳健的输入检查 (无修改) ---
    if nargin < 4, error('需要 4 个输入参数: root, satAName, targetObjName, targetTimeStr'); end
    localTimeStr = targetTimeStr; 
    if iscell(localTimeStr)
        if isempty(localTimeStr), error('输入错误: targetTimeStr (cell) 为空。'); end
        if numel(localTimeStr) > 1, warning('targetTimeStr (cell) 包含多个值，仅使用第一个值。'); end
        localTimeStr = localTimeStr{1}; 
    end
    if isstring(localTimeStr)
         if isempty(localTimeStr), error('输入错误: targetTimeStr (string) 为空。'); end
        if numel(localTimeStr) > 1, warning('targetTimeStr (string) 包含多个值，仅使用第一个值。'); end
        localTimeStr = localTimeStr(1);
    end
    if ~ischar(localTimeStr) && ~isstring(localTimeStr)
         error('输入错误: targetTimeStr 必须是一个字符串 (string), 字符向量 (char array) 或包含它们的中 cell。');
    end
    % --- [检查结束] ---

    % --- 【核心逻辑 - 正确的瞬时 Access 提供器】 ---
    
    % 1. 获取源卫星 (句柄)
    try
        satA = root.GetObjectFromPath(['Satellite/' char(satAName)]);
    catch ME
        error('获取源卫星 "%s" 失败。错误: %s', char(satAName), ME.message);
    end
    
    % 2. 【重要】获取 "Access" 数据提供器 (IAgDataProviderGroup)
    %    并【直接】从中选择目标对象 (IAgDataProvider)
    try
        % 【修正】: 不使用 GetAccessToObject, 不使用 'Access Data'
        %           直接使用 .DataProviders.Item('Access').Item(TargetName)
        %           这才是瞬时提供器, 它有 ExecSingle
        dp = satA.DataProviders.Item('Access').Item(char(targetObjName));
    catch ME
         % 这里的错误很可能是因为 targetObjName 不存在, 
         % 或者它是一个 Facility (需要 'Facility/MyFacility' 完整路径)
         % 我们尝试自动处理 Facility 的情况
         try
             dp = satA.DataProviders.Item('Access').Item(['Satellite/' char(targetObjName)]);
         catch ME2
             error('获取 Access 提供器失败。目标对象 "%s" 作为 Satellite 或 Facility 均无法找到。错误: %s', char(targetObjName), ME2.message);
         end
    end
    
    % 3. 使用 ExecSingle 在单个时间点执行
    %    现在 dp 是一个 IAgDataProvider, 它【有】ExecSingle
    try
        res = dp.ExecSingle(char(localTimeStr)); 
    catch ME
        % 如果这里出错, 通常是时间格式问题
        error('执行 ExecSingle 时出错。可能是时间格式 "%s" 无法被 STK 识别。错误: %s', char(localTimeStr), ME.message);
    end

    % 4. 提取单个布尔值 (Access 状态)
    try
        accessResult = res.DataSets.GetDataSetByName('Access').GetValues;
        val = accessResult{1};
    catch ME
        error('从 Access 报告中提取 "Access" 数据集失败。错误: %s', ME.message);
    end

    % 5. 将 STK 的返回值 (True/False, -1/0, 'True'/'False') 转换为 MATLAB logical
    if isnumeric(val)
        % COM booleans 通常是 0 (False) 或 -1 (True), 但 1 (True) 也可能
        isVisible = (val ~= 0);
    elseif islogical(val)
        % 直接就是 MATLAB logical
        isVisible = val;
    elseif ischar(val) || isstring(val)
        % 字符串 'True' 或 'False'
        isVisible = strcmpi(val, 'True');
    else
        warning('未知的 Access 返回值类型，默认为 false。');
        isVisible = false;
    end
end



% ====== 工具：安全的名称清洗（只留字母数字和下划线） ======
function s = sanitizeName(name)
    s = regexprep(char(name), '[^A-Za-z0-9_]', '_');
end

% ====== 工具：稳健的英文时间解析（显式 Locale） ======
function dt = tryParseDt(strVals, fmt1, fmt2)
    try
        dt = datetime(strVals, 'InputFormat', fmt1, 'TimeZone','UTC', 'Locale','en_US');
    catch
        try
            dt = datetime(strVals, 'InputFormat', fmt2, 'TimeZone','UTC', 'Locale','en_US');
        catch
            try
                dt = datetime(strVals, 'InputFormat', fmt1, 'TimeZone','UTC', 'Locale','en_GB');
            catch
                dt = datetime(strVals, 'InputFormat', fmt2, 'TimeZone','UTC', 'Locale','en_GB');
            end
        end
    end
end
