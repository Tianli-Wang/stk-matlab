import matplotlib.pyplot as plt
import cartopy.crs as ccrs

plt.figure(figsize=(12, 6))
ax = plt.axes(projection=ccrs.PlateCarree())
# 使用自带的 Stock Image (非常像 STK 的底图)
ax.stock_img()
# 添加网格
ax.gridlines(draw_labels=True)
plt.show()