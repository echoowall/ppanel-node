# PPanel-node（origin 版 / 源进源出）

Fork of [perfect-panel/ppanel-node](https://github.com/perfect-panel/ppanel-node)（基于 xray-core，modified from v2node）。

**本 fork 唯一改动**：启用 xray 的 `sendThrough: "origin"`，让 **host 网络、单网卡多 IP** 的节点实现「源进源出」——客户端连哪个本机 IP 进来，出站就从哪个 IP 出去（TCP / UDP 均生效）。单进程即可覆盖任意多个 IP，无需多进程 / docker。

> UDP 正确性依赖 xray-core [#5030](https://github.com/XTLS/Xray-core/pull/5030)（v25.8.29）的修复，当前锁定的 xray fork 已包含。
> ⚠️ 更新一律「重跑一键脚本」；**不要用 `ppnode update`**，那会从官方仓库把二进制覆盖成非 origin 版。

## 一键安装 / 更新

root 下执行（重跑即更新，自动保留现有 config）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/echoowall/ppanel-node/master/scripts/install-origin.sh) \
  --api-host https://你的面板API --server-id 节点ID --secret-key 通讯密钥
```

不带参数则进入交互式向导。

## 直接下载二进制（固定 URL，指向 origin-latest 滚动发布）

```bash
# amd64
wget https://github.com/echoowall/ppanel-node/releases/latest/download/ppnode-linux-amd64-origin.tar.gz
# arm64
wget https://github.com/echoowall/ppanel-node/releases/latest/download/ppnode-linux-arm64-origin.tar.gz
```

CI 每周一自动合并上游（跟进 xray 内核 / 功能更新）→ 打 origin 补丁编译 → 刷新以上 release。
多 IP 部署与自检详见 [`deploy/README.md`](deploy/README.md)。

## 构建

```bash
GOEXPERIMENT=jsonv2 go build -v -o ./ppnode -trimpath -ldflags "-s -w -buildid="
```

源进源出改动位于 `core/outbound/outbound.go`（取消注释 `sendThrough: "origin"` 两行即为本 fork）。
