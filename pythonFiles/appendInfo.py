# import pandas as pd
# import numpy as np

# def add_fou(df):
#     """
#     功能：录入 FOU 大小 (单位: urad)
#     目前逻辑：生成 10 到 50 之间的随机数。
#     """
#     num_rows = len(df)
#     # 如果你有真实数据，可以创建一个列表赋值给 df['FOU_urad']
#     # 例如: df['FOU_urad'] = [12.5, 30.1, ...] (长度必须匹配)
#     df['FOU_urad'] = np.random.uniform(10, 50, size=num_rows)
#     print("已录入 FOU 信息")
#     return df

# def add_capture_time(df):
#     """
#     功能：录入 Capture Time (单位: ms)
#     目前逻辑：生成 50 到 200 之间的随机数。
#     """
#     num_rows = len(df)
#     df['Capture_Time_ms'] = np.random.uniform(50, 200, size=num_rows)
#     print("已录入 Capture Time 信息")
#     return df

# def add_capture_probability(df):
#     """
#     功能：录入捕获概率 (归一化 0-1)
#     """
#     num_rows = len(df)
#     df['Capture_Probability'] = np.random.uniform(0, 1, size=num_rows)
#     print("已录入捕获概率")
#     return df

# def add_status(df):
#     """
#     功能：录入当前可用状态 (Boolean)
#     """
#     num_rows = len(df)
#     # 随机生成 True 或 False
#     df['Is_Available'] = np.random.choice([True, False], size=num_rows)
#     print("已录入可用状态")
#     return df

# def main():
#     # 1. 读取 CSV 文件
#     filename = 'visibility_step0001_27_Feb_2025_00_00_00_000000000.csv'
#     try:
#         df = pd.read_csv(filename)
#         print(f"成功读取文件，共 {len(df)} 行数据。")
#     except FileNotFoundError:
#         print(f"错误：找不到文件 {filename}")
#         return

#     # 2. 依次调用函数录入信息
#     df = add_fou(df)
#     df = add_capture_time(df)
#     df = add_capture_probability(df)
#     df = add_status(df)

#     # 3. 打印前 5 行查看结果
#     print("\n处理后的数据预览：")
#     print(df.head())

#     # 4. 保存为新文件
#     output_filename = 'satellite_matrix_python.csv'
#     df.to_csv(output_filename, index=False)
#     print(f"\n文件已保存为: {output_filename}")

# if __name__ == "__main__":
#     main()

import pandas as pd
import numpy as np

def generate_fou_lookup(all_satellites):
    """
    为所有卫星生成固定的 FOU 值
    分布: N(500, 2000) -> 均值=500, 方差=2000 (标准差 ~ 44.72)
    约束: > 0
    """
    fou_lookup = {}
    mu = 500
    sigma = np.sqrt(2000) # 因为 N(mu, sigma^2) 通常指方差
    
    for sat in all_satellites:
        while True:
            # 生成正态分布随机数
            val = np.random.normal(mu, sigma)
            if val > 0: # 确保大于0
                fou_lookup[sat] = val
                break
    return fou_lookup

def generate_fou_lookup_with_outliers(all_satellites, outlier_prob=0.05):
    """
    生成 FOU 查找表，包含部分极大偏差值。
    - 正常卫星: N(500, 2000) (均值500, 标准差~45)
    - 异常卫星: Uniform(1000, 5000) (随机分布在1000到5000之间)
    
    参数:
    - outlier_prob: 出现异常值的概率 (默认 0.05 即 5%)
    """
    fou_lookup = {}
    
    # 正常分布参数
    mu = 500
    sigma = np.sqrt(2000)
    
    outlier_count = 0
    
    for sat in all_satellites:
        # 抛硬币决定这颗卫星是否异常
        if np.random.rand() < outlier_prob:
            # --- 生成极大偏差值 ---
            # 这里设定为 1000 到 5000 之间的随机数
            val = np.random.uniform(1000, 5000)
            outlier_count += 1
        else:
            # --- 生成正常值 ---
            while True:
                val = np.random.normal(mu, sigma)
                if val > 0: break
        
        fou_lookup[sat] = val
        
    print(f"生成的 FOU 查找表: 总卫星数 {len(all_satellites)}, 其中异常值 {outlier_count} 个")
    return fou_lookup

def process_satellite_data(filename):
    # 1. 读取 CSV
    df = pd.read_csv(filename)
    
    # 2. 获取所有唯一的卫星名称 (合并 Sat1 和 Sat2 列)
    # 这样能确保无论卫星出现在哪一列，它都有一个固定的 ID 和 FOU
    unique_sats = pd.unique(df[['Sat1', 'Sat2']].values.ravel('K'))
    print(f"识别到 {len(unique_sats)} 颗唯一的卫星，正在生成 FOU 查找表...")
    
    # 3. 生成 FOU 查找表
    fou_lookup = generate_fou_lookup_with_outliers(unique_sats, outlier_prob=0.05)
    
    # 4. 根据 Sat2 的名字映射 FOU 值
    df['FOU_urad'] = df['Sat2'].map(fou_lookup)
    
    # 5. 生成其他动态参数 (Time, Prob, Status)
    # 这些参数通常取决于链路(Link)，而不是卫星本身，所以保持随机生成
    num_rows = len(df)
    df['Capture_Time_ms'] = np.random.uniform(50, 200, size=num_rows)
    df['Capture_Probability'] = np.random.uniform(0, 1, size=num_rows)
    df['Is_Available'] = np.random.choice([True, False], size=num_rows)
    
    # 6. 调整列顺序: 将 FOU 放在 Distance_km 后面
    cols = list(df.columns)
    if 'Distance_km' in cols:
        # 移除 FOU 并插入到 Distance_km 索引 + 1 的位置
        cols.remove('FOU_urad')
        insert_idx = cols.index('Distance_km') + 1
        cols.insert(insert_idx, 'FOU_urad')
        df = df[cols]
        
    return df, fou_lookup

# --- 执行主程序 ---
filename = './Results_Step5s_Limit1500km/visibility_step0121_27_Feb_2025_00_10_00_000000000.csv'
try:
    final_df, fou_dict = process_satellite_data(filename)
    
    # 保存结果
    output_csv = './Results_Step5s_Limit1500km/appended_visibility_step0121_27_Feb_2025_00_10_00_000000000.csv'
    final_df.to_csv(output_csv, index=False)
    print(f"处理完成！结果已保存为: {output_csv}")
    
    # 可选：保存查找表供检查
    # pd.DataFrame(list(fou_dict.items()), columns=['Sat', 'FOU']).to_csv('fou_lookup.csv', index=False)
    
    print("\n数据预览:")
    print(final_df.head())

except FileNotFoundError:
    print(f"错误: 找不到文件 {filename}")
