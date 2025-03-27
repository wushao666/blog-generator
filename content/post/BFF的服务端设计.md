---
title: "BFF的服务端设计"
date: 2025-03-26T23:30:38+08:00
draft: false

tags: ["BFF层"]
categories: ["BFF"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---

本节是BFF层设计的开端：使用koa封装服务端逻辑。
本系列中的BFF层设计是为了解决多个子应用访问的问题：
1. 避免传统的大型的一站式平台，过于复杂，牺牲了灵活性
2. 避免开发各个子系统的过度灵活性。

通过职责单一的模块化开发，配合动态模版生成来做BFF设计。

基本的BFF架构如图：
![nova-core](/images/nova-bff/BFF-structure.png)
## 服务端设计
通过koa中间件洋葱圈模型，来处理api请求和页面请求，设计如图：
![nova-core](/images/nova-bff/nova-core-structure.png)
通过实现自定义的loader来串联整个洋葱圈模型。

1. 中间件请求时，按照从左 -> 右顺序，
2. 响应时，按照从右 -> 左响应。

具体来说：
有7个全局中间件，顺序是:
1. api错误处理中间件
2. 静态资源目录
3. 模版渲染中间件
4. 请求超时校验中间件
5. 请求体解析中间件
6. api签名验证中间件
7. api参数校验中间件

请求时，按照1 -> 7的顺序依次执行
响应时，按照7 -> 1的顺序依次响应

错误处理从当前中间件先处理，如果没有处理则依次往上冒泡，直到被最外层错误处理中间件捕获
再加上router的两个中间件，整个架构设计用了9个中间件：

完整顺序就是：
1. api错误处理中间件
2. 静态资源目录
3. 模版渲染中间件
4. 请求超时校验中间件
5. 请求体解析中间件
6. api签名验证中间件
7. api参数校验中间件
8. router中间件
9. router方法校验中间件

8、9是router中间件，是koa-router的中间件，是koa-router的实例方法,可以当成一个大的路由中间件就行。

处理顺序有点小区别:

因为路由方法校验中间件需要获取路由方法
- 匹配到路由就执行路由处理函数
- 没匹配到就交给校验方法处理
例如要post请求，但是请求的是get
就会走到校验方法处理，设置状态码为405

这种设计可以：
1. 确保路由匹配优先于方法校验
2. 避免为不存在的路由返回405错误
```javascript
  app.use(koaRouter.routes())
  app.use(koaRouter.allowedMethods())
```