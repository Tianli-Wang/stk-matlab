import pandas as pd
import networkx as nx
import matplotlib.pyplot as plt
import os
import heapq  # <--- 新增引入：用于优先队列

# ================= 配置区域 =================
# 输入文件路径
VISIBILITY_FILE = "./Results_Step5s_Limit1500km/appended_visibility_step0121_27_Feb_2025_00_10_00_000000000.csv"
ROUTE_FILE = "./Results_Step5s_Limit1500km/GS_Route_step0121_27_Feb_2025_00_10_00_000000000.csv"

# 输出文件路径
OUTPUT_ROUTES_CSV = "calculated_bottleneck_routes.csv" # 修改文件名以示区别
OUTPUT_IMAGE_FILE = "bottleneck_route_visualization.png"
# ===========================================

def build_satellite_network(visibility_file):
    """读取可见性矩阵，构建卫星网络拓扑图。"""
    print(f"正在加载网络拓扑: {visibility_file} ...")
    try:
        df = pd.read_csv(visibility_file)
        G = nx.Graph()
        # 批量添加边 (Sat1, Sat2, weight=Distance_km)
        # 注意：这里的 'weight' 现在被视为"捕获时间"或"瓶颈代价"
        for _, row in df.iterrows():
            G.add_edge(
                row['Sat1'], 
                row['Sat2'], 
                weight=row['Distance_km'], 
                fou=row.get('FOU_urad', 0),
                status=row.get('Is_Available', True)
            )
        print(f"网络构建完成: {G.number_of_nodes()} 个节点, {G.number_of_edges()} 条边")
        return G
    except FileNotFoundError:
        print(f"错误: 找不到文件 {visibility_file}")
        return None

# ================= 新增核心算法函数 =================
def get_minimax_path(G, source, target, weight_key='weight'):
    """
    修改版 Dijkstra：寻找瓶颈路径 (Minimax Path)。
    优化目标优先级：
    1. 路径上的最大边权 (Bottleneck) 最小。
    2. 在瓶颈相同的情况下，跳数 (Hops) 最少。
    """
    # 存储到达每个节点的最佳状态: (当前瓶颈值, 当前跳数)
    # 初始化为无穷大
    best_stats = {node: (float('inf'), float('inf')) for node in G.nodes()}
    best_stats[source] = (0, 0)
    
    # 优先队列存储: (瓶颈值, 跳数, 当前节点)
    # Python 的元组比较机制会自动先比瓶颈，再比跳数
    pq = [(0, 0, source)]
    
    # 用于回溯路径: predecessors[child] = parent
    predecessors = {source: None}
    
    while pq:
        curr_bottleneck, curr_hops, u = heapq.heappop(pq)
        
        # 如果找到目标，因为是优先队列，这一定是符合条件的最优解
        if u == target:
            break
            
        # 剪枝：如果我们现在的状态比之前记录的更差，就跳过
        # 注意：这里需要比较元组 (bottleneck, hops)
        if (curr_bottleneck, curr_hops) > best_stats[u]:
            continue
        
        for v, attr in G[u].items():
            edge_weight = attr.get(weight_key, float('inf'))
            
            # 计算新的瓶颈值：max(之前路径的瓶颈, 当前边的权重)
            new_bottleneck = max(curr_bottleneck, edge_weight)
            new_hops = curr_hops + 1
            
            # 核心松弛操作：如果发现了 (瓶颈更小) 或者 (瓶颈一样但跳数更少) 的路径
            if (new_bottleneck, new_hops) < best_stats[v]:
                best_stats[v] = (new_bottleneck, new_hops)
                predecessors[v] = u
                heapq.heappush(pq, (new_bottleneck, new_hops, v))
                
    # --- 路径回溯重构 ---
    if target not in predecessors:
        return None, float('inf') # 无法到达
    
    path = []
    curr = target
    while curr is not None:
        path.append(curr)
        curr = predecessors[curr]
    path.reverse() # 翻转得到从源到目标的顺序
    
    return path, best_stats[target][0] # 返回 (路径列表, 瓶颈值)
# ===================================================

