# 工作室工具独立仓库 · 自助建仓指南

> 目标：给「内容工作室」桌面工具建一个独立的 GitHub 私有仓库（名字 `gongzuoshi`），把它推上去，避免以后跟游戏主仓库混在一起、或工具改坏时丢失历史。

## 背景（为什么需要这一步）

- 当前游戏主仓库 `wuxia-game`（私有，SSH 可推代码）。

- 但**新建一个仓库**必须走 GitHub 的「网页」或「接口」通道；你的电脑网页通道被封/超时，只有 SSH 能用，而 SSH 无法建仓。

- 解决办法：开一个能访问 GitHub 的途径（VPN / 手机 / 其它能上 GitHub 的设备），然后任选下面一种方式建仓。

***

## 方案 A：电脑开 VPN 后，我用 gh 一键建仓（最省事，推荐）

1. 打开你的 VPN 客户端，连接一个能访问 `github.com` 的节点。
2. 回到对话告诉我「好了，VPN 已开」。
3. 我会自动完成：

   - 检测网络是否通；

   - 安装 GitHub 官方命令行工具 `gh`；

   - 用你的 GitHub 账号登录；

   - 新建私有仓库 `gongzuoshi`；

   - 把工作室工具推上去。
4. 全程你只需在浏览器弹窗里点一次「Authorize 授权」。

## 方案 B：手机网页手动建仓（不依赖电脑网络）

1. 手机浏览器打开 `https://github.com/login`，登录你的账号（asiuuua）。
2. 右上角 **+** → **New repository**（新建仓库）。
3. 填：

   - Repository name：`gongzuoshi`

   - 确保 **Private**（私有）被选中（很重要，别选成 Public）

   - **不要**勾选 "Add a README / .gitignore / license"

   - 点 **Create repository**
4. 建好后看页面，把红色框里的仓库地址（形如 `git@github.com:asiuuua/gongzuoshi.git`）记下来，**发给我**。
5. 剩下的推送我来做。

## 方案 C：完全自己操作（备用）

如果你不想我来，手动步骤：

```bash
# 1. 复制工作室工具到独立目录
cd Desktop
cp -r "D:/武侠游戏/tools/desktop_studio" studio_repo

# 2. 打开 studio_repo，初始化仓库
cd studio_repo
git init
git add -A
git commit -m "init: 内容工作室工具"

# 3. 添加远端（用你建好的 gongzuoshi 仓库地址）
git remote add origin git@github.com:asiuuua/gongzuoshi.git
git branch -M master
git push -u origin master
```

***

## 建完后我会做的验证

- 确认新仓库 `gongzuoshi` 是 **Private**（私有）。

- 确认工作室核心文件（index.html、studio\_server.py、studio\_core.py、studio\_launcher.bat）都推上去了。

- 确认电脑上原工具仍正常（不破坏游戏主仓库）。

