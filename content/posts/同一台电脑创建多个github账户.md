---
title: "同一台电脑创建多个github账户"
date: 2021-12-04T21:52:55+08:00
draft: false
---

通常我们会有一个工作的gitlab账户、还会有一个github私人账号用，或者有两个及以上的github账号，所以在同一台电脑上会存在多个`github`账户的情况，此时默认的githug配置不在生效，我们要先清除掉之前设置的全局`github 用户名和邮箱`。
<!--more-->

## 1.配置仓库设置

### 1.1 清除全局配置
```javascript
git config --global --unset 'user.name'
git config --global --unset 'user.email'
```
### 1.2 设置local配置
然后不同的git项目需要单独配置一次

```javascript
git config user.name "your_name"
git config user.email "your_email@example.com"
```
所以，以后我们的项目也**只能使用ssh方式操作**。

## 2. 生成多个`ssh key`
既然我们需要多个`github`账户，就需要多个独立的`ssh key`。
1. 查看电脑上所有的`ssh key`，`ls -al ~/.ssh`
2. 采用rsa老算法生成`ssh key`, 使用`ssh-keygen -t rsa -b 4096 -C "your_email@example.com"`，这里要格外注意第二次生成时，要起另一个名字，例如默认名字会是`id_rsa`，此时我们输入一个`id_rsa_wsl`，`.ssh`目录下就会用两对不同的公私钥了，新的ed25519算法生成公私钥的`ssh-keygen -t ed25519 -C "your_email@example.com"`暂时不知道如何配置下一章的`ssh config`。
![目录结构](/images/createMd/sshkey.png)
3. 分别在不同账户下的GitHub的设置中[粘贴ssh key 公钥](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)，`pbcopy < ~/.ssh/id_rsa.pub`
## 3. 配置ssh config
如果在`.ssh`目录下没有`config`文件，需要创建`touch ~/.ssh/config`,
修改`config`，以我的配置文件为例，默认经常使用的`github`账户为账户1，生成ssh key 时直接使用默认的，账户2采用别名`id_rsa_wsl`，配置文件中的**Host名字**一定不能一样，对后面不同账户的的git 操作极为重要,以下是配置文件内容：
```
# github 账户1
Host github.com
HostName github.com
PreferredAuthentications publickey
IdentityFile ~/.ssh/id_rsa

# 账户2
Host wsl
HostName github.com
PreferredAuthentications publickey
IdentityFile ~/.ssh/id_rsa_wsl
```

配置完了上述操作后，测试一下

```javascript
ssh -T git@github.com
ssh -T git@wsl
```
上面@后面的那个就是config中的那个`Host名字`，配置啥都可以，只要这里保持一致即可。

## 注意
因为我们有了多个GitHub账户，就不能再使用默认配置了，以后不同项目的克隆和提交啥的操作，对于不同的项目ssh url要修改一下，例如我们的账户2需要克隆时修改一下：
```
git@github.com:github用户名/仓库名.git
修改为
git@wsl:github用户名/仓库名.git
```
在ssh操作中中，url的@与:之间就是Host。

为了方便起见，我们在每个git项目的`.git/config`下可以直接更改`remote "origin"]`。
```
[core]
        repositoryformatversion = 0
        filemode = true
        bare = false
        logallrefupdates = true
        ignorecase = true
        precomposeunicode = true
[remote "origin"]
        url = git@wsl:wushao666/blog-generator.git //这里的Host名字改成对应的即可
        fetch = +refs/heads/*:refs/remotes/origin/*
[branch "main"]
        remote = origin
        merge = refs/heads/main
```

