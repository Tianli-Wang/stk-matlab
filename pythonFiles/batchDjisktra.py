import pandas as pd
import networkx as nx
import matplotlib.pyplot as plt
import os
import glob
import time

# ================= 配置区域 =================
# 输入文件夹路径 (包含 GS_Route 和 visibility 文件的文件夹)
INPUT_FOLDER = "./Results_Step5s_Limit1000km"

# 输出文件夹路径 (脚本会自动创建)
OUTPUT_FOLDER = "./Processed_Routes_Results"

# 文件名前缀定义 (用于匹配文件)
# 路由任务文件前缀
ROUTE_PREFIX = "GS_Route_"
# 可见性文件前缀 (请根据实际情况确认是 'visibility_' 还是 'appended_visibility_')
VISIBILITY_PREFIX = "visibility_" 

# 是否生成可视化图片？(批量处理时建议关闭，否则速度会很慢且占用大量空间)
GENERATE_IMAGES = False 
# ===========================================

def build_satellite_network(visibility_file):
    """读取可见性矩阵，构建卫星网络拓扑图。"""
    # print(f"  -> 正在加载网络拓扑: {os.path.basename(visibility_file)} ...")
    try:
        df = pd.read_csv(visibility_file)
        G = nx.Graph()
        # 批量添加边
        for _, row in df.iterrows():
            G.add_edge(
                row['Sat1'], 
                row['Sat2'], 
                weight=row['Distance_km'],
                fou=row.get('FOU_urad', 0),
                status=row.get('Is_Available', True)
            )
        return G
    except Exception as e:
        print(f"  [Error] 读取可见性文件失败: {e}")
        return None

def process_routing_tasks(route_file, G):
    """读取路由任务文件，计算所有任务的最短路径"""
    try:
        tasks_df = pd.read_csv(route_file)
        results = []
        
        # print(f"  -> 处理 {len(tasks_df)} 个路由任务...")
        for index, row in tasks_df.iterrows():
            src_sat = row['SourceSat']
            tgt_sat = row['TargetSat']
            
            task_result = {
                'SourceGS': row.get('SourceGS', 'N/A'),
                'SourceSat': src_sat,
                'TargetSat': tgt_sat,
                'TargetGS': row.get('TargetGS', 'N/A'),
                'Path_List': None
            }
            
            if not G.has_node(src_sat) or not G.has_node(tgt_sat):
                task_result['Path'] = "Node Not Found"
                task_result['Total_ISL_Distance_km'] = -1
                task_result['Hops'] = -1
                task_result['Total_Link_Distance_km'] = -1
            else:
                try:
                    path = nx.dijkstra_path(G, source=src_sat, target=tgt_sat, weight='weight')
                    dist = nx.dijkstra_path_length(G, source=src_sat, target=tgt_sat, weight='weight')
                    
                    task_result['Path'] = " -> ".join(path)
                    task_result['Path_List'] = path
                    task_result['Hops'] = len(path) - 1
                    task_result['Total_ISL_Distance_km'] = dist
                    task_result['Total_Link_Distance_km'] = dist + row.get('SourceDist_km', 0) + row.get('TargetDist_km', 0)
                except nx.NetworkXNoPath:
                    task_result['Path'] = "No Path"
                    task_result['Total_ISL_Distance_km'] = -1
                    task_result['Hops'] = -1
                    task_result['Total_Link_Distance_km'] = -1

            results.append(task_result)

        return pd.DataFrame(results)

    except Exception as e:
        print(f"  [Error] 读取路由文件失败: {e}")
        return pd.DataFrame()

