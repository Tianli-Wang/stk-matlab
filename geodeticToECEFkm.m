function ecef = geodeticToECEFkm(latDeg, lonDeg, altKm)
%GEODETICTOECEFkm 将大地坐标系(纬度、经度、高程)转换为 ECEF 笛卡尔坐标，单位为 km。
%
% 该函数用于把地面站的地理位置转换到地心地固坐标系(Earth-Centered,
% Earth-Fixed, ECEF)下，便于后续与卫星位置做统一的距离、链路和可见性计算。
%
% 输入参数说明：
%   latDeg : 地理纬度，单位为度。北纬为正，南纬为负。
%   lonDeg : 地理经度，单位为度。东经为正，西经为负。
%   altKm  : 椭球高程，单位为 km。若地面站在海平面附近，可传入 0。
%
% 输出参数说明：
%   ecef   : 1x3 行向量，格式为 [x, y, z]，单位为 km。
%
% 数学模型说明：
%   这里使用 WGS-84 参考椭球参数：
%   - 长半轴 a = 6378.137 km
%   - 扁率   f = 1 / 298.257223563
%   再由扁率计算第一偏心率平方 e^2，用于求解卯酉圈曲率半径 N，
%   最终完成从大地坐标到 ECEF 坐标的标准转换。

% WGS-84 椭球长半轴，单位 km。
a = 6378.137;

% WGS-84 扁率。
f = 1 / 298.257223563;

% 第一偏心率平方。
e2 = f * (2 - f);

% 将角度制纬度、经度转换为弧度制，便于后续三角函数计算。
lat = deg2rad(latDeg);
lon = deg2rad(lonDeg);

% 预先计算常用三角函数值，既便于阅读，也避免重复计算。
sinLat = sin(lat);
cosLat = cos(lat);
sinLon = sin(lon);
cosLon = cos(lon);

% 计算卯酉圈曲率半径 N。
% 该量反映椭球在当前纬度处沿东西方向的局部曲率。
N = a / sqrt(1 - e2 * sinLat^2);

% 按照标准大地坐标 -> ECEF 公式进行转换。
% x、y、z 均以地心为原点，单位保持为 km。
ecef = [ ...
    (N + altKm) * cosLat * cosLon, ...
    (N + altKm) * cosLat * sinLon, ...
    (N * (1 - e2) + altKm) * sinLat ...
];
end
