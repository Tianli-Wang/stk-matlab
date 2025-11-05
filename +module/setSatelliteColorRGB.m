% function setSatelliteColorRGB(root, satelliteName, R, G, B)
%     % setSatelliteColorRGB - 更改 STK 中指定卫星的颜色 (使用 RGB)
%     %
%     % 参数:
%     %   root - STK 的根对象 (app.Personality2)
%     %   satelliteName - 要更改颜色的卫星名称 (字符串)
%     %   R, G, B - 0 到 255 之间的 RGB 整数值
% 
%     try
%         % 检查 RGB 值范围
%         if R > 255 || G > 255 || B > 255 || R < 0 || G < 0 || B < 0
%             warning('RGB 值必须在 0 到 255 之间。将自动截断。');
%             R = max(0, min(255, round(R)));
%             G = max(0, min(255, round(G)));
%             B = max(0, min(255, round(B)));
%         end
% 
%         % STK Connect 的 SetColor 命令使用 BGR 格式的整数
%         % Color = (Blue * 65536) + (Green * 256) + Red
%         colorValue = sprintf('%03d%03d%03d',R,G,B);
%         
%         % 构建 STK Connect 命令
%         % 格式: Graphics */<Class>/<ObjectName> SetColor #<DecimalColorValue>
%         cmd = sprintf('Graphics */Satellite/%s SetColor %d', satelliteName, str2num(colorValue));
%         
%         % 执行命令
%         root.ExecuteCommand(cmd);
%         
%         fprintf('卫星 "%s" 的颜色已成功设置为 RGB(%d, %d, %d)。\n', satelliteName, R, G, B);
%         
%     catch ME
%         fprintf('设置卫星 "%s" 的颜色时发生错误: %s\n', satelliteName, ME.message);
%     end
% end


function setSatelliteColorRGB(root, satelliteName, R, G, B)
    % setSatelliteColorRGB - 更改 STK 中指定卫星的颜色 (使用 RGB)
    %
    % 参数:
    %   root - STK 的根对象 (app.Personality2)
    %   satelliteName - 要更改颜色的卫星名称 (字符串)
    %   R, G, B - 0 到 255 之间的 RGB 整数值

    try
        % 检查 RGB 值范围
        if R > 255 || G > 255 || B > 255 || R < 0 || G < 0 || B < 0
            warning('RGB 值必须在 0 到 255 之间。将自动截断。');
            R = max(0, min(255, round(R)));
            G = max(0, min(255, round(G)));
            B = max(0, min(255, round(B)));
        end

        % 将 R, G, B 拼接成一个如 '255000000' 的字符串
        % 然后转换为数字 (或者直接在 sprintf 中拼接，如下面 cmd 的构造所示)

        % 构建 STK Connect 命令
        % 格式: Graphics */Satellite/<satelliteName> SetColor %<RRRGGGBBB>
        % 注意：使用 %% 来输出一个实际的 % 符号
        cmd = sprintf('Graphics */Satellite/%s SetColor %%%03d%03d%03d', satelliteName, R, G, B);

        % --- 可选：为了调试，可以显示生成的命令 ---
        % fprintf('执行的命令: %s\n', cmd);

        % 执行命令
        root.ExecuteCommand(cmd);

        fprintf('卫星 "%s" 的颜色已成功设置为 RGB(%d, %d, %d)。\n', satelliteName, R, G, B);

    catch ME
        fprintf('设置卫星 "%s" 的颜色时发生错误: %s\n', satelliteName, ME.message);
        % rethrow(ME); % 如果需要让错误继续向上抛出，取消注释此行
    end
end

