function process_satellite_data()
% 主函数：读取CSV并调用各个处理函数

% 1. 读取原始CSV文件
filename = 'visibility_step0001_27_Feb_2025_00_00_00_000000000.csv';
if isfile(filename)
    satTable = readtable(filename);
    fprintf('成功读取文件，共 %d 行数据。\n', height(satTable));
else
    error('未找到文件: %s', filename);
end

% 2. 调用函数分别录入信息
% 注意：这里我生成了随机数据作为示例，你可以修改函数内部逻辑改为固定值或手动输入

satTable = add_FOU(satTable);           % 添加 FOU (urad)
satTable = add_CaptureTime(satTable);   % 添加 Capture Time (ms)
satTable = add_Probability(satTable);   % 添加 捕获概率 (0-1)
satTable = add_Status(satTable);        % 添加 可用状态 (Boolean)

% 3. 显示前5行结果预览
disp('处理后的数据预览：');
head(satTable, 5);

% 4. 保存为新文件
writetable(satTable, 'satellite_matrix_complete.csv');
fprintf('新矩阵已保存为 satellite_matrix_complete.csv\n');
end

%% 以下是四个功能函数 %%

function tbl = add_FOU(tbl)
% 功能：添加FOU列，单位 urad
% 逻辑：这里假设FOU在 10 到 50 urad 之间随机分布

numRows = height(tbl);
% 生成随机数据 (你可以在这里改为读取外部文件或固定值)
fou_data = 10 + (50-10) * rand(numRows, 1);

% 将列添加到表格中
tbl.FOU_urad = fou_data;
fprintf('已添加 FOU 列。\n');
end

function tbl = add_CaptureTime(tbl)
% 功能：添加Capture Time列，单位 ms
% 逻辑：假设捕获时间在 50ms 到 200ms 之间

numRows = height(tbl);
time_data = 50 + (200-50) * rand(numRows, 1);

tbl.Capture_Time_ms = time_data;
fprintf('已添加 Capture Time 列。\n');
end

function tbl = add_Probability(tbl)
% 功能：添加捕获概率，归一化为1
% 逻辑：生成 0 到 1 之间的随机概率

numRows = height(tbl);
prob_data = rand(numRows, 1);

tbl.Capture_Probability = prob_data;
fprintf('已添加 Capture Probability 列。\n');
end

function tbl = add_Status(tbl)
% 功能：添加当前可用状态，布尔值
% 逻辑：随机生成 true/false

numRows = height(tbl);
% rand > 0.5 生成逻辑值
status_data = rand(numRows, 1) > 0.5;

tbl.Is_Available = logical(status_data); % 强制转换为逻辑类型
fprintf('已添加 Status 列。\n');
end