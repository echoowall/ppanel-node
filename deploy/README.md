# ppnode（源进源出版）部署说明

这是 `perfect-panel/ppanel-node` 的定制 fork，改动只有一处：**启用 xray 的 `sendThrough: "origin"`**，
让节点在 **host 网络、单网卡多 IP** 的机器上实现「源进源出」——客户端连哪个 IP 进来，出站就从哪个 IP 出去（TCP / UDP 均生效）。

- 改动位置：`core/outbound/outbound.go`（取消注释两行，启用 `origin`）。
- UDP 正确性：依赖 xray-core `#5030`（v25.8.29）的 origin UDP 修复，当前锁定的 `wyx2685/xray-core` fork 已包含。
- 单进程即可覆盖任意多个 IP（inbound 监听 `0.0.0.0`，origin 按每条连接动态取入站 IP），**不需要多进程 / 多容器**，性能开销最小。

## 一、拿到二进制（GitHub 自动 build，无需本地装 Go）

每次 build 会更新一个滚动 Release（tag `origin-latest`），下载 URL 固定不变，直接 wget：

```bash
# amd64（绝大多数服务器）
wget https://github.com/echoowall/ppanel-node/releases/latest/download/ppnode-linux-amd64-origin.tar.gz
# arm64
wget https://github.com/echoowall/ppanel-node/releases/latest/download/ppnode-linux-arm64-origin.tar.gz
```

内含：`ppnode` 二进制 + `geoip.dat` + `geosite.dat`。

手动触发一次构建：**Actions → Sync upstream and build (origin-enabled) → Run workflow**（每周一也会自动跑）。

> 该 workflow 每次都会先合并上游（自动跟进 xray 内核 / 功能更新），再打上 origin 补丁编译并刷新 `origin-latest`；
> 若上游改动与本补丁冲突，workflow 会失败并提示手动处理 `core/outbound/outbound.go`。

## 二、部署（systemd）

```bash
# 1. 放置二进制与 geo 数据
tar xzf ppnode-linux-amd64-origin.tar.gz
install -m 0755 ppnode /usr/local/bin/ppnode
mkdir -p /etc/PPanel-node
install -m 0644 geoip.dat geosite.dat /etc/PPanel-node/   # 若 config 指定了 geo 路径

# 2. 准备配置（面板节点的 apikey / server 等），路径固定为：
#    /etc/PPanel-node/config.yml

# 3. 安装 systemd 服务
install -m 0644 deploy/ppnode.service /etc/systemd/system/ppnode.service
systemctl daemon-reload
systemctl enable --now ppnode
systemctl status ppnode
journalctl -u ppnode -f
```

## 三、单网卡多 IP：上线前自检

源进源出靠内核绑定源 IP 出站，上线前确认每个 IP 都能作为出站源：

```bash
ip -brief addr                    # 确认 ip1 / ip2 … 都挂在网卡上
ping -I 133.x.x.2 -c2 1.1.1.1     # 用 ip2 作源地址能通，说明该 IP 可出站
```

若绑源 IP 出站被丢包，检查反向路径过滤（**同网卡多 IP 建议 0 或 2，避免 1**）：

```bash
sysctl net.ipv4.conf.all.rp_filter
# 需要时：
# sysctl -w net.ipv4.conf.all.rp_filter=2
```

## 四、验证源进源出

分别用 ip1、ip2 连接节点后，在客户端访问查看出口 IP 的服务（如 `curl ifconfig.me`）：
出口 IP 应与你连接所用的入口 IP 一致；UDP 可用基于 QUIC/UDP 的目标测试（出口同样应为入口 IP）。
