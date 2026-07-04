# STK-MATLAB 卫星网络仿真

本项目通过 MATLAB 调用 AGI/Ansys STK 11，构建 Walker 卫星星座和地面站场景，批量导出卫星状态，并基于距离与地球遮挡关系计算星间/星地可见链路。项目同时支持完全脱离 STK 的 CSV 离线后处理，便于重复测试不同的链路距离阈值。

## 主要功能

- 创建单层或双层 Walker 卫星星座；
- 配置北京—巴西利亚（`BBS`）或纽约—伦敦（`NLS`）地面站场景；
- 按指定时间范围和步长导出卫星位置、速度及地面站状态；
- 合并各卫星状态为统一 CSV；
- 计算节点间距离、相对速度、相对角速度及可见链路；
- 对多个通信距离阈值进行批量后处理；
- 使用 MATLAB 并行计算工具箱加速链路计算（可关闭）；
- 复用已有状态 CSV，跳过耗时的 STK 建模与导出。

## 环境要求

- Windows；
- MATLAB（建议使用支持 `string`、`datetime`、`readtable` 和 `writetable` 的较新版本）；
- AGI/Ansys STK 11，并安装 STK Object Model/Engine；
- 可用的 STK Engine 或 STK Desktop 许可证；
- MATLAB Parallel Computing Toolbox（可选，用于并行后处理）。

完整仿真通过 Windows COM/ActiveX 调用 `STKX11.application` 或 `STK11.application`，因此不能直接在 macOS 或 Linux 上运行。CSV 离线后处理不依赖 STK。

## 快速开始

1. 在 MATLAB 中将当前目录切换到本项目根目录。
2. 打开 `start_simulation.m`，按需修改 `cfg` 配置。
3. 运行：

```matlab
start_simulation
```

首次验证环境时，建议使用较短时间范围，并设置：

```matlab
% 使用小规模星座进行快速测试，避免首次运行耗时过长
cfg.isTestMode = true;

% 仅导出少量卫星，确认 STK、MATLAB 和输出流程均正常
cfg.MAX_SATS_TO_EXPORT = 20;
```

确认测试成功后，再将 `isTestMode` 设为 `false`、`MAX_SATS_TO_EXPORT` 设为 `inf` 运行完整场景。

## 常用配置

推荐统一在 `start_simulation.m` 中修改参数。

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `USE_ENGINE` | `true` | `true` 使用无界面的 STK Engine；`false` 使用 STK GUI |
| `SHOW_GUI` | `false` | 使用 STK GUI 模式时是否显示界面 |
| `StartTime` | `27 Feb 2025 00:00:00.000` | 仿真开始时间（STK UTCG 格式） |
| `StopTime` | `27 Feb 2025 01:00:00.000` | 仿真结束时间 |
| `time_step_val` | `5` | 状态采样时间步长，单位为秒 |
| `USE_MULTI_LAYER` | `false` | 是否启用多层星座 |
| `GS_SCENARIO` | `'BBS'` | 地面站场景：`BBS` 或 `NLS` |
| `isTestMode` | `false` | 是否缩小星座规模以便测试 |
| `MAX_SATS_TO_EXPORT` | `inf` | 最大状态导出卫星数 |
| `RUN_VISIBILITY_POSTPROCESS` | `true` | 状态导出后是否自动计算可见链路 |
| `distance_limit` | `1000` | 主链路距离上限，单位为 km |
| `distance_limit_batch` | `1000:500:4000` | 需要批量计算的距离上限 |
| `POSTPROCESS_ONLY` | `false` | 是否跳过 STK，仅处理已有 CSV |

### STK Engine 与 GUI

无界面的 Engine 模式通常更适合批量仿真：

```matlab
% 后台运行 STK Engine，完成后自动关闭
cfg.USE_ENGINE = true;
cfg.SHOW_GUI = false;
```

需要观察场景或排查 STK 对象时，可改用 GUI：

```matlab
% 启动并显示 STK Desktop 界面，便于人工检查场景
cfg.USE_ENGINE = false;
cfg.SHOW_GUI = true;
```

## 仅进行 CSV 离线后处理

已有 `satellite_states_combined.csv` 后，可跳过 STK 建模并重新计算不同阈值下的链路：

```matlab
% 启用离线模式，只读取已有状态数据，不创建任何 STK COM 对象
cfg.POSTPROCESS_ONLY = true;

% 指向合并状态 CSV，也可由底层函数读取包含逐星 CSV 的文件夹
cfg.STATE_SOURCE = 'D:\data\satellite_states_combined.csv';

% 设置本次需要评估的链路距离阈值，单位均为 km
cfg.distance_limit = 1000;
cfg.distance_limit_batch = 1000:500:4000;

run_STK_Export_SatelliteStates_CSV(cfg);
```

