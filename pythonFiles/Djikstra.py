import pandas as pd
import networkx as nx
import matplotlib.pyplot as plt
import os

# ================= 配置区域 =================
# 输入文件路径（请根据实际情况修改）
# VISIBILITY_FILE = "./Results_Step5s_Limit1000km/appended_visibility_step0001_27_Feb_2025_00_00_00_000000000.csv"
VISIBILITY_FILE = "./Results_Step5s_Limit1000km/visibility_step0001_27_Feb_2025_00_00_00_000000000.csv"
ROUTE_FILE = "./Results_Step5s_Limit1000km/GS_Route_step0001_27_Feb_2025_00_00_00_000000000.csv"

# 输出文件路径
OUTPUT_ROUTES_CSV = "calculated_routes.csv"
OUTPUT_IMAGE_FILE = "route_visualization.png"
# ===========================================

def build_satellite_network(visibility_file):
    """读取可见性矩阵，构建卫星网络拓扑图。"""
    print(f"正在加载网络拓扑: {visibility_file} ...")
    try:
        df = pd.read_csv(visibility_file)
        G = nx.Graph()
        # 批量添加边 (Sat1, Sat2, weight=Distance_km)
        for _, row in df.iterrows():
            G.add_edge(
                row['Sat1'], 
                row['Sat2'], 
                weight=row['Distance_km'],
                # 存储其他属性以备后用
                fou=row.get('FOU_urad', 0),
                status=row.get('Is_Available', True)
            )
        print(f"网络构建完成: {G.number_of_nodes()} 个节点, {G.number_of_edges()} 条边")
        return G
    except FileNotFoundError:
        print(f"错误: 找不到文件 {visibility_file}")
        return None


def process_routing_tasks(route_file, G):
    """读取路由任务文件，计算所有任务的最短路径，返回结果 DataFrame"""
    print(f"\n正在读取路由任务: {route_file} ...")
    try:
        tasks_df = pd.read_csv(route_file)
        results = []
        
        print(f"共找到 {len(tasks_df)} 个路由任务，开始计算...")
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
                task_result['Hops'] = -1  # <--- 【新增】确保失败时也有这个字段
                task_result['Total_Link_Distance_km'] = -1
            else:
                try:
                    # --- Dijkstra 计算 ---
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
                    task_result['Hops'] = -1  # <--- 【新增】确保无路径时也有这个字段
                    task_result['Total_Link_Distance_km'] = -1

            results.append(task_result)

        return pd.DataFrame(results)

    except FileNotFoundError:
        print(f"错误: 找不到文件 {route_file}")
        return pd.DataFrame()
    
    
def visualize_single_route(G, task_row, output_img):
    """可视化单个路由任务"""
    src = task_row['SourceSat']
    tgt = task_row['TargetSat']
    path = task_row['Path_List']
    dist = task_row['Total_ISL_Distance_km']

    if path is None or dist == -1:
        print(f"无法可视化: {src} -> {tgt} 没有有效路径。")
        return

    print(f"\n开始绘制路径可视化: {src} -> {tgt} ...")
    plt.figure(figsize=(15, 10))
    
    # 1. 布局计算 (耗时操作)
    print("正在计算节点布局 (Spring Layout)...")
    # k值调整节点间距，iterations调整迭代次数
    pos = nx.spring_layout(G, k=0.15, iterations=50, seed=42)

    # 2. 绘制背景 (所有节点和边)
    nx.draw_networkx_nodes(G, pos, node_size=20, node_color='lightgray', alpha=0.5)
    nx.draw_networkx_edges(G, pos, width=0.5, edge_color='lightgray', alpha=0.3)

    # 3. 绘制高亮路径
    path_edges = list(zip(path, path[1:]))
    nx.draw_networkx_nodes(G, pos, nodelist=path, node_size=100, node_color='red')
    nx.draw_networkx_edges(G, pos, edgelist=path_edges, width=2.5, edge_color='red')
    
    # 4. 标记起点和终点
    nx.draw_networkx_nodes(G, pos, nodelist=[src], node_size=300, node_color='blue', label='Source')
    nx.draw_networkx_nodes(G, pos, nodelist=[tgt], node_size=300, node_color='green', label='Target')
    
    # 5. 添加标签和标题
    path_labels = {node: node for node in path}
    nx.draw_networkx_labels(G, pos, labels=path_labels, font_size=8, font_color='black', verticalalignment='bottom')
    plt.title(f"Satellite Routing Result (Dijkstra)\n{src} -> {tgt}\nHops: {len(path)-1}, ISL Dist: {dist:.1f} km", fontsize=14)
    plt.legend(['All Nodes', 'Path Nodes', 'Source', 'Target'], loc='upper right')
    plt.axis('off')
    
    # 6. 保存
    plt.savefig(output_img, dpi=300, bbox_inches='tight')
    print(f"可视化图表已保存为: {output_img}")
    # plt.show() # 如果在服务器运行可注释掉此行

# ================= 主程序 =================
if __name__ == "__main__":
    # 检查文件是否存在
    if not os.path.exists(VISIBILITY_FILE) or not os.path.exists(ROUTE_FILE):
        print("错误: 输入文件不存在，请检查路径配置。")
        exit()

    # 1. 构建图
    satellite_graph = build_satellite_network(VISIBILITY_FILE)

    if satellite_graph:
        # 2. 计算所有路由
        routing_results_df = process_routing_tasks(ROUTE_FILE, satellite_graph)
        
        # 3. 保存路由结果 CSV
        if not routing_results_df.empty:
            # 保存前移除 Path_List 列，因为它不适合 CSV
            csv_df = routing_results_df.drop(columns=['Path_List'], errors='ignore')
            csv_df.to_csv(OUTPUT_ROUTES_CSV, index=False)
            print(f"\n所有路由计算完成，结果已保存至: {OUTPUT_ROUTES_CSV}")
            print("前 5 条结果预览:")
            print(csv_df[['SourceSat', 'TargetSat', 'Hops', 'Total_ISL_Distance_km']].head())

            # 4. 可视化第一个成功的任务
            # 找到第一个计算成功的任务 (Total_ISL_Distance_km > 0)
            successful_tasks = routing_results_df[routing_results_df['Total_ISL_Distance_km'] > 0]
            if not successful_tasks.empty:
                first_task = successful_tasks.iloc[0]
                visualize_single_route(satellite_graph, first_task, OUTPUT_IMAGE_FILE)
            else:
                print("\n没有找到任何成功的路由路径，无法进行可视化。")