def process_routing_tasks(route_file, G):
    """读取路由任务文件，计算 Minimax 路径"""
    print(f"\n正在读取路由任务: {route_file} ...")
    try:
        tasks_df = pd.read_csv(route_file)
        results = []
        
        print(f"共找到 {len(tasks_df)} 个路由任务，开始计算瓶颈路径...")
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
                task_result['Max_Link_Penalty'] = -1
                task_result['Total_ISL_Distance_km'] = -1
            else:
                # --- 核心修改：调用自定义的 Minimax 算法 ---
                path, bottleneck_val = get_minimax_path(G, src_sat, tgt_sat, weight_key='weight')
                
                if path:
                    task_result['Path'] = " -> ".join(path)
                    task_result['Path_List'] = path
                    task_result['Hops'] = len(path) - 1
                    
                    # 记录这条路径上的最大代价 (瓶颈)
                    task_result['Max_Link_Penalty'] = bottleneck_val 
                    
                    # 虽然算法不以总距离为优，但统计总距离仍有参考价值
                    # 我们需要手动把路径上的边权加起来
                    total_dist = 0
                    for i in range(len(path) - 1):
                        u, v = path[i], path[i+1]
                        total_dist += G[u][v]['weight']
                    
                    task_result['Total_ISL_Distance_km'] = total_dist
                    task_result['Total_Link_Distance_km'] = total_dist + row.get('SourceDist_km', 0) + row.get('TargetDist_km', 0)
                    
                else:
                    task_result['Path'] = "No Path"
                    task_result['Max_Link_Penalty'] = -1
                    task_result['Total_ISL_Distance_km'] = -1

            results.append(task_result)

        return pd.DataFrame(results)

    except FileNotFoundError:
        print(f"错误: 找不到文件 {route_file}")
        return pd.DataFrame()

def visualize_single_route(G, task_row, output_img):
    """可视化单个路由任务 (逻辑基本不变，仅更新标题)"""
    src = task_row['SourceSat']
    tgt = task_row['TargetSat']
    path = task_row['Path_List']
    # 优先显示瓶颈值，其次显示总距离
    bottleneck = task_row.get('Max_Link_Penalty', 0)
    dist = task_row.get('Total_ISL_Distance_km', 0)

    if path is None:
        print(f"无法可视化: {src} -> {tgt} 没有有效路径。")
        return

    print(f"\n开始绘制路径可视化: {src} -> {tgt} ...")
    plt.figure(figsize=(15, 10))
    
    print("正在计算节点布局 (Spring Layout)...")
    pos = nx.spring_layout(G, k=0.15, iterations=50, seed=42)

    nx.draw_networkx_nodes(G, pos, node_size=20, node_color='lightgray', alpha=0.5)
    nx.draw_networkx_edges(G, pos, width=0.5, edge_color='lightgray', alpha=0.3)

    path_edges = list(zip(path, path[1:]))
    nx.draw_networkx_nodes(G, pos, nodelist=path, node_size=100, node_color='red')
    nx.draw_networkx_edges(G, pos, edgelist=path_edges, width=2.5, edge_color='red')
    
    nx.draw_networkx_nodes(G, pos, nodelist=[src], node_size=300, node_color='blue', label='Source')
    nx.draw_networkx_nodes(G, pos, nodelist=[tgt], node_size=300, node_color='green', label='Target')
    
    path_labels = {node: node for node in path}
    nx.draw_networkx_labels(G, pos, labels=path_labels, font_size=8, font_color='black', verticalalignment='bottom')
    
    # 标题更新，强调瓶颈值
    plt.title(f"Satellite Minimax Path (Bottleneck Optimization)\n{src} -> {tgt}\nMax Penalty: {bottleneck:.1f} | Hops: {len(path)-1} | Total Dist: {dist:.1f} km", fontsize=14)
    plt.legend(['All Nodes', 'Path Nodes', 'Source', 'Target'], loc='upper right')
    plt.axis('off')
    
    plt.savefig(output_img, dpi=300, bbox_inches='tight')
    print(f"可视化图表已保存为: {output_img}")

# ================= 主程序 =================
if __name__ == "__main__":
    if not os.path.exists(VISIBILITY_FILE) or not os.path.exists(ROUTE_FILE):
        print("错误: 输入文件不存在，请检查路径配置。")
        exit()

    satellite_graph = build_satellite_network(VISIBILITY_FILE)

    if satellite_graph:
        routing_results_df = process_routing_tasks(ROUTE_FILE, satellite_graph)
        
        if not routing_results_df.empty:
            csv_df = routing_results_df.drop(columns=['Path_List'], errors='ignore')
            csv_df.to_csv(OUTPUT_ROUTES_CSV, index=False)
            print(f"\n所有路由计算完成，结果已保存至: {OUTPUT_ROUTES_CSV}")
            
            # 显示关键列：加入了 Max_Link_Penalty
            cols_to_show = ['SourceSat', 'TargetSat', 'Hops', 'Max_Link_Penalty', 'Total_ISL_Distance_km']
            # 防止列名不存在报错
            existing_cols = [c for c in cols_to_show if c in csv_df.columns]
            print("前 5 条结果预览:")
            print(csv_df[existing_cols].head())

            successful_tasks = routing_results_df[routing_results_df['Total_ISL_Distance_km'] > 0]
            if not successful_tasks.empty:
                first_task = successful_tasks.iloc[0]
                visualize_single_route(satellite_graph, first_task, OUTPUT_IMAGE_FILE)
            else:
                print("\n没有找到任何成功的路由路径，无法进行可视化。")