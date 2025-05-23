---
title: "hugo搭建博客"
date: 2021-12-04T15:10:38+08:00
draft: false

tags: ["hugo"]
categories: ["hugo"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---

## 前言

> 写作是每个人都必备的技能，它可以帮你梳理逻辑，检查自己的思考过程。进入互联网时代后，手写文章的机会变得少了，使用网络博客的机会和场景变得多了起来，无论是自己做技术总结、公司写技术方案都需要博客，工具千千万，但是要想写的好文章却是要一直打磨。我从17年到今天之前我都是用的`hexo`搭建的博客，`hexo`是用`javascript`写的静态博客框架，使用起来也挺方便，但是安装过程和后续换电脑或者更新过后可能会遇到一些各种`bug`，后来被前辈老师朋友们安利[hugo](https://gohugo.io/)，它使用`go`写的，安装、运行都速度极快，对新手极为友好，故今天开始用它重新更新博客，并记录一下搭建的过程。

<!--more-->

## 1. 搭建博客站点

### 1.1 安装`hugo`

```javascript
//mac 直接通过brew
brew install hugo
//Win10 通过安装包，并配置环境变量
//https://gohugo.io/getting-started/quick-start/
```
因为不同的版本配置差异很大，我用的还是老版本，已经适应了这个版本，所以我会锁版本
### 1.2 锁版本0.92.2
直接下载官方预编译二进制文件（全平台通用）

Hugo 官方在 GitHub Releases 页面提供了各系统的预编译二进制文件，支持手动安装指定版本。

操作步骤（以 macOS ARM64 为例）：
1. 访问 Releases 页面：打开 Hugo Releases，找到目标版本（如 v0.92.2）。
2. 下载对应系统的安装包：
macOS（ARM64）：下载文件名包含 darwin-arm64 的压缩包（如 hugo_0.92.2_Darwin-ARM64.tar.gz）。
- macOS（x86_64）：下载 darwin-amd64 版本。
- Linux（x86_64）：下载 linux-amd64 版本。
- Windows（x64）：下载 windows-amd64.zip。

3. *macOS/Linux 示例（假设下载到 ~/Downloads 目录）*
`VERSION=0.92.2`
解压并安装：
```bash
# mac的话，在你下载目录下，解压当前二进制压缩包 到hugo目录
tar -xzvf hugo_extended_0.92.2_macOS-ARM64.tar.gz hugo
# 移动解压的目录到系统可执行目录下
sudo mv hugo /usr/local/bin/
```
Windows：解压后将 hugo.exe 复制到任意添加到系统环境变量的目录（如 C:\Program Files\hugo）。
验证安装：
```bash
hugo version  # 应显示指定版本（如 Hugo 0.92.2）
# 因为我们是使用的二进制文件，mac下会报安全错误，去系统设置允许访问就行
```

### 1.3 创建博客生成器
安装完之后，使用自带命令迅速生成博客站点`hugo new site 你的博客名字`，这里的博客名字替换成你想命名的英文名字，一般格式是用`你的github名字.github.io-generator`比较好，例如我`github`名字叫`wushao666`，就用`hugo new site wushao666.github.io-generator`。
执行完上述代码后，会在当前目录下生成一个以`你的博客名字`命名的目录。

### 1.4 添加基础主题
经过上述两步之后，我们已经有了基础的博客站点，但是目前还不能使用，我们需要安装一个基础主题ananke

```javascript
cd 你的博客名字
git init
git submodule add https://github.com/theNewDynamic/gohugo-theme-ananke.git themes/ananke
echo theme = \"ananke\" >> config.toml
```
### 1.5 创建博客
`hugo new posts/my-first-post.md`，其中`my-first-post.md`即要创建的博客名字，可随意替换(如果是`even`主题，用`hugo new post/my-first-post.md`)
此时我们的目录结构如下：
![目录结构](/images/createMd/dir.png)
此时打开刚才新建的文章，做一下小修改：

```md
---
title: "My First Post"
date: 2019-03-26T08:47:11+01:00
draft: true //正式发布是需要改为false，这是草稿
---
```
***
小tips: 在`hugo`中插入图片，可以不借助在线图床，使用根目录下的`static`完成，例如我们在其目录下创建`/images/createMd`，那么文章中插入图片`dir.png`只需要用`![](/images/createMd/dir.png)`即可。
***

### 1.6 修改基本配置
项目根目录下`config.toml`修改一下`baseURL languageCode`：

```md
baseURL = 'http://wushao666.github.io/' //这里是你的github pages的URL或者你的个人域名
languageCode = 'zh-Hans' //中文汉字简体语言
title = '吴少林写字的地方'
theme = "ananke"
```
### 1.7 本地预览与打包发布
- 本地预览，经过上述几步简单操作，此时我们的博客基本站点已经完成，并且有了一篇文章，我们通过命令`hugo server -D`进行本地预览一下，看看效果咋样再决定是否发布
- 打包发布静态页面，如果上面预览没问题了，就打包静态文件，发布到网上`hugo -D`
- 每次更新了新文章都要重新`build`，即每次都要执行`hugo -D`

最终我们发布到网上的是根目录下的`public`目录，所以我们通常的操作是把在generator生成器的仓库中的public目录不提交，而是拷贝该目录到下一小节的真正的博客展示仓库中去，通过真正的博客展示仓库展现blog。

## 2. 发布博客

以上我们只是创建完了本地博客，那么如何发布到`github`上呢，我们需要做两件事：
1. 创建博客生成器仓库，该仓库用来生成博客，备份生成器文件。
2. 创建博客静态页仓库，该仓库才是真正的博客地址。

### 2.1 创建博客生成器仓库
在`git init`当前目录（即以`你的博客站点名字`命名的那个目录，在本文中即为图中的`wushao666.github.io-generator`目录）时，需要做如下两步操作：
- 在根目录创建`.gitignore`文件，所有的命令如下：

```sh
touch .gitignore
vim .gitignore
//写入/public/
```
生成器仓库不需要存储静态文件

- 清除掉下载的主题的`.git`目录，即`rm -rf themes/ananke/.git`

此时再执行初始化仓库，上传到`github`即可。

### 2.2 创建博客静态页仓库
该仓库命名必须叫`你的github名字.github.io`，例如本文中就叫`wushao666.github.io`
这个仓库我们只需要初始化`pulic`目录即可，`git init`完并上传到`github`后，还需要打开`github Pages`
![打开githubpages](/images/createMd/githubPages.png)

完成以上操作就能够在浏览器输入`你的github名字.github.io`，访问你的网站了，如果你有个人域名，通过你购买域名的服务商做相关域名解析，把`你的github名字.github.io`解析到你的域名上即可。