def visualize_single_route(G, task_row, output_img):
    """可视化单个路由任务 (仅保存不显示)"""
    src = task_row['SourceSat']
    tgt = task_row['TargetSat']
    path = task_row['Path_List']
    
    plt.figure(figsize=(12, 8))
    try:
        pos = nx.spring_layout(G, k=0.15, iterations=30, seed=42) # 减少迭代次数以加快速度
        nx.draw_networkx_nodes(G, pos, node_size=10, node_color='lightgray', alpha=0.5)
        nx.draw_networkx_edges(G, pos, width=0.5, edge_color='lightgray', alpha=0.3)
        
        path_edges = list(zip(path, path[1:]))
        nx.draw_networkx_nodes(G, pos, nodelist=path, node_size=80, node_color='red')
        nx.draw_networkx_edges(G, pos, edgelist=path_edges, width=2.0, edge_color='red')
        
        nx.draw_networkx_nodes(G, pos, nodelist=[src], node_size=200, node_color='blue')
        nx.draw_networkx_nodes(G, pos, nodelist=[tgt], node_size=200, node_color='green')
        
        plt.title(f"{src} -> {tgt} (Dist: {task_row['Total_ISL_Distance_km']:.1f} km)")
        plt.savefig(output_img, dpi=150, bbox_inches='tight')
    except Exception as e:
        print(f"  [Error] 绘图失败: {e}")
    finally:
        plt.close() # 必须关闭，否则内存溢出

# ================= 主程序逻辑 =================
if __name__ == "__main__":
    # 1. 检查输入目录
    if not os.path.exists(INPUT_FOLDER):
        print(f"错误: 输入文件夹 '{INPUT_FOLDER}' 不存在。")
        exit()

    # 2. 创建输出目录
    if not os.path.exists(OUTPUT_FOLDER):
        os.makedirs(OUTPUT_FOLDER)
        print(f"已创建输出文件夹: {OUTPUT_FOLDER}")

    # 3. 搜索所有路由文件
    # 假设文件名格式为: GS_Route_stepXXXX_....csv
    search_pattern = os.path.join(INPUT_FOLDER, f"{ROUTE_PREFIX}*.csv")
    route_files = glob.glob(search_pattern)
    
    if not route_files:
        print(f"在 {INPUT_FOLDER} 中未找到以 {ROUTE_PREFIX} 开头的文件。")
        exit()

    print(f"=== 开始批量处理，共发现 {len(route_files)} 个任务文件 ===\n")
    
    success_count = 0
    start_time = time.time()

    for i, route_path in enumerate(route_files):
        # 获取文件名（不带路径）
        route_filename = os.path.basename(route_path)
        
        # === 核心逻辑：解析后缀并匹配 visibility 文件 ===
        # 提取后缀：将 "GS_Route_" 替换为空，剩下的就是 "stepXXXX_Date_Time..."
        file_suffix = route_filename.replace(ROUTE_PREFIX, "")
        
        # 构造对应的 visibility 文件名
        visibility_filename = f"{VISIBILITY_PREFIX}{file_suffix}"
        visibility_path = os.path.join(INPUT_FOLDER, visibility_filename)
        
        # 构造输出文件名
        output_csv_name = f"Calculated_{file_suffix}"
        output_csv_path = os.path.join(OUTPUT_FOLDER, output_csv_name)
        
        print(f"[{i+1}/{len(route_files)}] 处理: {file_suffix}")
        
        # 检查配对的 visibility 文件是否存在
        if not os.path.exists(visibility_path):
            print(f"  [跳过] 找不到对应的 visibility 文件: {visibility_filename}")
            continue

        # === 执行计算 ===
        # 1. 建图
        G = build_satellite_network(visibility_path)
        if not G:
            continue
            
        # 2. 算路
        result_df = process_routing_tasks(route_path, G)
        
        # 3. 保存结果
        if not result_df.empty:
            save_df = result_df.drop(columns=['Path_List'], errors='ignore')
            save_df.to_csv(output_csv_path, index=False)
            print(f"  -> 结果已保存: {output_csv_name}")
            
            # 4. (可选) 可视化第一个成功路径
            if GENERATE_IMAGES:
                successful = result_df[result_df['Total_ISL_Distance_km'] > 0]
                if not successful.empty:
                    img_name = output_csv_name.replace(".csv", ".png")
                    img_path = os.path.join(OUTPUT_FOLDER, img_name)
                    visualize_single_route(G, successful.iloc[0], img_path)
                    print(f"  -> 图片已保存")
            
            success_count += 1
        else:
            print("  -> 计算结果为空")

    total_time = time.time() - start_time
    print(f"\n=== 处理完成 ===")
    print(f"成功处理文件数: {success_count} / {len(route_files)}")
    print(f"总耗时: {total_time:.2f} 秒")
    print(f"所有结果保存在: {OUTPUT_FOLDER}")