离线输入至少需要时间、位置和速度字段，程序兼容多种常见列名。推荐使用以下结构：

| 字段 | 含义 |
| --- | --- |
| `Time_UTC` | UTC 时间 |
| `Satellite_Name` | 卫星名称 |
| `X_km`, `Y_km`, `Z_km` | 三维位置，单位为 km |
| `VX_km_s`, `VY_km_s`, `VZ_km_s` | 三维速度，单位为 km/s |

## 输出结果

STK 状态默认导出到项目根目录下的 `ExportedStates/`：

```text
ExportedStates/
└── StateExport_<场景>_Step<步长>s_<时间戳>/
    ├── PerSatellite/                       # 每颗卫星的状态 CSV
    ├── GroundStations/
    │   ├── PerGroundStation/               # 每个地面站的状态 CSV
    │   ├── ground_station_definitions.csv
    │   └── ground_station_states_combined.csv
    ├── RelativeVelocityPairs/              # 可选的卫星对相对速度结果
    ├── satellite_states_combined.csv       # 合并后的卫星状态
    └── export_metadata.mat                 # 本次导出的配置和统计信息
```

可见性后处理默认写入项目上一级的 `OutputFiles/`，主要包含：

```text
OutputFiles/
└── RawDataCSV_<场景>/
    └── Results_Step<步长>s_Limit<阈值>km/
        ├── Visibility_Datas/                # 主距离阈值结果
        └── Visibility_Limit<阈值>km/        # 批量阈值结果
```

每个可见性快照 CSV 主要包含 `Sat1`、`Sat2`、`Distance_km`、`AngularVelocity_rad_s` 和 `RelativeSpeed_km_s`。节点对只有在满足距离上限且未被地球遮挡时才会写入结果。

## 项目结构

| 路径 | 作用 |
| --- | --- |
| `start_simulation.m` | 推荐入口和集中配置文件 |
| `run_STK_Export_SatelliteStates_CSV.m` | STK 建模、状态导出及后处理调度主函数 |
| `STK_Full_Simulation_CSV.m` | 不依赖 STK 的 CSV 可见性后处理 |
| `+module/` | 卫星、地面站、传感器和 STK 操作辅助模块 |
| `TestDatasets/` | 示例可见性结果数据 |
| `demo/` | 角速度、传感器等功能的实验示例 |
| `test/` | 开发和验证脚本 |
| `pythonfile/` | 早期文本格式转换辅助脚本，不属于推荐主流程 |
| `STK_Full_Simulation*.m`、`FinalSTKSimulation.m` | 历史或实验性完整仿真脚本 |

## 常见问题

### 无法启动 STK Engine

确认 STK 11 已正确安装且许可证可用。在 MATLAB 中可分别检查以下 COM 对象能否创建：

```matlab
% 检查无界面的 STK Engine COM 服务是否已注册
app = actxserver('STKX11.application');
root = actxserver('AgStkObjects11.AgStkObjectRoot');
```

如果仅安装了 STK Desktop，可先设置 `USE_ENGINE = false`、`SHOW_GUI = true` 测试 GUI 模式。

### 完整仿真耗时或占用内存过大

卫星数和时间步数会显著影响状态文件规模；可先缩短 `StopTime`、增大 `time_step_val`、启用 `isTestMode` 或限制 `MAX_SATS_TO_EXPORT`。批量阈值也会重复生成结果，调试时建议只保留一个值。

### 并行工具箱不可用

离线函数会尝试建立并行池。没有 Parallel Computing Toolbox 时，可在直接调用后处理函数的配置中设置：

```matlab
% 禁用 parfor 加速，改用普通串行循环完成链路计算
cfg.ENABLE_PARALLEL = false;
```

### 中文注释显示乱码

仓库中部分历史 MATLAB 文件可能使用了不同字符编码。若编辑器显示乱码，请尝试以 UTF-8 或 GBK/GB18030 重新打开；新增和修改文件建议统一保存为 UTF-8。

## 使用提示

- 完整星座会生成大量卫星和时间序列数据，请预留足够的磁盘空间与运行时间；
- 正式运行前先使用测试模式验证许可证、报告样式与输出目录；
- `ExportedStates/` 已在 `.gitignore` 中忽略，仿真结果不会默认提交到 Git；
- 部分历史脚本包含本机绝对路径，新的实验应优先通过 `start_simulation.m` 和配置结构体指定路径；
- 项目当前未提供自动化测试，修改核心几何或导出逻辑后应使用小规模场景核对 CSV 内容。

